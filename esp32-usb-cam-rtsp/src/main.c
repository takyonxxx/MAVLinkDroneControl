/**
 * @file main.c
 * @brief ESP32-CAM RTSP Streamer + MAVLink Telemetry
 * 
 * OV2640 kamera ile WiFi üzerinden RTSP video stream
 */

#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "esp_system.h"
#include "esp_log.h"
#include "nvs_flash.h"

#include "wifi_ap.h"
#include "mavlink_telemetry.h"
#include "rtsp_server.h"
#include "ov2640_camera.h"

static const char *TAG = "MAIN";

// Frame sayacı
static uint32_t s_frame_count = 0;

// Kamera frame callback - RTSP'ye gönder
static void camera_frame_callback(ov2640_frame_t *frame, void *arg)
{
    if (!frame || frame->size == 0) return;
    
    rtsp_frame_t rtsp_frame = {
        .data = frame->data,
        .size = frame->size,
        .capacity = frame->size,
        .width = frame->width,
        .height = frame->height,
        .format = 0,  // MJPEG
        .timestamp = frame->timestamp,
        .sequence = frame->sequence,
    };
    
    rtsp_server_send_frame(&rtsp_frame);
    
    s_frame_count++;
    if (s_frame_count % 30 == 0) {
        ESP_LOGI(TAG, "Frame #%lu: %u bytes, %.1f fps", 
                 (unsigned long)s_frame_count,
                 (unsigned)frame->size,
                 ov2640_get_fps());
    }
}

static void wifi_callback(wifi_ap_state_t state, void *arg) 
{ 
    if (state == WIFI_AP_STATE_STARTED) {
        ESP_LOGI(TAG, "WiFi AP ready");
    }
}

static void mavlink_heartbeat_callback(const mavlink_heartbeat_info_t *info, void *arg) 
{ 
    (void)info; 
    (void)arg; 
}

static void rtsp_client_callback(uint32_t client_id, bool connected, void *arg) 
{ 
    if (connected) {
        ESP_LOGI(TAG, "RTSP client %lu connected", (unsigned long)client_id);
    } else {
        ESP_LOGI(TAG, "RTSP client %lu disconnected", (unsigned long)client_id);
    }
}

void app_main(void)
{
    // NVS
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        nvs_flash_init();
    }

    ESP_LOGI(TAG, "========================================");
    ESP_LOGI(TAG, "   ESP32-CAM RTSP + MAVLink System");
    ESP_LOGI(TAG, "========================================");
    ESP_LOGI(TAG, "Free heap: %lu bytes", (unsigned long)esp_get_free_heap_size());

    // WiFi AP başlat
    wifi_ap_set_callback(wifi_callback, NULL);
    wifi_ap_init();
    wifi_ap_start();
    ESP_LOGI(TAG, "WiFi AP: %s", WIFI_AP_SSID);
    ESP_LOGI(TAG, "IP: 192.168.4.1");

    // MAVLink başlat
    mavlink_config_t mav_config = {
        .uart_num = MAVLINK_UART_NUM,
        .uart_tx_pin = MAVLINK_UART_TX_PIN,
        .uart_rx_pin = MAVLINK_UART_RX_PIN,
        .uart_baud = MAVLINK_UART_BAUD,
        .udp_port = MAVLINK_UDP_PORT,
        .on_heartbeat = mavlink_heartbeat_callback,
        .callback_arg = NULL,
    };
    mavlink_telemetry_init(&mav_config);
    mavlink_telemetry_start();
    ESP_LOGI(TAG, "MAVLink: UDP port %d", MAVLINK_UDP_PORT);

    // RTSP Server başlat
    rtsp_server_config_t rtsp_config = {
        .port = RTSP_PORT,
        .stream_name = RTSP_STREAM_NAME,
        .max_clients = RTSP_MAX_CLIENTS,
        .client_callback = rtsp_client_callback,
        .callback_arg = NULL,
    };
    rtsp_server_init(&rtsp_config);
    rtsp_server_start();
    ESP_LOGI(TAG, "RTSP: rtsp://192.168.4.1:%d/%s", RTSP_PORT, RTSP_STREAM_NAME);

    // OV2640 Kamera başlat
    ov2640_config_t cam_config = {
        .framesize = FRAMESIZE_VGA,  // 640x480
        .quality = 12,               // JPEG quality (10-63, lower=better)
        .fps = 15,
        .frame_callback = camera_frame_callback,
        .callback_arg = NULL,
    };
    
    ret = ov2640_init(&cam_config);
    if (ret == ESP_OK) {
        ov2640_start();
        ESP_LOGI(TAG, "Camera: OV2640 VGA 15fps");
    } else {
        ESP_LOGE(TAG, "Camera init failed: %s", esp_err_to_name(ret));
    }

    ESP_LOGI(TAG, "========================================");
    ESP_LOGI(TAG, "System ready!");
    ESP_LOGI(TAG, "Connect to WiFi: %s", WIFI_AP_SSID);
    ESP_LOGI(TAG, "Open VLC: rtsp://192.168.4.1:554/stream");
    ESP_LOGI(TAG, "========================================");

    // Ana döngü
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(10000));
        ESP_LOGI(TAG, "Heap: %lu bytes", (unsigned long)esp_get_free_heap_size());
    }
}
