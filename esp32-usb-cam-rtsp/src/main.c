/**
 * @file main.c
 * @brief ESP32-CAM MJPEG Streamer - DEBUG VERSION
 */

#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "esp_system.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#include "nvs_flash.h"

#include "wifi_ap.h"
#include "mavlink_telemetry.h"
#include "rtsp_server.h"
#include "ov2640_camera.h"
#include "esp_camera.h"
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

static const char *TAG = "MAIN";

#define MAX_FRAME_SIZE_PSRAM (80 * 1024)  // 80KB for SVGA with PSRAM
#define MAX_FRAME_SIZE_DRAM  (15 * 1024)  // 15KB for QVGA without PSRAM

typedef struct {
    uint8_t *data;
    size_t size;
    uint32_t width;
    uint32_t height;
    uint32_t sequence;
} frame_msg_t;

static QueueHandle_t s_frame_queue = NULL;
static uint8_t *s_frame_buffer = NULL;
static SemaphoreHandle_t s_frame_mutex = NULL;
static uint32_t s_frames_captured = 0;
static uint32_t s_frames_sent = 0;

// ═══════════════════════════════════════════════════════
// Callbacks
// ═══════════════════════════════════════════════════════
static void wifi_callback(wifi_ap_state_t state, void *arg)
{
    if (state == WIFI_AP_STATE_CLIENT_CONNECTED)
        ESP_LOGI(TAG, "📱 WiFi client connected");
    else if (state == WIFI_AP_STATE_CLIENT_DISCONNECTED)
        ESP_LOGI(TAG, "📱 WiFi client disconnected");
}

static void stream_client_callback(uint32_t client_id, bool connected, void *arg)
{
    ESP_LOGI(TAG, "🎥 Stream client #%lu %s", 
             (unsigned long)client_id, connected ? "CONNECTED" : "DISCONNECTED");
}

// ═══════════════════════════════════════════════════════
// CAMERA TASK - CPU0
// ═══════════════════════════════════════════════════════
static void camera_task(void *arg)
{
    ESP_LOGI(TAG, "📷 Camera task started on CPU%d", xPortGetCoreID());

    // QVGA for DRAM mode
    ov2640_config_t cam_config = {
        .framesize = FRAMESIZE_QVGA,  // 320x240
        .quality = 12,
        .fps = 15,
        .frame_callback = NULL,
        .callback_arg = NULL,
    };

    if (ov2640_init(&cam_config) != ESP_OK) {
        ESP_LOGE(TAG, "❌ Camera init failed!");
        vTaskDelete(NULL);
        return;
    }

    ESP_LOGI(TAG, "✅ Camera initialized");
    ESP_LOGI(TAG, "📸 Starting capture loop...");

    uint32_t seq = 0;
    int64_t last_log = esp_timer_get_time();

    // İlk frame'i test et
    ESP_LOGI(TAG, "📸 Attempting first capture...");
    camera_fb_t *test_fb = esp_camera_fb_get();
    if (test_fb) {
        ESP_LOGI(TAG, "✅ First frame OK: %ux%u, %u bytes", 
                 test_fb->width, test_fb->height, test_fb->len);
        esp_camera_fb_return(test_fb);
    } else {
        ESP_LOGE(TAG, "❌ First frame FAILED!");
    }

    while (1) {
        camera_fb_t *fb = esp_camera_fb_get();
        if (fb) {
            s_frames_captured++;
            
            // Her 30 frame'de bir log
            if (s_frames_captured % 30 == 0) {
                ESP_LOGI(TAG, "📸 Captured frame #%lu, size=%u bytes", 
                         (unsigned long)s_frames_captured, (unsigned)fb->len);
            }

            if (xSemaphoreTake(s_frame_mutex, pdMS_TO_TICKS(10)) == pdTRUE) {
                // Copy frame - buffer size determined at init
                memcpy(s_frame_buffer, fb->buf, fb->len);

                frame_msg_t msg = {
                    .data = s_frame_buffer,
                    .size = fb->len,
                    .width = fb->width,
                    .height = fb->height,
                    .sequence = seq++,
                };

                xSemaphoreGive(s_frame_mutex);
                xQueueOverwrite(s_frame_queue, &msg);
            }

            esp_camera_fb_return(fb);
        } else {
            ESP_LOGW(TAG, "⚠️ Capture failed!");
        }

        // Her 5 saniyede heap durumu
        int64_t now = esp_timer_get_time();
        if (now - last_log >= 5000000) {
            ESP_LOGI(TAG, "💾 Heap: %lu, Captured: %lu, Sent: %lu",
                     (unsigned long)esp_get_free_heap_size(),
                     (unsigned long)s_frames_captured,
                     (unsigned long)s_frames_sent);
            last_log = now;
        }

        vTaskDelay(pdMS_TO_TICKS(33));  // ~30fps target
    }
}

// ═══════════════════════════════════════════════════════
// STREAM SENDER TASK - CPU1
// ═══════════════════════════════════════════════════════
static void stream_sender_task(void *arg)
{
    ESP_LOGI(TAG, "📡 Stream sender started on CPU%d", xPortGetCoreID());

    frame_msg_t msg;

    while (1) {
        if (xQueueReceive(s_frame_queue, &msg, pdMS_TO_TICKS(100)) == pdTRUE) {
            if (msg.size > 0) {
                rtsp_frame_t frame = {
                    .data = msg.data,
                    .size = msg.size,
                    .capacity = msg.size,
                    .width = msg.width,
                    .height = msg.height,
                    .format = 0,
                    .timestamp = esp_timer_get_time(),
                    .sequence = msg.sequence,
                };

                rtsp_server_send_frame(&frame);
                s_frames_sent++;

                // Her 30 frame'de bir log
                if (s_frames_sent % 30 == 0) {
                    ESP_LOGI(TAG, "📤 Sent frame #%lu to server", (unsigned long)s_frames_sent);
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════
// NETWORK TASK - CPU1
// ═══════════════════════════════════════════════════════
static void network_task(void *arg)
{
    ESP_LOGI(TAG, "🌐 Network task on CPU%d", xPortGetCoreID());

    // WiFi AP
    wifi_ap_set_callback(wifi_callback, NULL);
    wifi_ap_init();
    wifi_ap_start();
    ESP_LOGI(TAG, "📶 WiFi AP: %s", WIFI_AP_SSID);

    // Stream Server
    rtsp_server_config_t stream_config = {
        .port = 8080,
        .stream_name = "stream",
        .max_clients = 2,
        .client_callback = stream_client_callback,
        .callback_arg = NULL,
    };
    
    ESP_LOGI(TAG, "🔧 Initializing stream server...");
    rtsp_server_init(&stream_config);
    
    ESP_LOGI(TAG, "🚀 Starting stream server...");
    rtsp_server_start();

    // MAVLink
    mavlink_config_t mav_config = {
        .uart_num = MAVLINK_UART_NUM,
        .uart_tx_pin = MAVLINK_UART_TX_PIN,
        .uart_rx_pin = MAVLINK_UART_RX_PIN,
        .uart_baud = MAVLINK_UART_BAUD,
        .udp_port = MAVLINK_UDP_PORT,
        .on_heartbeat = NULL,
        .callback_arg = NULL,
    };
    mavlink_telemetry_init(&mav_config);
    mavlink_telemetry_start();

    // Stream Sender task
    xTaskCreatePinnedToCore(stream_sender_task, "stream_tx", 4096, NULL, 4, NULL, 1);

    ESP_LOGI(TAG, "════════════════════════════════════════");
    ESP_LOGI(TAG, "✅ ALL SYSTEMS READY!");
    ESP_LOGI(TAG, "   WiFi: %s / %s", WIFI_AP_SSID, WIFI_AP_PASS);
    ESP_LOGI(TAG, "   Stream: http://192.168.4.1:8080/stream");
    ESP_LOGI(TAG, "════════════════════════════════════════");

    // Monitor loop
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(10000));
        ESP_LOGI(TAG, "📊 Status: Heap=%lu, Clients=%d, Cap=%lu, Sent=%lu",
                 (unsigned long)esp_get_free_heap_size(),
                 rtsp_server_get_client_count(),
                 (unsigned long)s_frames_captured,
                 (unsigned long)s_frames_sent);
    }
}

// ═══════════════════════════════════════════════════════
// APP_MAIN
// ═══════════════════════════════════════════════════════
void app_main(void)
{
    // Disable brownout detector
    WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);
    
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        nvs_flash_init();
    }

    ESP_LOGI(TAG, "════════════════════════════════════════");
    ESP_LOGI(TAG, "   ESP32-CAM DEBUG VERSION");
    ESP_LOGI(TAG, "════════════════════════════════════════");
    ESP_LOGI(TAG, "Heap: %lu bytes", (unsigned long)esp_get_free_heap_size());

    // Check PSRAM
    size_t psram_size = heap_caps_get_total_size(MALLOC_CAP_SPIRAM);
    bool has_psram = (psram_size > 0);
    size_t frame_buf_size = has_psram ? MAX_FRAME_SIZE_PSRAM : MAX_FRAME_SIZE_DRAM;
    
    if (has_psram) {
        ESP_LOGI(TAG, "✅ PSRAM: %lu KB", (unsigned long)(psram_size / 1024));
    } else {
        ESP_LOGW(TAG, "⚠️ No PSRAM detected!");
    }

    // Frame queue and buffer
    s_frame_queue = xQueueCreate(1, sizeof(frame_msg_t));
    s_frame_mutex = xSemaphoreCreateMutex();
    
    // Allocate from PSRAM if available
    if (has_psram) {
        s_frame_buffer = heap_caps_malloc(frame_buf_size, MALLOC_CAP_SPIRAM);
    } else {
        s_frame_buffer = malloc(frame_buf_size);
    }

    if (!s_frame_queue || !s_frame_mutex || !s_frame_buffer) {
        ESP_LOGE(TAG, "❌ Memory alloc failed!");
        return;
    }
    ESP_LOGI(TAG, "✅ Frame buffer: %lu KB (%s)", 
             (unsigned long)(frame_buf_size / 1024),
             has_psram ? "PSRAM" : "DRAM");

    // Camera task - CPU0
    xTaskCreatePinnedToCore(camera_task, "camera", 4096, NULL, 5, NULL, 0);

    // Network task - CPU1  
    xTaskCreatePinnedToCore(network_task, "network", 8192, NULL, 5, NULL, 1);

    ESP_LOGI(TAG, "🚀 Tasks started");
}
