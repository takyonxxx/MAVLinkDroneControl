/**
 * @file rtsp_server.h
 * @brief Basit RTSP Server modülü
 * 
 * MJPEG stream için basit RTSP/RTP server implementasyonu.
 * RFC 2326 (RTSP) ve RFC 3550 (RTP) standartlarına uygun.
 */

#ifndef RTSP_SERVER_H
#define RTSP_SERVER_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include "esp_err.h"
#include "usb_camera.h"

#ifdef __cplusplus
extern "C" {
#endif

// Varsayılan ayarlar
#ifndef RTSP_PORT
#define RTSP_PORT 554
#endif

#ifndef RTSP_STREAM_NAME
#define RTSP_STREAM_NAME "/stream"
#endif

// Maksimum eşzamanlı istemci sayısı
#define RTSP_MAX_CLIENTS 4

// RTP varsayılan portları
#define RTP_DEFAULT_VIDEO_PORT 5004
#define RTCP_DEFAULT_VIDEO_PORT 5005

/**
 * @brief RTSP istemci durumu
 */
typedef enum {
    RTSP_CLIENT_STATE_INIT = 0,
    RTSP_CLIENT_STATE_READY,
    RTSP_CLIENT_STATE_PLAYING,
    RTSP_CLIENT_STATE_TEARDOWN
} rtsp_client_state_t;

/**
 * @brief RTSP server durumu
 */
typedef enum {
    RTSP_SERVER_STATE_STOPPED = 0,
    RTSP_SERVER_STATE_RUNNING,
    RTSP_SERVER_STATE_ERROR
} rtsp_server_state_t;

/**
 * @brief RTSP istemci bilgisi
 */
typedef struct {
    uint32_t client_id;
    char ip_addr[16];
    uint16_t rtp_port;
    rtsp_client_state_t state;
    uint64_t connected_time;
    uint32_t frames_sent;
    uint64_t bytes_sent;
} rtsp_client_info_t;

/**
 * @brief İstemci bağlantı callback tipi
 */
typedef void (*rtsp_client_callback_t)(uint32_t client_id, bool connected, void* arg);

/**
 * @brief Server istatistikleri
 */
typedef struct {
    uint32_t total_clients;         // Toplam bağlanan istemci
    uint32_t active_clients;        // Aktif istemci sayısı
    uint64_t total_frames_sent;     // Toplam gönderilen frame
    uint64_t total_bytes_sent;      // Toplam gönderilen veri
    uint64_t uptime_seconds;        // Çalışma süresi
} rtsp_server_stats_t;

/**
 * @brief RTSP server yapılandırması
 */
typedef struct {
    uint16_t port;                  // RTSP port (varsayılan 554)
    const char* stream_name;        // Stream adı (varsayılan /stream)
    uint8_t max_clients;            // Maksimum istemci
    rtsp_client_callback_t client_callback;
    void* callback_arg;
} rtsp_server_config_t;

/**
 * @brief RTSP server'ı başlat
 * 
 * @param config Server yapılandırması (NULL ise varsayılanlar kullanılır)
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t rtsp_server_init(const rtsp_server_config_t* config);

/**
 * @brief RTSP server'ı kapat
 * 
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t rtsp_server_deinit(void);

/**
 * @brief Server'ı başlat (dinlemeye başla)
 * 
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t rtsp_server_start(void);

/**
 * @brief Server'ı durdur
 * 
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t rtsp_server_stop(void);

/**
 * @brief Server durumunu al
 * 
 * @return rtsp_server_state_t Server durumu
 */
rtsp_server_state_t rtsp_server_get_state(void);

/**
 * @brief Yeni frame gönder (tüm istemcilere)
 * 
 * @param frame Gönderilecek frame
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t rtsp_server_send_frame(const usb_cam_frame_t* frame);

/**
 * @brief Aktif istemci listesini al
 * 
 * @param clients İstemci dizisi (çıktı)
 * @param max_clients Maksimum istemci
 * @return uint8_t Döndürülen istemci sayısı
 */
uint8_t rtsp_server_get_clients(rtsp_client_info_t* clients, uint8_t max_clients);

/**
 * @brief Server istatistiklerini al
 * 
 * @param stats İstatistik yapısı (çıktı)
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t rtsp_server_get_stats(rtsp_server_stats_t* stats);

/**
 * @brief RTSP URL'ini al
 * 
 * @param url_buffer URL buffer (çıktı)
 * @param buffer_size Buffer boyutu
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t rtsp_server_get_url(char* url_buffer, size_t buffer_size);

/**
 * @brief Belirli bir istemciyi kes
 * 
 * @param client_id İstemci ID
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t rtsp_server_disconnect_client(uint32_t client_id);

#ifdef __cplusplus
}
#endif

#endif // RTSP_SERVER_H
