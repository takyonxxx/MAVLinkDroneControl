/**
 * @file rtsp_server.h
 * @brief RTSP Server modülü
 */

#ifndef RTSP_SERVER_H
#define RTSP_SERVER_H

#include "esp_err.h"
#include <stdint.h>
#include <stdbool.h>

// Varsayılan ayarlar
#ifndef RTSP_PORT
#define RTSP_PORT 554
#endif

#ifndef RTSP_STREAM_NAME
#define RTSP_STREAM_NAME "stream"
#endif

#ifndef RTSP_MAX_CLIENTS
#define RTSP_MAX_CLIENTS 2
#endif

// Frame yapısı
typedef struct {
    uint8_t *data;
    size_t size;
    size_t capacity;
    uint32_t width;
    uint32_t height;
    uint8_t format;
    uint64_t timestamp;
    uint32_t sequence;
} rtsp_frame_t;

// Callback tipi
typedef void (*rtsp_client_cb_t)(uint32_t client_id, bool connected, void *arg);

// Konfigürasyon
typedef struct {
    uint16_t port;
    const char *stream_name;
    uint8_t max_clients;
    rtsp_client_cb_t client_callback;
    void *callback_arg;
} rtsp_server_config_t;

/**
 * @brief RTSP sunucuyu başlat
 */
esp_err_t rtsp_server_init(const rtsp_server_config_t *config);

/**
 * @brief RTSP sunucuyu durdur
 */
esp_err_t rtsp_server_deinit(void);

/**
 * @brief Sunucuyu aktif et
 */
esp_err_t rtsp_server_start(void);

/**
 * @brief Sunucuyu durdur
 */
esp_err_t rtsp_server_stop(void);

/**
 * @brief Frame gönder
 */
esp_err_t rtsp_server_send_frame(const rtsp_frame_t *frame);

/**
 * @brief Bağlı istemci sayısı
 */
uint8_t rtsp_server_get_client_count(void);

#endif // RTSP_SERVER_H
