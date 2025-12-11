/**
 * @file rtsp_server.c
 * @brief MJPEG HTTP Streaming Server
 * 
 * Basitleştirilmiş implementasyon - MJPEG over HTTP
 * VLC ve tarayıcılarla uyumlu
 */

#include "rtsp_server.h"
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "esp_log.h"
#include "lwip/sockets.h"

static const char *TAG = "RTSP_SRV";

#define MAX_CLIENTS 4
#define BOUNDARY "frame"

// Client yapısı
typedef struct {
    int sock;
    bool active;
    uint32_t id;
} client_t;

static struct {
    bool initialized;
    bool running;
    rtsp_server_config_t config;
    int server_sock;
    client_t clients[MAX_CLIENTS];
    SemaphoreHandle_t clients_mutex;
    TaskHandle_t accept_task;
    uint32_t client_id_counter;
    
    // Current frame
    uint8_t *frame_buf;
    size_t frame_size;
    SemaphoreHandle_t frame_mutex;
} s_rtsp = {0};

// HTTP MJPEG response header
static const char *MJPEG_HEADER = 
    "HTTP/1.1 200 OK\r\n"
    "Content-Type: multipart/x-mixed-replace;boundary=" BOUNDARY "\r\n"
    "Cache-Control: no-cache\r\n"
    "Connection: close\r\n"
    "\r\n";

// Frame header template
static const char *FRAME_HEADER_FMT = 
    "--" BOUNDARY "\r\n"
    "Content-Type: image/jpeg\r\n"
    "Content-Length: %u\r\n"
    "\r\n";

// Client handler task
static void client_task(void *arg)
{
    client_t *client = (client_t *)arg;
    char header_buf[128];
    
    ESP_LOGI(TAG, "Client %lu handler started", (unsigned long)client->id);
    
    // Send MJPEG header
    send(client->sock, MJPEG_HEADER, strlen(MJPEG_HEADER), 0);
    
    while (client->active && s_rtsp.running) {
        // Wait for frame
        if (xSemaphoreTake(s_rtsp.frame_mutex, pdMS_TO_TICKS(1000)) == pdTRUE) {
            if (s_rtsp.frame_size > 0) {
                // Frame header
                int hdr_len = snprintf(header_buf, sizeof(header_buf), 
                                       FRAME_HEADER_FMT, (unsigned)s_rtsp.frame_size);
                
                // Send frame header
                int ret = send(client->sock, header_buf, hdr_len, 0);
                if (ret < 0) {
                    xSemaphoreGive(s_rtsp.frame_mutex);
                    break;
                }
                
                // Send frame data
                ret = send(client->sock, s_rtsp.frame_buf, s_rtsp.frame_size, 0);
                if (ret < 0) {
                    xSemaphoreGive(s_rtsp.frame_mutex);
                    break;
                }
                
                // Frame separator
                send(client->sock, "\r\n", 2, 0);
            }
            xSemaphoreGive(s_rtsp.frame_mutex);
        }
        
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    
    // Cleanup
    close(client->sock);
    client->active = false;
    
    if (s_rtsp.config.client_callback) {
        s_rtsp.config.client_callback(client->id, false, s_rtsp.config.callback_arg);
    }
    
    ESP_LOGI(TAG, "Client %lu disconnected", (unsigned long)client->id);
    vTaskDelete(NULL);
}

// Accept task
static void accept_task(void *arg)
{
    struct sockaddr_in client_addr;
    socklen_t addr_len = sizeof(client_addr);
    
    ESP_LOGI(TAG, "RTSP Server started: http://192.168.4.1:%d", s_rtsp.config.port);
    
    while (s_rtsp.running) {
        int client_sock = accept(s_rtsp.server_sock, (struct sockaddr *)&client_addr, &addr_len);
        if (client_sock < 0) {
            if (s_rtsp.running) {
                vTaskDelay(pdMS_TO_TICKS(100));
            }
            continue;
        }
        
        // Read HTTP request (and discard)
        char buf[256];
        recv(client_sock, buf, sizeof(buf), 0);
        
        // Find free client slot
        client_t *client = NULL;
        xSemaphoreTake(s_rtsp.clients_mutex, portMAX_DELAY);
        for (int i = 0; i < MAX_CLIENTS; i++) {
            if (!s_rtsp.clients[i].active) {
                client = &s_rtsp.clients[i];
                client->sock = client_sock;
                client->active = true;
                client->id = ++s_rtsp.client_id_counter;
                break;
            }
        }
        xSemaphoreGive(s_rtsp.clients_mutex);
        
        if (client) {
            char ip_str[16];
            inet_ntoa_r(client_addr.sin_addr, ip_str, sizeof(ip_str));
            ESP_LOGI(TAG, "Client connected from %s", ip_str);
            
            if (s_rtsp.config.client_callback) {
                s_rtsp.config.client_callback(client->id, true, s_rtsp.config.callback_arg);
            }
            
            // Start client handler
            char task_name[16];
            snprintf(task_name, sizeof(task_name), "rtsp_c%lu", (unsigned long)client->id);
            xTaskCreate(client_task, task_name, 4096, client, 4, NULL);
        } else {
            ESP_LOGW(TAG, "Max clients reached, rejecting connection");
            close(client_sock);
        }
    }
    
    vTaskDelete(NULL);
}

esp_err_t rtsp_server_init(const rtsp_server_config_t *config)
{
    if (s_rtsp.initialized) {
        return ESP_OK;
    }
    
    if (config) {
        memcpy(&s_rtsp.config, config, sizeof(rtsp_server_config_t));
    } else {
        s_rtsp.config.port = RTSP_PORT;
        s_rtsp.config.stream_name = RTSP_STREAM_NAME;
        s_rtsp.config.max_clients = RTSP_MAX_CLIENTS;
    }
    
    // Mutexler
    s_rtsp.clients_mutex = xSemaphoreCreateMutex();
    s_rtsp.frame_mutex = xSemaphoreCreateMutex();
    
    if (!s_rtsp.clients_mutex || !s_rtsp.frame_mutex) {
        return ESP_ERR_NO_MEM;
    }
    
    // Frame buffer (PSRAM'da)
    s_rtsp.frame_buf = heap_caps_malloc(100 * 1024, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!s_rtsp.frame_buf) {
        // PSRAM yoksa internal RAM
        s_rtsp.frame_buf = malloc(50 * 1024);
    }
    if (!s_rtsp.frame_buf) {
        return ESP_ERR_NO_MEM;
    }
    
    // Server socket
    s_rtsp.server_sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s_rtsp.server_sock < 0) {
        ESP_LOGE(TAG, "Socket create failed");
        return ESP_FAIL;
    }
    
    int opt = 1;
    setsockopt(s_rtsp.server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    struct sockaddr_in bind_addr = {
        .sin_family = AF_INET,
        .sin_port = htons(s_rtsp.config.port),
        .sin_addr.s_addr = htonl(INADDR_ANY),
    };
    
    if (bind(s_rtsp.server_sock, (struct sockaddr *)&bind_addr, sizeof(bind_addr)) < 0) {
        ESP_LOGE(TAG, "Socket bind failed");
        close(s_rtsp.server_sock);
        return ESP_FAIL;
    }
    
    if (listen(s_rtsp.server_sock, 4) < 0) {
        ESP_LOGE(TAG, "Socket listen failed");
        close(s_rtsp.server_sock);
        return ESP_FAIL;
    }
    
    s_rtsp.initialized = true;
    return ESP_OK;
}

esp_err_t rtsp_server_deinit(void)
{
    rtsp_server_stop();
    
    if (s_rtsp.server_sock >= 0) {
        close(s_rtsp.server_sock);
    }
    
    if (s_rtsp.frame_buf) {
        free(s_rtsp.frame_buf);
    }
    
    if (s_rtsp.clients_mutex) {
        vSemaphoreDelete(s_rtsp.clients_mutex);
    }
    
    if (s_rtsp.frame_mutex) {
        vSemaphoreDelete(s_rtsp.frame_mutex);
    }
    
    s_rtsp.initialized = false;
    return ESP_OK;
}

esp_err_t rtsp_server_start(void)
{
    if (!s_rtsp.initialized || s_rtsp.running) {
        return ESP_ERR_INVALID_STATE;
    }
    
    s_rtsp.running = true;
    xTaskCreate(accept_task, "rtsp_accept", 4096, NULL, 5, &s_rtsp.accept_task);
    
    return ESP_OK;
}

esp_err_t rtsp_server_stop(void)
{
    s_rtsp.running = false;
    
    // Close all clients
    xSemaphoreTake(s_rtsp.clients_mutex, portMAX_DELAY);
    for (int i = 0; i < MAX_CLIENTS; i++) {
        if (s_rtsp.clients[i].active) {
            close(s_rtsp.clients[i].sock);
            s_rtsp.clients[i].active = false;
        }
    }
    xSemaphoreGive(s_rtsp.clients_mutex);
    
    vTaskDelay(pdMS_TO_TICKS(200));
    return ESP_OK;
}

esp_err_t rtsp_server_send_frame(const rtsp_frame_t *frame)
{
    if (!s_rtsp.initialized || !frame || !frame->data) {
        return ESP_ERR_INVALID_ARG;
    }
    
    if (xSemaphoreTake(s_rtsp.frame_mutex, pdMS_TO_TICKS(10)) == pdTRUE) {
        size_t copy_size = frame->size;
        if (copy_size > 100 * 1024) {
            copy_size = 100 * 1024;
        }
        memcpy(s_rtsp.frame_buf, frame->data, copy_size);
        s_rtsp.frame_size = copy_size;
        xSemaphoreGive(s_rtsp.frame_mutex);
    }
    
    return ESP_OK;
}

uint8_t rtsp_server_get_client_count(void)
{
    uint8_t count = 0;
    xSemaphoreTake(s_rtsp.clients_mutex, portMAX_DELAY);
    for (int i = 0; i < MAX_CLIENTS; i++) {
        if (s_rtsp.clients[i].active) {
            count++;
        }
    }
    xSemaphoreGive(s_rtsp.clients_mutex);
    return count;
}
