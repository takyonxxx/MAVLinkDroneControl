/**
 * @file ov2640_camera.c
 * @brief OV2640 Kamera modülü (ESP32-CAM AI-Thinker)
 */

#include "ov2640_camera.h"
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "driver/gpio.h"

static const char *TAG = "OV2640";

// ESP32-CAM AI-Thinker pin tanımları
#define CAM_PIN_PWDN 32
#define CAM_PIN_RESET -1
#define CAM_PIN_XCLK 0
#define CAM_PIN_SIOD 26
#define CAM_PIN_SIOC 27
#define CAM_PIN_D7 35
#define CAM_PIN_D6 34
#define CAM_PIN_D5 39
#define CAM_PIN_D4 36
#define CAM_PIN_D3 21
#define CAM_PIN_D2 19
#define CAM_PIN_D1 18
#define CAM_PIN_D0 5
#define CAM_PIN_VSYNC 25
#define CAM_PIN_HREF 23
#define CAM_PIN_PCLK 22

// Flash LED pin
#define CAM_PIN_FLASH 4

// Modül durumu
static struct
{
    bool initialized;
    bool streaming;
    ov2640_config_t config;
    TaskHandle_t stream_task;
    uint32_t frame_count;
    uint64_t fps_start;
    float current_fps;
} s_cam = {0};

// Streaming task
static void stream_task(void *arg)
{
    ESP_LOGI(TAG, "Stream task started");

    s_cam.fps_start = esp_timer_get_time();
    s_cam.frame_count = 0;
    uint32_t seq = 0;

    while (s_cam.streaming)
    {
        camera_fb_t *fb = esp_camera_fb_get();
        if (fb)
        {
            // Callback varsa çağır
            if (s_cam.config.frame_callback)
            {
                ov2640_frame_t frame = {
                    .data = fb->buf,
                    .size = fb->len,
                    .width = fb->width,
                    .height = fb->height,
                    .timestamp = esp_timer_get_time(),
                    .sequence = seq++,
                };
                s_cam.config.frame_callback(&frame, s_cam.config.callback_arg);
            }

            esp_camera_fb_return(fb);

            s_cam.frame_count++;

            // FPS hesaplama
            uint64_t now = esp_timer_get_time();
            uint64_t elapsed = now - s_cam.fps_start;
            if (elapsed >= 1000000)
            {
                s_cam.current_fps = (float)s_cam.frame_count * 1000000.0f / (float)elapsed;
                s_cam.frame_count = 0;
                s_cam.fps_start = now;
            }
        }
        else
        {
            ESP_LOGW(TAG, "Camera capture failed");
            vTaskDelay(pdMS_TO_TICKS(100));
        }

        // FPS kontrolü
        if (s_cam.config.fps > 0)
        {
            vTaskDelay(pdMS_TO_TICKS(1000 / s_cam.config.fps));
        }
        else
        {
            vTaskDelay(pdMS_TO_TICKS(33)); // ~30fps default
        }
    }

    ESP_LOGI(TAG, "Stream task stopped");
    vTaskDelete(NULL);
}

esp_err_t ov2640_init(const ov2640_config_t *config)
{
    if (s_cam.initialized)
    {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing OV2640 camera...");

    // Config kaydet
    if (config)
    {
        memcpy(&s_cam.config, config, sizeof(ov2640_config_t));
    }
    else
    {
        s_cam.config.framesize = FRAMESIZE_VGA;
        s_cam.config.quality = 12;
        s_cam.config.fps = 15;
    }

    // Flash LED GPIO
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << CAM_PIN_FLASH),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&io_conf);
    gpio_set_level(CAM_PIN_FLASH, 0);

    // Kamera konfigürasyonu
    camera_config_t camera_config = {
        .pin_pwdn = CAM_PIN_PWDN,
        .pin_reset = CAM_PIN_RESET,
        .pin_xclk = CAM_PIN_XCLK,
        .pin_sccb_sda = CAM_PIN_SIOD,
        .pin_sccb_scl = CAM_PIN_SIOC,
        .pin_d7 = CAM_PIN_D7,
        .pin_d6 = CAM_PIN_D6,
        .pin_d5 = CAM_PIN_D5,
        .pin_d4 = CAM_PIN_D4,
        .pin_d3 = CAM_PIN_D3,
        .pin_d2 = CAM_PIN_D2,
        .pin_d1 = CAM_PIN_D1,
        .pin_d0 = CAM_PIN_D0,
        .pin_vsync = CAM_PIN_VSYNC,
        .pin_href = CAM_PIN_HREF,
        .pin_pclk = CAM_PIN_PCLK,

        .xclk_freq_hz = 20000000,
        .ledc_timer = LEDC_TIMER_0,
        .ledc_channel = LEDC_CHANNEL_0,

        .pixel_format = PIXFORMAT_JPEG,
        .frame_size = s_cam.config.framesize,
        .jpeg_quality = s_cam.config.quality,
        .fb_count = 2,
        .fb_location = CAMERA_FB_IN_PSRAM,
        .grab_mode = CAMERA_GRAB_LATEST,
    };

    // Kamerayı başlat
    esp_err_t ret = esp_camera_init(&camera_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Camera init failed: %s", esp_err_to_name(ret));
        return ret;
    }

    // Sensör ayarları
    sensor_t *sensor = esp_camera_sensor_get();
    if (sensor)
    {
        sensor->set_brightness(sensor, 0);
        sensor->set_contrast(sensor, 0);
        sensor->set_saturation(sensor, 0);
        sensor->set_whitebal(sensor, 1);
        sensor->set_awb_gain(sensor, 1);
        sensor->set_exposure_ctrl(sensor, 1);
        sensor->set_aec2(sensor, 1);
        sensor->set_gain_ctrl(sensor, 1);
        sensor->set_agc_gain(sensor, 0);
        sensor->set_gainceiling(sensor, GAINCEILING_2X);
        sensor->set_bpc(sensor, 1);
        sensor->set_wpc(sensor, 1);
        sensor->set_hmirror(sensor, 0);
        sensor->set_vflip(sensor, 0);
    }

    s_cam.initialized = true;
    ESP_LOGI(TAG, "OV2640 camera initialized");

    return ESP_OK;
}

esp_err_t ov2640_deinit(void)
{
    if (!s_cam.initialized)
    {
        return ESP_OK;
    }

    ov2640_stop();
    esp_camera_deinit();
    s_cam.initialized = false;

    return ESP_OK;
}

esp_err_t ov2640_start(void)
{
    if (!s_cam.initialized)
    {
        return ESP_ERR_INVALID_STATE;
    }

    if (s_cam.streaming)
    {
        return ESP_OK;
    }

    s_cam.streaming = true;

    xTaskCreatePinnedToCore(
        stream_task,
        "cam_stream",
        4096,
        NULL,
        5,
        &s_cam.stream_task,
        0 // CPU0
    );

    ESP_LOGI(TAG, "Streaming started");
    return ESP_OK;
}

esp_err_t ov2640_stop(void)
{
    if (!s_cam.streaming)
    {
        return ESP_OK;
    }

    s_cam.streaming = false;
    vTaskDelay(pdMS_TO_TICKS(100));
    s_cam.stream_task = NULL;

    ESP_LOGI(TAG, "Streaming stopped");
    return ESP_OK;
}

esp_err_t ov2640_capture(ov2640_frame_t *frame)
{
    if (!s_cam.initialized || !frame)
    {
        return ESP_ERR_INVALID_STATE;
    }

    camera_fb_t *fb = esp_camera_fb_get();
    if (!fb)
    {
        return ESP_FAIL;
    }

    frame->data = fb->buf;
    frame->size = fb->len;
    frame->width = fb->width;
    frame->height = fb->height;
    frame->timestamp = esp_timer_get_time();

    return ESP_OK;
}

void ov2640_release_frame(ov2640_frame_t *frame)
{
    (void)frame;
}

float ov2640_get_fps(void)
{
    return s_cam.current_fps;
}

void ov2640_set_flash(bool on)
{
    gpio_set_level(CAM_PIN_FLASH, on ? 1 : 0);
}