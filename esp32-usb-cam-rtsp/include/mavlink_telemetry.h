/**
 * @file mavlink_telemetry.h
 * @brief MAVLink Telemetri Modülü
 * 
 * Pixhawk'tan UART üzerinden MAVLink mesajları alır ve
 * WiFi üzerinden UDP port 14550'den yayınlar.
 * Aynı zamanda GCS'den gelen komutları Pixhawk'a iletir.
 */

#ifndef MAVLINK_TELEMETRY_H
#define MAVLINK_TELEMETRY_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

// UART Yapılandırması (Pixhawk bağlantısı)
#ifndef MAVLINK_UART_NUM
#define MAVLINK_UART_NUM        1           // UART1
#endif

#ifndef MAVLINK_UART_TX_PIN
#define MAVLINK_UART_TX_PIN     17          // GPIO17 -> Pixhawk RX
#endif

#ifndef MAVLINK_UART_RX_PIN
#define MAVLINK_UART_RX_PIN     18          // GPIO18 -> Pixhawk TX
#endif

#ifndef MAVLINK_UART_BAUD
#define MAVLINK_UART_BAUD       115200      // Pixhawk varsayılan baud
#endif

// UDP Yapılandırması
#ifndef MAVLINK_UDP_PORT
#define MAVLINK_UDP_PORT        14550       // QGroundControl varsayılan port
#endif

#ifndef MAVLINK_UDP_PORT_OUT
#define MAVLINK_UDP_PORT_OUT    14555       // Çıkış portu (opsiyonel)
#endif

// Buffer boyutları
#define MAVLINK_BUFFER_SIZE     2048
#define MAVLINK_MAX_PACKET_LEN  280

// Maksimum GCS istemci sayısı
#define MAVLINK_MAX_GCS_CLIENTS 4

/**
 * @brief Telemetri modülü durumu
 */
typedef enum {
    MAVLINK_STATE_STOPPED = 0,
    MAVLINK_STATE_RUNNING,
    MAVLINK_STATE_PIXHAWK_CONNECTED,
    MAVLINK_STATE_GCS_CONNECTED,
    MAVLINK_STATE_ERROR
} mavlink_state_t;

/**
 * @brief Telemetri istatistikleri
 */
typedef struct {
    uint32_t uart_rx_bytes;         // UART'tan alınan byte
    uint32_t uart_tx_bytes;         // UART'a gönderilen byte
    uint32_t udp_rx_bytes;          // UDP'den alınan byte
    uint32_t udp_tx_bytes;          // UDP'ye gönderilen byte
    uint32_t mavlink_messages_rx;   // Alınan MAVLink mesaj sayısı
    uint32_t mavlink_messages_tx;   // Gönderilen MAVLink mesaj sayısı
    uint32_t parse_errors;          // Parse hataları
    uint32_t gcs_clients;           // Bağlı GCS sayısı
    uint64_t uptime_ms;             // Çalışma süresi
    uint8_t pixhawk_system_id;      // Pixhawk sistem ID
    uint8_t pixhawk_component_id;   // Pixhawk component ID
} mavlink_stats_t;

/**
 * @brief Heartbeat bilgisi
 */
typedef struct {
    uint8_t system_id;
    uint8_t component_id;
    uint8_t type;                   // MAV_TYPE
    uint8_t autopilot;              // MAV_AUTOPILOT
    uint8_t base_mode;
    uint32_t custom_mode;
    uint8_t system_status;          // MAV_STATE
    uint64_t last_heartbeat_time;
} mavlink_heartbeat_info_t;

/**
 * @brief GCS istemci bilgisi
 */
typedef struct {
    uint32_t ip_addr;
    uint16_t port;
    uint64_t last_seen;
    uint32_t messages_sent;
    uint32_t messages_received;
} mavlink_gcs_client_t;

/**
 * @brief Yapılandırma
 */
typedef struct {
    // UART ayarları
    int uart_num;
    int uart_tx_pin;
    int uart_rx_pin;
    int uart_baud;
    
    // UDP ayarları
    uint16_t udp_port;
    
    // Opsiyonel callback'ler
    void (*on_heartbeat)(const mavlink_heartbeat_info_t* info, void* arg);
    void (*on_gcs_connect)(uint32_t ip, uint16_t port, void* arg);
    void (*on_gcs_disconnect)(uint32_t ip, uint16_t port, void* arg);
    void* callback_arg;
} mavlink_config_t;

/**
 * @brief MAVLink telemetri modülünü başlat
 * 
 * @param config Yapılandırma (NULL ise varsayılanlar)
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t mavlink_telemetry_init(const mavlink_config_t* config);

/**
 * @brief MAVLink telemetri modülünü kapat
 * 
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t mavlink_telemetry_deinit(void);

/**
 * @brief Telemetri yayınını başlat
 * 
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t mavlink_telemetry_start(void);

/**
 * @brief Telemetri yayınını durdur
 * 
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t mavlink_telemetry_stop(void);

/**
 * @brief Mevcut durumu al
 * 
 * @return mavlink_state_t Durum
 */
mavlink_state_t mavlink_telemetry_get_state(void);

/**
 * @brief İstatistikleri al
 * 
 * @param stats İstatistik yapısı (çıktı)
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t mavlink_telemetry_get_stats(mavlink_stats_t* stats);

/**
 * @brief Son heartbeat bilgisini al
 * 
 * @param info Heartbeat bilgisi (çıktı)
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t mavlink_telemetry_get_heartbeat(mavlink_heartbeat_info_t* info);

/**
 * @brief Bağlı GCS istemcilerini al
 * 
 * @param clients İstemci dizisi (çıktı)
 * @param max_clients Maksimum istemci
 * @return uint8_t Döndürülen istemci sayısı
 */
uint8_t mavlink_telemetry_get_gcs_clients(mavlink_gcs_client_t* clients, uint8_t max_clients);

/**
 * @brief Pixhawk bağlı mı kontrol et
 * 
 * @return bool true bağlı
 */
bool mavlink_telemetry_is_pixhawk_connected(void);

/**
 * @brief GCS bağlı mı kontrol et
 * 
 * @return bool true en az bir GCS bağlı
 */
bool mavlink_telemetry_is_gcs_connected(void);

/**
 * @brief Manuel olarak MAVLink mesajı gönder (UART'a)
 * 
 * @param data Mesaj verisi
 * @param len Veri uzunluğu
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t mavlink_telemetry_send_to_pixhawk(const uint8_t* data, size_t len);

/**
 * @brief Manuel olarak MAVLink mesajı gönder (UDP'ye)
 * 
 * @param data Mesaj verisi
 * @param len Veri uzunluğu
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t mavlink_telemetry_send_to_gcs(const uint8_t* data, size_t len);

#ifdef __cplusplus
}
#endif

#endif // MAVLINK_TELEMETRY_H
