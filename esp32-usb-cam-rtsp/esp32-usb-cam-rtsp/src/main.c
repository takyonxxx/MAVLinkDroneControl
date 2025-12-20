/**
 * @file main.c
 * @brief ESP32-CAM MJPEG Streamer with PSRAM Support
 * 
 * Features:
 * - PSRAM auto-detection (VGA with PSRAM, QVGA without)
 * - WiFi AP mode
 * - MJPEG HTTP streaming
 * - MAVLink telemetry bridge
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
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

#include "wifi_ap.h"
#include "mavlink_telemetry.h"
#include "rtsp_server.h"
#include "ov2640_camera.h"
#include "esp_camera.h"

static const char *TAG = "MAIN";

// Frame buffer sizes
#define MAX_FRAME_SIZE_PSRAM (100 * 1024)  // 100KB for VGA/SVGA with PSRAM
#define MAX_FRAME_SIZE_DRAM  (20 * 1024)   // 20KB for QVGA without PSRAM

typedef struct {
    uint8_t *data;
    size_t size;
    uint32_t width;
    uint32_t height;
    uint32_t sequence;
} frame_msg_t;

static QueueHandle_t s_frame_queue = NULL;
static uint8_t *s_frame_buffer = NULL;
static size_t s_frame_buffer_size = 0;
static SemaphoreHandle_t s_frame_mutex = NULL;
static uint32_t s_frames_captured = 0;
static uint32_t s_frames_sent = 0;
static bool s_has_psram = false;

// ═══════════════════════════════════════════════════════
// Callbacks
// ═══════════════════════════════════════════════════════
static void wifi_callback(wifi_ap_state_t state, void *arg)
{
    if (state == WIFI_AP_STATE_CLIENT_CONNECTED) {
        ESP_LOGI(TAG, "📱 WiFi client connected");
    } else if (state == WIFI_AP_STATE_CLIENT_DISCONNECTED) {
        ESP_LOGI(TAG, "📱 WiFi client disconnected");
    }
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

    // Configure based on PSRAM availability
    ov2640_config_t cam_config = {
        .framesize = s_has_psram ? FRAMESIZE_VGA : FRAMESIZE_QVGA,
        .quality = s_has_psram ? 10 : 12,
        .fps = 30,
        .frame_callback = NULL,
        .callback_arg = NULL,
    };

    if (ov2640_init(&cam_config) != ESP_OK) {
        ESP_LOGE(TAG, "❌ Camera init failed!");
        vTaskDelete(NULL);
        return;
    }

    const char *res_str = s_has_psram ? "VGA 640x480" : "QVGA 320x240";
    ESP_LOGI(TAG, "✅ Camera ready: %s", res_str);

    // Test first frame
    ESP_LOGI(TAG, "📸 Testing first capture...");
    camera_fb_t *test_fb = esp_camera_fb_get();
    if (test_fb) {
        ESP_LOGI(TAG, "✅ First frame: %ux%u, %u bytes", 
                 test_fb->width, test_fb->height, test_fb->len);
        esp_camera_fb_return(test_fb);
    } else {
        ESP_LOGE(TAG, "❌ First capture failed!");
    }

    uint32_t seq = 0;
    int64_t last_stats = esp_timer_get_time();
    uint32_t stats_frames = 0;

    while (1) {
        camera_fb_t *fb = esp_camera_fb_get();
        if (fb) {
            s_frames_captured++;
            stats_frames++;

            if (xSemaphoreTake(s_frame_mutex, pdMS_TO_TICKS(10)) == pdTRUE) {
                // Copy frame if it fits
                if (fb->len <= s_frame_buffer_size) {
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
                } else {
                    xSemaphoreGive(s_frame_mutex);
                    ESP_LOGW(TAG, "Frame too large: %u > %u", fb->len, s_frame_buffer_size);
                }
            }

            esp_camera_fb_return(fb);
        } else {
            ESP_LOGW(TAG, "⚠️ Capture failed!");
            vTaskDelay(pdMS_TO_TICKS(100));
            continue;
        }

        // Stats every 5 seconds
        int64_t now = esp_timer_get_time();
        if (now - last_stats >= 5000000) {
            float fps = (float)stats_frames * 1000000.0f / (float)(now - last_stats);
            ESP_LOGI(TAG, "📊 Capture: %.1f fps, Heap: %lu KB", 
                     fps, (unsigned long)(esp_get_free_heap_size() / 1024));
            stats_frames = 0;
            last_stats = now;
        }

        // Target ~30fps with PSRAM, ~15fps without
        vTaskDelay(pdMS_TO_TICKS(s_has_psram ? 30 : 60));
    }
}

// ═══════════════════════════════════════════════════════
// STREAM SENDER TASK - CPU1
// ═══════════════════════════════════════════════════════
static void stream_sender_task(void *arg)
{
    ESP_LOGI(TAG, "📡 Stream sender on CPU%d", xPortGetCoreID());

    frame_msg_t msg;
    int64_t last_stats = esp_timer_get_time();
    uint32_t stats_frames = 0;

    while (1) {
        if (xQueueReceive(s_frame_queue, &msg, pdMS_TO_TICKS(100)) == pdTRUE) {
            if (msg.size > 0 && xSemaphoreTake(s_frame_mutex, pdMS_TO_TICKS(10)) == pdTRUE) {
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
                stats_frames++;
                
                xSemaphoreGive(s_frame_mutex);
            }
        }

        // Stats every 10 seconds
        int64_t now = esp_timer_get_time();
        if (now - last_stats >= 10000000) {
            float fps = (float)stats_frames * 1000000.0f / (float)(now - last_stats);
            ESP_LOGI(TAG, "📤 Stream: %.1f fps, Clients: %d", 
                     fps, rtsp_server_get_client_count());
            stats_frames = 0;
            last_stats = now;
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
    ESP_LOGI(TAG, "📶 WiFi AP: %s / %s", WIFI_AP_SSID, WIFI_AP_PASS);

    // Stream Server
    rtsp_server_config_t stream_config = {
        .port = 8080,
        .stream_name = "stream",
        .max_clients = 4,
        .client_callback = stream_client_callback,
        .callback_arg = NULL,
    };
    
    rtsp_server_init(&stream_config);
    rtsp_server_start();
    ESP_LOGI(TAG, "🎬 Stream: http://192.168.4.1:8080/stream");

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
    ESP_LOGI(TAG, "📡 MAVLink: UDP port %d", MAVLINK_UDP_PORT);

    // Start stream sender
    xTaskCreatePinnedToCore(stream_sender_task, "stream_tx", 4096, NULL, 4, NULL, 1);

    ESP_LOGI(TAG, "════════════════════════════════════════");
    ESP_LOGI(TAG, "✅ SYSTEM READY!");
    ESP_LOGI(TAG, "   Resolution: %s", s_has_psram ? "VGA 640x480" : "QVGA 320x240");
    ESP_LOGI(TAG, "   WiFi: %s", WIFI_AP_SSID);
    ESP_LOGI(TAG, "   Video: http://192.168.4.1:8080/stream");
    ESP_LOGI(TAG, "════════════════════════════════════════");

    // Idle - this task now just monitors
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(30000));
        ESP_LOGI(TAG, "📊 Status: Cap=%lu, Sent=%lu, Heap=%lu KB",
                 (unsigned long)s_frames_captured,
                 (unsigned long)s_frames_sent,
                 (unsigned long)(esp_get_free_heap_size() / 1024));
    }
}

// ═══════════════════════════════════════════════════════
// APP_MAIN
// ═══════════════════════════════════════════════════════
void app_main(void)
{
    // Disable brownout detector (camera needs stable power)
    WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);
    
    // NVS init
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        nvs_flash_init();
    }

    ESP_LOGI(TAG, "");
    ESP_LOGI(TAG, "════════════════════════════════════════");
    ESP_LOGI(TAG, "   ESP32-CAM MJPEG Streamer v2.0");
    ESP_LOGI(TAG, "════════════════════════════════════════");

    // Check PSRAM
    size_t psram_size = heap_caps_get_total_size(MALLOC_CAP_SPIRAM);
    s_has_psram = (psram_size > 0);
    
    ESP_LOGI(TAG, "DRAM Heap: %lu KB", (unsigned long)(esp_get_free_heap_size() / 1024));
    
    if (s_has_psram) {
        ESP_LOGI(TAG, "✅ PSRAM: %lu KB", (unsigned long)(psram_size / 1024));
        s_frame_buffer_size = MAX_FRAME_SIZE_PSRAM;
    } else {
        ESP_LOGW(TAG, "⚠️ No PSRAM detected - using low resolution mode");
        s_frame_buffer_size = MAX_FRAME_SIZE_DRAM;
    }

    // Allocate frame queue and buffer
    s_frame_queue = xQueueCreate(1, sizeof(frame_msg_t));
    s_frame_mutex = xSemaphoreCreateMutex();
    
    // Prefer PSRAM for frame buffer
    if (s_has_psram) {
        s_frame_buffer = heap_caps_malloc(s_frame_buffer_size, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    }
    if (!s_frame_buffer) {
        s_frame_buffer = malloc(s_frame_buffer_size);
    }

    if (!s_frame_queue || !s_frame_mutex || !s_frame_buffer) {
        ESP_LOGE(TAG, "❌ Memory allocation failed!");
        return;
    }
    
    ESP_LOGI(TAG, "✅ Frame buffer: %lu KB (%s)", 
             (unsigned long)(s_frame_buffer_size / 1024),
             s_has_psram ? "PSRAM" : "DRAM");

    // Start tasks
    xTaskCreatePinnedToCore(camera_task, "camera", 4096, NULL, 5, NULL, 0);
    xTaskCreatePinnedToCore(network_task, "network", 8192, NULL, 5, NULL, 1);

    ESP_LOGI(TAG, "🚀 Tasks started");
}
