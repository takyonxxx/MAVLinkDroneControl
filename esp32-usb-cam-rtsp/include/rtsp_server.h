/**
 * RTSP Server for ESP32-CAM
 * Supports: MJPEG over RTP/UDP
 */

#ifndef RTSP_SERVER_H
#define RTSP_SERVER_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

#define RTSP_DEFAULT_PORT       8554
#define RTP_DEFAULT_PORT        5004
#define RTCP_DEFAULT_PORT       5005

typedef struct {
    uint8_t *data;
    size_t size;
    size_t capacity;
    uint32_t width;
    uint32_t height;
    uint32_t format;
    int64_t timestamp;
    uint32_t sequence;
} rtsp_frame_t;

typedef void (*rtsp_client_callback_t)(uint32_t client_id, bool connected, void *arg);

typedef struct {
    uint16_t rtsp_port;
    uint16_t rtp_port;
    const char *stream_name;
    uint8_t max_clients;
    rtsp_client_callback_t client_callback;
    void *callback_arg;
} rtsp_server_config_t;

esp_err_t rtsp_server_init(const rtsp_server_config_t *config);
esp_err_t rtsp_server_deinit(void);
esp_err_t rtsp_server_start(void);
esp_err_t rtsp_server_stop(void);
esp_err_t rtsp_server_send_frame(const rtsp_frame_t *frame);
uint8_t rtsp_server_get_client_count(void);

#endif
