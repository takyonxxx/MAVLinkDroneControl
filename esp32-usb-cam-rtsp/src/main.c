/**
 * @file main.c
 * @brief ESP32-S3 USB Camera RTSP Streamer
 *
 * USB kameradan görüntü alıp WiFi AP üzerinden RTSP ile yayınlar.
 *
 * Kullanım:
 * 1. ESP32-S3'e USB kamera bağlayın
 * 2. Cihaz başlatıldığında "ESP32-CAM-RTSP" WiFi ağına bağlanın
 * 3. VLC veya benzeri bir player ile rtsp://192.168.4.1:554/stream adresini açın
 *
 * @author Maren
 * @date 2024
 */

#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "esp_system.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "nvs_flash.h"
#include "driver/gpio.h"

#include "wifi_ap.h"
#include "usb_camera.h"
#include "rtsp_server.h"
#include "mavlink_telemetry.h"
#include "lwip/sockets.h"

static const char *TAG = "MAIN";

// LED GPIO (durum göstergesi)
#define LED_GPIO GPIO_NUM_2

// Event grupları
static EventGroupHandle_t s_app_event_group;
#define WIFI_READY_BIT BIT0
#define CAMERA_READY_BIT BIT1
#define RTSP_READY_BIT BIT2
#define STREAMING_BIT BIT3

// Uygulama durumu
static struct
{
    bool wifi_ready;
    bool camera_ready;
    bool rtsp_ready;
    bool mavlink_ready;
    bool pixhawk_connected;
    bool streaming;
    uint32_t frame_count;
    uint64_t start_time;
} s_app_state = {0};

/**
 * @brief LED'i ayarla
 */
static void set_led(bool on)
{
    gpio_set_level(LED_GPIO, on ? 1 : 0);
}

/**
 * @brief LED blink (async)
 */
static void blink_led(int times, int interval_ms)
{
    for (int i = 0; i < times; i++)
    {
        set_led(true);
        vTaskDelay(pdMS_TO_TICKS(interval_ms));
        set_led(false);
        vTaskDelay(pdMS_TO_TICKS(interval_ms));
    }
}

/**
 * @brief WiFi AP callback
 */
static void wifi_callback(wifi_ap_state_t state, void *arg)
{
    switch (state)
    {
    case WIFI_AP_STATE_STARTED:
        ESP_LOGI(TAG, "📶 WiFi AP started");
        s_app_state.wifi_ready = true;
        xEventGroupSetBits(s_app_event_group, WIFI_READY_BIT);
        break;

    case WIFI_AP_STATE_CLIENT_CONNECTED:
        ESP_LOGI(TAG, "📱 Client connected to WiFi");
        blink_led(2, 100);
        break;

    case WIFI_AP_STATE_STOPPED:
        ESP_LOGW(TAG, "⚠️ WiFi AP stopped");
        s_app_state.wifi_ready = false;
        xEventGroupClearBits(s_app_event_group, WIFI_READY_BIT);
        break;

    default:
        break;
    }
}

/**
 * @brief Kamera durumu callback
 */
static void camera_state_callback(usb_cam_state_t state, void *arg)
{
    switch (state)
    {
    case USB_CAM_STATE_CONNECTED:
        ESP_LOGI(TAG, "📷 USB Camera connected");
        s_app_state.camera_ready = true;
        xEventGroupSetBits(s_app_event_group, CAMERA_READY_BIT);
        blink_led(3, 100);
        break;

    case USB_CAM_STATE_STREAMING:
        ESP_LOGI(TAG, "🎬 Camera streaming started");
        s_app_state.streaming = true;
        xEventGroupSetBits(s_app_event_group, STREAMING_BIT);
        break;

    case USB_CAM_STATE_DISCONNECTED:
        ESP_LOGW(TAG, "⚠️ USB Camera disconnected");
        s_app_state.camera_ready = false;
        s_app_state.streaming = false;
        xEventGroupClearBits(s_app_event_group, CAMERA_READY_BIT | STREAMING_BIT);
        break;

    case USB_CAM_STATE_ERROR:
        ESP_LOGE(TAG, "❌ Camera error");
        break;
    }
}

/**
 * @brief Yeni frame callback
 */
static void frame_callback(usb_cam_frame_t *frame, void *arg)
{
    if (!frame || !s_app_state.rtsp_ready)
    {
        return;
    }

    // Frame'i RTSP server'a gönder
    esp_err_t ret = rtsp_server_send_frame(frame);
    if (ret == ESP_OK)
    {
        s_app_state.frame_count++;

        // Her 100 frame'de bir durum logu
        if (s_app_state.frame_count % 100 == 0)
        {
            float fps = usb_camera_get_fps();
            ESP_LOGI(TAG, "📊 Frames: %lu, FPS: %.1f, Size: %zu bytes",
                     (unsigned long)s_app_state.frame_count, fps, frame->size);
        }
    }
}

/**
 * @brief RTSP istemci callback
 */
static void rtsp_client_callback(uint32_t client_id, bool connected, void *arg)
{
    if (connected)
    {
        ESP_LOGI(TAG, "🔗 RTSP Client %lu connected", (unsigned long)client_id);
        set_led(true);
    }
    else
    {
        ESP_LOGI(TAG, "🔌 RTSP Client %lu disconnected", (unsigned long)client_id);

        // Başka istemci var mı kontrol et
        rtsp_client_info_t clients[RTSP_MAX_CLIENTS];
        uint8_t count = rtsp_server_get_clients(clients, RTSP_MAX_CLIENTS);
        if (count == 0)
        {
            set_led(false);
        }
    }
}

/**
 * @brief MAVLink heartbeat callback
 */
static void mavlink_heartbeat_callback(const mavlink_heartbeat_info_t *info, void *arg)
{
    static bool was_connected = false;

    if (!was_connected)
    {
        was_connected = true;
        s_app_state.pixhawk_connected = true;
        ESP_LOGI(TAG, "🚁 Pixhawk connected - SysID: %d, Type: %d, Status: %d",
                 info->system_id, info->type, info->system_status);
        blink_led(2, 100);
    }
}

/**
 * @brief MAVLink GCS bağlantı callback
 */
static void mavlink_gcs_connect_callback(uint32_t ip, uint16_t port, void *arg)
{
    struct in_addr addr;
    addr.s_addr = ip;
    ESP_LOGI(TAG, "📡 GCS connected: %s:%d", inet_ntoa(addr), port);
}

/**
 * @brief MAVLink GCS bağlantı kesme callback
 */
static void mavlink_gcs_disconnect_callback(uint32_t ip, uint16_t port, void *arg)
{
    struct in_addr addr;
    addr.s_addr = ip;
    ESP_LOGI(TAG, "📡 GCS disconnected: %s:%d", inet_ntoa(addr), port);
}

/**
 * @brief Sistem durumunu göster
 */
static void print_status(void)
{
    ESP_LOGI(TAG, "");
    ESP_LOGI(TAG, "╔════════════════════════════════════════════════════╗");
    ESP_LOGI(TAG, "║   ESP32-S3 USB Camera + MAVLink RTSP Streamer      ║");
    ESP_LOGI(TAG, "╠════════════════════════════════════════════════════╣");
    ESP_LOGI(TAG, "║  WiFi AP:                                          ║");
    ESP_LOGI(TAG, "║    SSID: %-40s ║", WIFI_AP_SSID);
    ESP_LOGI(TAG, "║    Pass: %-40s ║", WIFI_AP_PASS);
    ESP_LOGI(TAG, "║    IP:   %-40s ║", WIFI_AP_IP);
    ESP_LOGI(TAG, "╠════════════════════════════════════════════════════╣");

    char rtsp_url[64];
    rtsp_server_get_url(rtsp_url, sizeof(rtsp_url));
    ESP_LOGI(TAG, "║  RTSP Stream:                                      ║");
    ESP_LOGI(TAG, "║    URL: %-41s ║", rtsp_url);
    ESP_LOGI(TAG, "║    Resolution: %dx%d @ %d fps                   ║",
             CAM_FRAME_WIDTH, CAM_FRAME_HEIGHT, CAM_FPS);
    ESP_LOGI(TAG, "╠════════════════════════════════════════════════════╣");
    ESP_LOGI(TAG, "║  MAVLink Telemetry:                                ║");
    ESP_LOGI(TAG, "║    UDP Port: %-37d ║", MAVLINK_UDP_PORT);
    ESP_LOGI(TAG, "║    UART: TX=GPIO%d, RX=GPIO%d, Baud=%d        ║",
             MAVLINK_UART_TX_PIN, MAVLINK_UART_RX_PIN, MAVLINK_UART_BAUD);
    ESP_LOGI(TAG, "╠════════════════════════════════════════════════════╣");
    ESP_LOGI(TAG, "║  Status:                                           ║");
    ESP_LOGI(TAG, "║    WiFi:    %s                                   ║",
             s_app_state.wifi_ready ? "✅ Ready" : "❌ Not Ready");
    ESP_LOGI(TAG, "║    Camera:  %s                                   ║",
             s_app_state.camera_ready ? "✅ Ready" : "⏳ Waiting");
    ESP_LOGI(TAG, "║    RTSP:    %s                                   ║",
             s_app_state.rtsp_ready ? "✅ Ready" : "❌ Not Ready");
    ESP_LOGI(TAG, "║    MAVLink: %s                                   ║",
             s_app_state.mavlink_ready ? "✅ Ready" : "❌ Not Ready");
    ESP_LOGI(TAG, "║    Pixhawk: %s                                   ║",
             s_app_state.pixhawk_connected ? "✅ Connected" : "⏳ Waiting");
    ESP_LOGI(TAG, "╚════════════════════════════════════════════════════╝");
    ESP_LOGI(TAG, "");
    ESP_LOGI(TAG, "📱 Connect to WiFi: %s (pass: %s)", WIFI_AP_SSID, WIFI_AP_PASS);
    ESP_LOGI(TAG, "🎬 Open in VLC: %s", rtsp_url);
    ESP_LOGI(TAG, "📡 QGroundControl UDP: %s:%d", WIFI_AP_IP, MAVLINK_UDP_PORT);
    ESP_LOGI(TAG, "");
}

/**
 * @brief Durum gösterge task'ı
 */
static void status_task(void *arg)
{
    while (1)
    {
        // Her 10 saniyede bir durum göster
        vTaskDelay(pdMS_TO_TICKS(10000));

        // Pixhawk bağlantı durumunu kontrol et
        s_app_state.pixhawk_connected = mavlink_telemetry_is_pixhawk_connected();

        if (s_app_state.streaming)
        {
            rtsp_server_stats_t rtsp_stats;
            rtsp_server_get_stats(&rtsp_stats);

            mavlink_stats_t mav_stats;
            mavlink_telemetry_get_stats(&mav_stats);

            ESP_LOGI(TAG, "📊 RTSP - Clients: %lu, Frames: %llu",
                     (unsigned long)rtsp_stats.active_clients,
                     (unsigned long long)rtsp_stats.total_frames_sent);

            ESP_LOGI(TAG, "📡 MAVLink - GCS: %lu, RX: %lu msgs, TX: %lu msgs, Pixhawk: %s",
                     (unsigned long)mav_stats.gcs_clients,
                     (unsigned long)mav_stats.mavlink_messages_rx,
                     (unsigned long)mav_stats.mavlink_messages_tx,
                     s_app_state.pixhawk_connected ? "Connected" : "Disconnected");
        }

        // LED heartbeat
        if (s_app_state.wifi_ready && !s_app_state.streaming)
        {
            blink_led(1, 50);
        }
    }
}

/**
 * @brief Ana uygulama başlatma
 */
static esp_err_t app_init(void)
{
    esp_err_t ret;

    ESP_LOGI(TAG, "🚀 Initializing application...");

    // Event group oluştur
    s_app_event_group = xEventGroupCreate();
    if (!s_app_event_group)
    {
        ESP_LOGE(TAG, "Failed to create event group");
        return ESP_ERR_NO_MEM;
    }

    // LED GPIO yapılandır
    gpio_config_t io_conf = {
        .intr_type = GPIO_INTR_DISABLE,
        .mode = GPIO_MODE_OUTPUT,
        .pin_bit_mask = (1ULL << LED_GPIO),
        .pull_down_en = 0,
        .pull_up_en = 0,
    };
    gpio_config(&io_conf);
    set_led(false);

    // 1. WiFi AP başlat
    ESP_LOGI(TAG, "📶 Starting WiFi AP...");
    wifi_ap_set_callback(wifi_callback, NULL);

    ret = wifi_ap_init();
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "WiFi AP init failed: %s", esp_err_to_name(ret));
        return ret;
    }

    ret = wifi_ap_start();
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "WiFi AP start failed: %s", esp_err_to_name(ret));
        return ret;
    }

    // WiFi hazır olmasını bekle
    xEventGroupWaitBits(s_app_event_group, WIFI_READY_BIT, false, true, pdMS_TO_TICKS(5000));

    // 2. RTSP Server başlat
    ESP_LOGI(TAG, "🎬 Starting RTSP Server...");

    rtsp_server_config_t rtsp_config = {
        .port = RTSP_PORT,
        .stream_name = RTSP_STREAM_NAME,
        .max_clients = RTSP_MAX_CLIENTS,
        .client_callback = rtsp_client_callback,
        .callback_arg = NULL,
    };

    ret = rtsp_server_init(&rtsp_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "RTSP Server init failed: %s", esp_err_to_name(ret));
        return ret;
    }

    ret = rtsp_server_start();
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "RTSP Server start failed: %s", esp_err_to_name(ret));
        return ret;
    }

    s_app_state.rtsp_ready = true;
    xEventGroupSetBits(s_app_event_group, RTSP_READY_BIT);

    // 3. USB Kamera başlat
    ESP_LOGI(TAG, "📷 Starting USB Camera...");

    usb_cam_config_t cam_config = {
        .width = CAM_FRAME_WIDTH,
        .height = CAM_FRAME_HEIGHT,
        .fps = CAM_FPS,
        .format = USB_CAM_FORMAT_MJPEG,
        .frame_buffer_count = 3,
        .frame_callback = frame_callback,
        .state_callback = camera_state_callback,
        .callback_arg = NULL,
    };

    ret = usb_camera_init(&cam_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "USB Camera init failed: %s", esp_err_to_name(ret));
        // Kamera başarısız olsa da devam et, sonradan bağlanabilir
    }

    // 4. MAVLink Telemetri başlat
    ESP_LOGI(TAG, "📡 Starting MAVLink Telemetry...");

    mavlink_config_t mav_config = {
        .uart_num = MAVLINK_UART_NUM,
        .uart_tx_pin = MAVLINK_UART_TX_PIN,
        .uart_rx_pin = MAVLINK_UART_RX_PIN,
        .uart_baud = MAVLINK_UART_BAUD,
        .udp_port = MAVLINK_UDP_PORT,
        .on_heartbeat = mavlink_heartbeat_callback,
        .on_gcs_connect = mavlink_gcs_connect_callback,
        .on_gcs_disconnect = mavlink_gcs_disconnect_callback,
        .callback_arg = NULL,
    };

    ret = mavlink_telemetry_init(&mav_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "MAVLink init failed: %s", esp_err_to_name(ret));
    }
    else
    {
        ret = mavlink_telemetry_start();
        if (ret == ESP_OK)
        {
            s_app_state.mavlink_ready = true;
            ESP_LOGI(TAG, "✅ MAVLink telemetry active on UDP port %d", MAVLINK_UDP_PORT);
        }
    }

    // Durum task'ını başlat
    xTaskCreate(status_task, "status", 2048, NULL, 2, NULL);

    // Durumu göster
    print_status();

    s_app_state.start_time = esp_timer_get_time();

    return ESP_OK;
}

/**
 * @brief Ana döngü - kamera bağlantısını izle
 */
static void app_main_loop(void)
{
    EventBits_t bits;

    while (1)
    {
        // Kamera bağlantısını bekle
        bits = xEventGroupWaitBits(s_app_event_group,
                                   CAMERA_READY_BIT,
                                   false, false,
                                   pdMS_TO_TICKS(1000));

        if (bits & CAMERA_READY_BIT)
        {
            // Kamera bağlandı, streaming başlat
            if (!s_app_state.streaming)
            {
                ESP_LOGI(TAG, "🎥 Starting camera stream...");

                esp_err_t ret = usb_camera_start();
                if (ret == ESP_OK)
                {
                    ESP_LOGI(TAG, "✅ Stream active!");
                    print_status();
                }
                else
                {
                    ESP_LOGE(TAG, "Failed to start camera: %s", esp_err_to_name(ret));
                }
            }
        }
        else
        {
            // Kamera bağlı değil
            if (s_app_state.streaming)
            {
                ESP_LOGW(TAG, "⚠️ Camera disconnected, waiting for reconnection...");
                s_app_state.streaming = false;
            }
        }

        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

/**
 * @brief Ana giriş noktası
 */
void app_main(void)
{
    ESP_LOGI(TAG, "");
    ESP_LOGI(TAG, "========================================");
    ESP_LOGI(TAG, "  ESP32-S3 USB Camera RTSP Streamer");
    ESP_LOGI(TAG, "========================================");
    ESP_LOGI(TAG, "");

    // NVS başlat
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND)
    {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    // Heap bilgisi
    ESP_LOGI(TAG, "Free heap: %lu bytes", (unsigned long)esp_get_free_heap_size());
    ESP_LOGI(TAG, "Free PSRAM: %lu bytes", (unsigned long)heap_caps_get_free_size(MALLOC_CAP_SPIRAM));

    // Uygulama başlat
    ret = app_init();
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "❌ Application initialization failed!");
        // Hata durumunda LED blink
        while (1)
        {
            blink_led(5, 200);
            vTaskDelay(pdMS_TO_TICKS(1000));
        }
    }

    // Ana döngü
    app_main_loop();
}
