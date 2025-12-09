/**
 * @file wifi_ap.h
 * @brief WiFi Access Point modülü
 * 
 * ESP32-S3 üzerinde WiFi hotspot oluşturur.
 * IP adresi: 192.168.4.1 (Gateway)
 * Subnet: 192.168.4.0/24
 */

#ifndef WIFI_AP_H
#define WIFI_AP_H

#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"
#include "esp_netif.h"

#ifdef __cplusplus
extern "C" {
#endif

// Varsayılan ayarlar (platformio.ini'den override edilebilir)
#ifndef WIFI_AP_SSID
#define WIFI_AP_SSID "ESP32-CAM-RTSP"
#endif

#ifndef WIFI_AP_PASS
#define WIFI_AP_PASS "12345678"
#endif

#ifndef WIFI_AP_CHANNEL
#define WIFI_AP_CHANNEL 6
#endif

#ifndef WIFI_AP_MAX_CONN
#define WIFI_AP_MAX_CONN 4
#endif

// IP Yapılandırması (192.168.4.x subnet)
#define WIFI_AP_IP          "192.168.4.1"
#define WIFI_AP_GATEWAY     "192.168.4.1"
#define WIFI_AP_NETMASK     "255.255.255.0"

// DHCP aralığı
#define WIFI_AP_DHCP_START  "192.168.4.100"
#define WIFI_AP_DHCP_END    "192.168.4.200"

/**
 * @brief WiFi AP durumu
 */
typedef enum {
    WIFI_AP_STATE_STOPPED = 0,
    WIFI_AP_STATE_STARTED,
    WIFI_AP_STATE_CLIENT_CONNECTED,
    WIFI_AP_STATE_ERROR
} wifi_ap_state_t;

/**
 * @brief Bağlı istemci bilgisi
 */
typedef struct {
    uint8_t mac[6];
    uint32_t ip;
} wifi_ap_client_t;

/**
 * @brief WiFi AP callback fonksiyon tipi
 */
typedef void (*wifi_ap_callback_t)(wifi_ap_state_t state, void* arg);

/**
 * @brief WiFi AP modülünü başlat
 * 
 * @return esp_err_t ESP_OK başarılı, diğer hata kodu
 */
esp_err_t wifi_ap_init(void);

/**
 * @brief WiFi AP'yi başlat (yayına başla)
 * 
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t wifi_ap_start(void);

/**
 * @brief WiFi AP'yi durdur
 * 
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t wifi_ap_stop(void);

/**
 * @brief WiFi AP durumunu al
 * 
 * @return wifi_ap_state_t Mevcut durum
 */
wifi_ap_state_t wifi_ap_get_state(void);

/**
 * @brief Bağlı istemci sayısını al
 * 
 * @return uint8_t İstemci sayısı
 */
uint8_t wifi_ap_get_client_count(void);

/**
 * @brief Bağlı istemcilerin listesini al
 * 
 * @param clients İstemci dizisi (çıktı)
 * @param max_clients Maksimum istemci sayısı
 * @return uint8_t Döndürülen istemci sayısı
 */
uint8_t wifi_ap_get_clients(wifi_ap_client_t* clients, uint8_t max_clients);

/**
 * @brief Durum değişikliği callback'i kaydet
 * 
 * @param callback Callback fonksiyonu
 * @param arg Kullanıcı argümanı
 */
void wifi_ap_set_callback(wifi_ap_callback_t callback, void* arg);

/**
 * @brief AP IP adresini al
 * 
 * @return const char* IP adresi string'i
 */
const char* wifi_ap_get_ip(void);

#ifdef __cplusplus
}
#endif

#endif // WIFI_AP_H