/**
 * @file ov2640_camera.h
 * @brief OV2640 Kamera modülü (ESP32-CAM)
 */

#ifndef OV2640_CAMERA_H
#define OV2640_CAMERA_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"
#include "esp_camera.h" // Use library's framesize_t

// Frame yapısı
typedef struct
{
    uint8_t *data;
    size_t size;
    uint32_t width;
    uint32_t height;
    uint64_t timestamp;
    uint32_t sequence;
} ov2640_frame_t;

// Callback tipi
typedef void (*ov2640_frame_cb_t)(ov2640_frame_t *frame, void *arg);

// Konfigürasyon
typedef struct
{
    framesize_t framesize; // Use library's type
    uint8_t quality;       // JPEG quality 10-63 (lower = better)
    uint8_t fps;
    ov2640_frame_cb_t frame_callback;
    void *callback_arg;
} ov2640_config_t;

/**
 * @brief Kamerayı başlat
 */
esp_err_t ov2640_init(const ov2640_config_t *config);

/**
 * @brief Kamerayı durdur
 */
esp_err_t ov2640_deinit(void);

/**
 * @brief Streaming başlat
 */
esp_err_t ov2640_start(void);

/**
 * @brief Streaming durdur
 */
esp_err_t ov2640_stop(void);

/**
 * @brief Tek frame al
 */
esp_err_t ov2640_capture(ov2640_frame_t *frame);

/**
 * @brief Frame'i serbest bırak
 */
void ov2640_release_frame(ov2640_frame_t *frame);

/**
 * @brief FPS değerini al
 */
float ov2640_get_fps(void);

/**
 * @brief Flash LED kontrolü
 */
void ov2640_set_flash(bool on);

#endif // OV2640_CAMERA_H