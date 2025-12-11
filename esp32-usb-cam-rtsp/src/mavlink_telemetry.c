/**
 * @file mavlink_telemetry.c
 * @brief MAVLink telemetri modülü (UDP bridge)
 */

#include "mavlink_telemetry.h"
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "driver/uart.h"
#include "lwip/sockets.h"

static const char *TAG = "MAVLINK";

#define UART_BUF_SIZE 1024
#define UDP_BUF_SIZE 1024

static struct {
    bool initialized;
    bool running;
    mavlink_config_t config;
    int udp_sock;
    struct sockaddr_in gcs_addr;
    bool gcs_connected;
    TaskHandle_t uart_task;
    TaskHandle_t udp_task;
} s_mav = {0};

// UART -> UDP task
static void uart_to_udp_task(void *arg)
{
    uint8_t *buf = malloc(UART_BUF_SIZE);
    if (!buf) {
        vTaskDelete(NULL);
        return;
    }
    
    while (s_mav.running) {
        int len = uart_read_bytes(s_mav.config.uart_num, buf, UART_BUF_SIZE, pdMS_TO_TICKS(50));
        if (len > 0 && s_mav.gcs_connected) {
            sendto(s_mav.udp_sock, buf, len, 0, 
                   (struct sockaddr *)&s_mav.gcs_addr, sizeof(s_mav.gcs_addr));
        }
    }
    
    free(buf);
    vTaskDelete(NULL);
}

// UDP -> UART task
static void udp_to_uart_task(void *arg)
{
    uint8_t *buf = malloc(UDP_BUF_SIZE);
    if (!buf) {
        vTaskDelete(NULL);
        return;
    }
    
    struct sockaddr_in client_addr;
    socklen_t addr_len = sizeof(client_addr);
    
    while (s_mav.running) {
        int len = recvfrom(s_mav.udp_sock, buf, UDP_BUF_SIZE, 0,
                          (struct sockaddr *)&client_addr, &addr_len);
        if (len > 0) {
            // GCS adresini kaydet
            if (!s_mav.gcs_connected || 
                memcmp(&s_mav.gcs_addr, &client_addr, sizeof(client_addr)) != 0) {
                memcpy(&s_mav.gcs_addr, &client_addr, sizeof(client_addr));
                s_mav.gcs_connected = true;
                char ip_str[16];
                inet_ntoa_r(client_addr.sin_addr, ip_str, sizeof(ip_str));
                ESP_LOGI(TAG, "GCS connected: %s:%d", ip_str, ntohs(client_addr.sin_port));
            }
            
            // UART'a gönder
            uart_write_bytes(s_mav.config.uart_num, buf, len);
        }
    }
    
    free(buf);
    vTaskDelete(NULL);
}

esp_err_t mavlink_telemetry_init(const mavlink_config_t *config)
{
    if (s_mav.initialized) {
        return ESP_OK;
    }
    
    if (config) {
        memcpy(&s_mav.config, config, sizeof(mavlink_config_t));
    } else {
        s_mav.config.uart_num = MAVLINK_UART_NUM;
        s_mav.config.uart_tx_pin = MAVLINK_UART_TX_PIN;
        s_mav.config.uart_rx_pin = MAVLINK_UART_RX_PIN;
        s_mav.config.uart_baud = MAVLINK_UART_BAUD;
        s_mav.config.udp_port = MAVLINK_UDP_PORT;
    }
    
    // UART başlat
    uart_config_t uart_config = {
        .baud_rate = s_mav.config.uart_baud,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };
    
    ESP_ERROR_CHECK(uart_driver_install(s_mav.config.uart_num, UART_BUF_SIZE * 2, UART_BUF_SIZE * 2, 0, NULL, 0));
    ESP_ERROR_CHECK(uart_param_config(s_mav.config.uart_num, &uart_config));
    ESP_ERROR_CHECK(uart_set_pin(s_mav.config.uart_num, 
                                  s_mav.config.uart_tx_pin, 
                                  s_mav.config.uart_rx_pin, 
                                  UART_PIN_NO_CHANGE, 
                                  UART_PIN_NO_CHANGE));
    
    // UDP socket
    s_mav.udp_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s_mav.udp_sock < 0) {
        ESP_LOGE(TAG, "Socket create failed");
        return ESP_FAIL;
    }
    
    // Non-blocking
    int flags = fcntl(s_mav.udp_sock, F_GETFL, 0);
    fcntl(s_mav.udp_sock, F_SETFL, flags | O_NONBLOCK);
    
    // Timeout
    struct timeval timeout = { .tv_sec = 0, .tv_usec = 100000 };  // 100ms
    setsockopt(s_mav.udp_sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    
    // Bind
    struct sockaddr_in bind_addr = {
        .sin_family = AF_INET,
        .sin_port = htons(s_mav.config.udp_port),
        .sin_addr.s_addr = htonl(INADDR_ANY),
    };
    
    if (bind(s_mav.udp_sock, (struct sockaddr *)&bind_addr, sizeof(bind_addr)) < 0) {
        ESP_LOGE(TAG, "Socket bind failed");
        close(s_mav.udp_sock);
        return ESP_FAIL;
    }
    
    s_mav.initialized = true;
    return ESP_OK;
}

esp_err_t mavlink_telemetry_deinit(void)
{
    mavlink_telemetry_stop();
    
    if (s_mav.udp_sock >= 0) {
        close(s_mav.udp_sock);
        s_mav.udp_sock = -1;
    }
    
    uart_driver_delete(s_mav.config.uart_num);
    s_mav.initialized = false;
    
    return ESP_OK;
}

esp_err_t mavlink_telemetry_start(void)
{
    if (!s_mav.initialized || s_mav.running) {
        return ESP_ERR_INVALID_STATE;
    }
    
    s_mav.running = true;
    
    xTaskCreate(uart_to_udp_task, "mav_uart", 4096, NULL, 5, &s_mav.uart_task);
    xTaskCreate(udp_to_uart_task, "mav_udp", 4096, NULL, 5, &s_mav.udp_task);
    
    return ESP_OK;
}

esp_err_t mavlink_telemetry_stop(void)
{
    s_mav.running = false;
    vTaskDelay(pdMS_TO_TICKS(200));
    return ESP_OK;
}

bool mavlink_telemetry_is_gcs_connected(void)
{
    return s_mav.gcs_connected;
}
