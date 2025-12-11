/**
 * @file main.c
 * @brief ESP32-CAM RTSP Streamer + MAVLink Telemetry
 * 
 * RTOS Task Yapısı:
 * ─────────────────────────────────────────────────
 * CPU0 (PRO_CPU):
 *   - camera_task (Priority 5) - Frame capture
 *   
 * CPU1 (APP_CPU):
 *   - network_task (Priority 5) - WiFi/RTSP/MAVLink init
 *   - rtsp_sender_task (Priority 4) - Frame → Client
 *   - mavlink_uart_task (Priority 4) - UART ↔ UDP
 * ─────────────────────────────────────────────────
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
#include "nvs_flash.h"

#include "wifi_ap.h"
#include "mavlink_telemetry.h"
#include "rtsp_server.h"
#include "ov2640_camera.h"
#include "esp_camera.h"

static const char *TAG = "MAIN";

// ═══════════════════════════════════════════════════════
// Frame Queue - Kamera → RTSP iletişimi
// ═══════════════════════════════════════════════════════
#define FRAME_QUEUE_SIZE    2
#define MAX_FRAME_SIZE      (50 * 1024)  // 50KB max frame

typedef struct {
    uint8_t *data;
    size_t size;
    uint32_t width;
    uint32_t height;
    uint32_t sequence;
    int64_t timestamp;
} frame_msg_t;

static QueueHandle_t s_frame_queue = NULL;
static uint8_t *s_frame_buffer = NULL;
static SemaphoreHandle_t s_frame_mutex = NULL;

// Task handles
static TaskHandle_t s_camera_task = NULL;
static TaskHandle_t s_network_task = NULL;
static TaskHandle_t s_rtsp_sender_task = NULL;

// Stats
static uint32_t s_frame_count = 0;
static uint32_t s_dropped_frames = 0;

// ═══════════════════════════════════════════════════════
// Callbacks
// ═══════════════════════════════════════════════════════
static void wifi_callback(wifi_ap_state_t state, void *arg) 
{ 
    if (state == WIFI_AP_STATE_CLIENT_CONNECTED) {
        ESP_LOGI(TAG, "📱 Client connected to WiFi");
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
        ESP_LOGI(TAG, "🎥 RTSP client #%lu connected", (unsigned long)client_id);
    } else {
        ESP_LOGI(TAG, "🎥 RTSP client #%lu disconnected", (unsigned long)client_id);
    }
}

// ═══════════════════════════════════════════════════════
// CAMERA TASK - CPU0 (PRO_CPU)
// Frame capture ve queue'ya gönderme
// ═══════════════════════════════════════════════════════
static void camera_task(void *arg)
{
    ESP_LOGI(TAG, "📷 Camera task started on CPU%d", xPortGetCoreID());
    
    // Kamera başlat
    ov2640_config_t cam_config = {
        .framesize = FRAMESIZE_VGA,  // 640x480
        .quality = 12,               // JPEG quality (10-63, lower=better)
        .fps = 15,
        .frame_callback = NULL,      // Manuel capture kullanacağız
        .callback_arg = NULL,
    };
    
    esp_err_t ret = ov2640_init(&cam_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "❌ Camera init failed: %s", esp_err_to_name(ret));
        vTaskDelete(NULL);
        return;
    }
    
    ESP_LOGI(TAG, "✅ Camera initialized: VGA 640x480 @ 15fps");
    
    uint32_t seq = 0;
    uint32_t fps_count = 0;
    int64_t fps_start = esp_timer_get_time();
    float current_fps = 0;
    
    while (1) {
        // Frame capture
        camera_fb_t *fb = esp_camera_fb_get();
        if (fb) {
            // Queue'ya gönder (non-blocking)
            if (xSemaphoreTake(s_frame_mutex, pdMS_TO_TICKS(5)) == pdTRUE) {
                size_t copy_size = fb->len;
                if (copy_size > MAX_FRAME_SIZE) {
                    copy_size = MAX_FRAME_SIZE;
                }
                memcpy(s_frame_buffer, fb->buf, copy_size);
                
                frame_msg_t msg = {
                    .data = s_frame_buffer,
                    .size = copy_size,
                    .width = fb->width,
                    .height = fb->height,
                    .sequence = seq++,
                    .timestamp = esp_timer_get_time(),
                };
                
                xSemaphoreGive(s_frame_mutex);
                
                // Queue'ya gönder (overwrite mode - eski frame'i at)
                if (xQueueOverwrite(s_frame_queue, &msg) != pdTRUE) {
                    s_dropped_frames++;
                }
                
                s_frame_count++;
                fps_count++;
            }
            
            esp_camera_fb_return(fb);
            
            // FPS hesaplama (her saniye)
            int64_t now = esp_timer_get_time();
            if (now - fps_start >= 1000000) {
                current_fps = (float)fps_count * 1000000.0f / (float)(now - fps_start);
                fps_count = 0;
                fps_start = now;
                
                // Her 5 saniyede bir log
                if ((seq % 75) == 0) {  // 15fps * 5s = 75
                    ESP_LOGI(TAG, "📊 Camera: %.1f fps, %lu frames, %lu dropped", 
                             current_fps, (unsigned long)s_frame_count, (unsigned long)s_dropped_frames);
                }
            }
        } else {
            ESP_LOGW(TAG, "⚠️ Camera capture failed");
            vTaskDelay(pdMS_TO_TICKS(100));
        }
        
        // FPS kontrolü (~15fps = 66ms)
        vTaskDelay(pdMS_TO_TICKS(50));
    }
}

// ═══════════════════════════════════════════════════════
// RTSP SENDER TASK - CPU1 (APP_CPU)
// Queue'dan frame al, RTSP client'lara gönder
// ═══════════════════════════════════════════════════════
static void rtsp_sender_task(void *arg)
{
    ESP_LOGI(TAG, "📡 RTSP sender task started on CPU%d", xPortGetCoreID());
    
    frame_msg_t msg;
    uint32_t sent_count = 0;
    
    while (1) {
        // Queue'dan frame bekle
        if (xQueueReceive(s_frame_queue, &msg, pdMS_TO_TICKS(100)) == pdTRUE) {
            if (msg.size > 0) {
                // RTSP'ye gönder
                rtsp_frame_t rtsp_frame = {
                    .data = msg.data,
                    .size = msg.size,
                    .capacity = msg.size,
                    .width = msg.width,
                    .height = msg.height,
                    .format = 0,
                    .timestamp = msg.timestamp,
                    .sequence = msg.sequence,
                };
                
                rtsp_server_send_frame(&rtsp_frame);
                sent_count++;
                
                // Her 30 frame'de bir log
                if (sent_count % 30 == 0) {
                    ESP_LOGD(TAG, "📤 Sent frame #%lu (%u bytes)", 
                             (unsigned long)sent_count, (unsigned)msg.size);
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════
// NETWORK TASK - CPU1 (APP_CPU)
// WiFi, RTSP, MAVLink başlatma
// ═══════════════════════════════════════════════════════
static void network_task(void *arg)
{
    ESP_LOGI(TAG, "🌐 Network task started on CPU%d", xPortGetCoreID());
    
    // WiFi AP başlat
    wifi_ap_set_callback(wifi_callback, NULL);
    wifi_ap_init();
    wifi_ap_start();
    ESP_LOGI(TAG, "📶 WiFi AP: %s (192.168.4.1)", WIFI_AP_SSID);

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
    ESP_LOGI(TAG, "🎬 RTSP: http://192.168.4.1:%d", RTSP_PORT);

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
    ESP_LOGI(TAG, "🛩️ MAVLink: UDP port %d", MAVLINK_UDP_PORT);

    // RTSP Sender task başlat (aynı CPU'da)
    xTaskCreatePinnedToCore(
        rtsp_sender_task,
        "rtsp_send",
        4096,
        NULL,
        4,              // Priority (network'ten düşük)
        &s_rtsp_sender_task,
        1               // CPU1 (APP_CPU)
    );

    ESP_LOGI(TAG, "════════════════════════════════════════");
    ESP_LOGI(TAG, "✅ System Ready!");
    ESP_LOGI(TAG, "   WiFi: %s", WIFI_AP_SSID);
    ESP_LOGI(TAG, "   Video: http://192.168.4.1:554");
    ESP_LOGI(TAG, "   MAVLink: UDP 14550");
    ESP_LOGI(TAG, "════════════════════════════════════════");

    // Network task döngüsü - sistem monitör
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(10000));
        
        // Sistem durumu
        ESP_LOGI(TAG, "💾 Heap: %lu bytes free", (unsigned long)esp_get_free_heap_size());
    }
}

// ═══════════════════════════════════════════════════════
// APP_MAIN
// ═══════════════════════════════════════════════════════
void app_main(void)
{
    // NVS
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        nvs_flash_init();
    }

    ESP_LOGI(TAG, "════════════════════════════════════════");
    ESP_LOGI(TAG, "   ESP32-CAM RTSP + MAVLink System");
    ESP_LOGI(TAG, "════════════════════════════════════════");
    ESP_LOGI(TAG, "Free heap: %lu bytes", (unsigned long)esp_get_free_heap_size());

    // Frame queue ve buffer oluştur
    s_frame_queue = xQueueCreate(1, sizeof(frame_msg_t));  // Single item queue (overwrite mode)
    s_frame_mutex = xSemaphoreCreateMutex();
    s_frame_buffer = heap_caps_malloc(MAX_FRAME_SIZE, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    
    if (!s_frame_buffer) {
        // PSRAM yoksa internal RAM dene
        s_frame_buffer = heap_caps_malloc(MAX_FRAME_SIZE, MALLOC_CAP_8BIT);
    }
    
    if (!s_frame_queue || !s_frame_mutex || !s_frame_buffer) {
        ESP_LOGE(TAG, "❌ Failed to create queue/mutex/buffer");
        return;
    }
    
    ESP_LOGI(TAG, "✅ Frame buffer: %d KB", MAX_FRAME_SIZE / 1024);

    // ─────────────────────────────────────────────
    // Task'ları başlat - CPU dağılımı:
    // CPU0: Kamera (yoğun I/O)
    // CPU1: Network (WiFi driver burada)
    // ─────────────────────────────────────────────
    
    // Camera task - CPU0 (PRO_CPU)
    xTaskCreatePinnedToCore(
        camera_task,
        "camera",
        4096,
        NULL,
        5,              // High priority
        &s_camera_task,
        0               // CPU0 (PRO_CPU)
    );

    // Network task - CPU1 (APP_CPU)
    xTaskCreatePinnedToCore(
        network_task,
        "network",
        8192,
        NULL,
        5,              // High priority
        &s_network_task,
        1               // CPU1 (APP_CPU)
    );

    ESP_LOGI(TAG, "🚀 Tasks started, main exiting");
    
    // app_main bitti, RTOS scheduler devam ediyor
}