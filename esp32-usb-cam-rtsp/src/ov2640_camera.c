/**
 * @file ov2640_camera.c
 * @brief OV2640 Camera Module (ESP32-CAM AI-Thinker)
 */

#include "ov2640_camera.h"
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#include "driver/gpio.h"

static const char *TAG = "OV2640";

// ESP32-CAM AI-Thinker pins
#define CAM_PIN_PWDN    32
#define CAM_PIN_RESET   -1
#define CAM_PIN_XCLK    0
#define CAM_PIN_SIOD    26
#define CAM_PIN_SIOC    27
#define CAM_PIN_D7      35
#define CAM_PIN_D6      34
#define CAM_PIN_D5      39
#define CAM_PIN_D4      36
#define CAM_PIN_D3      21
#define CAM_PIN_D2      19
#define CAM_PIN_D1      18
#define CAM_PIN_D0      5
#define CAM_PIN_VSYNC   25
#define CAM_PIN_HREF    23
#define CAM_PIN_PCLK    22
#define CAM_PIN_FLASH   4

static struct {
    bool initialized;
    bool streaming;
    ov2640_config_t config;
    TaskHandle_t stream_task;
    float current_fps;
} s_cam = {0};

esp_err_t ov2640_init(const ov2640_config_t *config)
{
    if (s_cam.initialized) return ESP_OK;

    ESP_LOGI(TAG, "Initializing OV2640 camera...");

    if (config) {
        memcpy(&s_cam.config, config, sizeof(ov2640_config_t));
    } else {
        s_cam.config.framesize = FRAMESIZE_QVGA;
        s_cam.config.quality = 12;
        s_cam.config.fps = 15;
    }

    // Flash LED GPIO
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << CAM_PIN_FLASH),
        .mode = GPIO_MODE_OUTPUT,
    };
    gpio_config(&io_conf);
    gpio_set_level(CAM_PIN_FLASH, 0);

    // Check PSRAM
    size_t psram = heap_caps_get_total_size(MALLOC_CAP_SPIRAM);
    bool has_psram = (psram > 0);
    
    if (has_psram) {
        ESP_LOGI(TAG, "✅ PSRAM detected: %u KB", (unsigned)(psram / 1024));
    } else {
        ESP_LOGW(TAG, "⚠️ No PSRAM - using DRAM mode");
    }

    // Camera config - match Arduino example
    camera_config_t cam_config = {
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
        // PSRAM varsa SVGA (800x600), yoksa QVGA (320x240)
        .frame_size = has_psram ? FRAMESIZE_SVGA : FRAMESIZE_QVGA,
        .jpeg_quality = has_psram ? 10 : 12,
        .fb_count = has_psram ? 2 : 1,
        .fb_location = has_psram ? CAMERA_FB_IN_PSRAM : CAMERA_FB_IN_DRAM,
        .grab_mode = CAMERA_GRAB_LATEST,
    };

    ESP_LOGI(TAG, "Using %s for frame buffer", has_psram ? "PSRAM" : "DRAM");

    esp_err_t ret = esp_camera_init(&cam_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Camera init failed: %s", esp_err_to_name(ret));
        return ret;
    }

    sensor_t *sensor = esp_camera_sensor_get();
    if (sensor) {
        sensor->set_brightness(sensor, 0);
        sensor->set_contrast(sensor, 0);
        sensor->set_saturation(sensor, 0);
        sensor->set_whitebal(sensor, 1);
        sensor->set_awb_gain(sensor, 1);
        sensor->set_exposure_ctrl(sensor, 1);
        sensor->set_gain_ctrl(sensor, 1);
    }

    s_cam.initialized = true;
    ESP_LOGI(TAG, "========================================");
    ESP_LOGI(TAG, "Camera initialized successfully");
    ESP_LOGI(TAG, "  Resolution: %s", has_psram ? "VGA 640x480" : "QVGA 320x240");
    ESP_LOGI(TAG, "  Buffer: %s", has_psram ? "PSRAM" : "DRAM");
    ESP_LOGI(TAG, "  Free heap: %lu", (unsigned long)esp_get_free_heap_size());
    ESP_LOGI(TAG, "========================================");

    return ESP_OK;
}

esp_err_t ov2640_deinit(void)
{
    if (!s_cam.initialized) return ESP_OK;
    ov2640_stop();
    esp_camera_deinit();
    s_cam.initialized = false;
    return ESP_OK;
}

esp_err_t ov2640_start(void) { return ESP_OK; }
esp_err_t ov2640_stop(void) { return ESP_OK; }

esp_err_t ov2640_capture(ov2640_frame_t *frame)
{
    if (!s_cam.initialized || !frame) return ESP_ERR_INVALID_STATE;
    camera_fb_t *fb = esp_camera_fb_get();
    if (!fb) return ESP_FAIL;
    frame->data = fb->buf;
    frame->size = fb->len;
    frame->width = fb->width;
    frame->height = fb->height;
    frame->timestamp = esp_timer_get_time();
    return ESP_OK;
}

void ov2640_release_frame(ov2640_frame_t *frame) { (void)frame; }
float ov2640_get_fps(void) { return s_cam.current_fps; }
void ov2640_set_flash(bool on) { gpio_set_level(CAM_PIN_FLASH, on ? 1 : 0); }
