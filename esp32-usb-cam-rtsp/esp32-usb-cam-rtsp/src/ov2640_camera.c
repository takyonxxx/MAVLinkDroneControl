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
    bool has_psram;
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

    // Flash LED GPIO - start OFF
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << CAM_PIN_FLASH),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&io_conf);
    gpio_set_level(CAM_PIN_FLASH, 0);

    // Check PSRAM availability
    size_t psram = heap_caps_get_total_size(MALLOC_CAP_SPIRAM);
    s_cam.has_psram = (psram > 0);
    
    if (s_cam.has_psram) {
        ESP_LOGI(TAG, "✅ PSRAM: %u KB available", (unsigned)(psram / 1024));
    } else {
        ESP_LOGW(TAG, "⚠️ No PSRAM - using DRAM (low resolution)");
    }

    // Determine settings based on PSRAM
    framesize_t frame_size;
    int jpeg_quality;
    int fb_count;
    camera_fb_location_t fb_location;
    
    if (s_cam.has_psram) {
        // High quality with PSRAM
        frame_size = FRAMESIZE_VGA;     // 640x480
        jpeg_quality = 10;              // Better quality
        fb_count = 2;                   // Double buffer
        fb_location = CAMERA_FB_IN_PSRAM;
        ESP_LOGI(TAG, "Mode: VGA 640x480, Quality 10, 2 buffers (PSRAM)");
    } else {
        // Conservative without PSRAM  
        frame_size = FRAMESIZE_QVGA;    // 320x240
        jpeg_quality = 12;              // Lower quality for smaller frames
        fb_count = 1;                   // Single buffer
        fb_location = CAMERA_FB_IN_DRAM;
        ESP_LOGI(TAG, "Mode: QVGA 320x240, Quality 12, 1 buffer (DRAM)");
    }

    // Camera configuration
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
        .frame_size = frame_size,
        .jpeg_quality = jpeg_quality,
        .fb_count = fb_count,
        .fb_location = fb_location,
        .grab_mode = CAMERA_GRAB_LATEST,
    };

    // Initialize camera
    esp_err_t ret = esp_camera_init(&cam_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Camera init failed: 0x%x (%s)", ret, esp_err_to_name(ret));
        return ret;
    }

    // Get sensor and configure
    sensor_t *sensor = esp_camera_sensor_get();
    if (sensor) {
        // Basic settings
        sensor->set_brightness(sensor, 0);
        sensor->set_contrast(sensor, 0);
        sensor->set_saturation(sensor, 0);
        
        // Auto settings
        sensor->set_whitebal(sensor, 1);
        sensor->set_awb_gain(sensor, 1);
        sensor->set_wb_mode(sensor, 0);
        sensor->set_exposure_ctrl(sensor, 1);
        sensor->set_aec2(sensor, 0);
        sensor->set_gain_ctrl(sensor, 1);
        sensor->set_agc_gain(sensor, 0);
        sensor->set_bpc(sensor, 0);
        sensor->set_wpc(sensor, 1);
        sensor->set_raw_gma(sensor, 1);
        sensor->set_lenc(sensor, 1);
        sensor->set_hmirror(sensor, 0);
        sensor->set_vflip(sensor, 0);
        sensor->set_dcw(sensor, 1);
        
        ESP_LOGI(TAG, "Sensor configured: PID=0x%02X", sensor->id.PID);
    }

    s_cam.initialized = true;
    
    ESP_LOGI(TAG, "════════════════════════════════════════");
    ESP_LOGI(TAG, "Camera initialized successfully");
    ESP_LOGI(TAG, "  Resolution: %s", s_cam.has_psram ? "VGA 640x480" : "QVGA 320x240");
    ESP_LOGI(TAG, "  Buffer: %s", s_cam.has_psram ? "PSRAM" : "DRAM");
    ESP_LOGI(TAG, "  Free heap: %lu KB", (unsigned long)(esp_get_free_heap_size() / 1024));
    ESP_LOGI(TAG, "════════════════════════════════════════");

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

esp_err_t ov2640_start(void) 
{ 
    s_cam.streaming = true;
    return ESP_OK; 
}

esp_err_t ov2640_stop(void) 
{ 
    s_cam.streaming = false;
    return ESP_OK; 
}

esp_err_t ov2640_capture(ov2640_frame_t *frame)
{
    if (!s_cam.initialized || !frame) {
        return ESP_ERR_INVALID_STATE;
    }
    
    camera_fb_t *fb = esp_camera_fb_get();
    if (!fb) {
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
    // Note: Frame is released via esp_camera_fb_return() in main loop
}

float ov2640_get_fps(void) 
{ 
    return s_cam.current_fps; 
}

void ov2640_set_flash(bool on) 
{ 
    gpio_set_level(CAM_PIN_FLASH, on ? 1 : 0); 
}

bool ov2640_has_psram(void)
{
    return s_cam.has_psram;
}
