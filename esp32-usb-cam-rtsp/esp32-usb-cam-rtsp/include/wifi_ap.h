/**
 * @file wifi_ap.h
 * @brief WiFi Access Point modülü
 */

#ifndef WIFI_AP_H
#define WIFI_AP_H

#include "esp_err.h"
#include <stdint.h>

// AP ayarları
#ifndef WIFI_AP_SSID
#define WIFI_AP_SSID "PixhawkDrone"
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

// AP durumu
typedef enum
{
    WIFI_AP_STATE_STOPPED,
    WIFI_AP_STATE_STARTED,
    WIFI_AP_STATE_CLIENT_CONNECTED,
    WIFI_AP_STATE_CLIENT_DISCONNECTED,
} wifi_ap_state_t;

// Callback tipi
typedef void (*wifi_ap_callback_t)(wifi_ap_state_t state, void *arg);

/**
 * @brief Callback ayarla
 */
void wifi_ap_set_callback(wifi_ap_callback_t cb, void *arg);

/**
 * @brief WiFi AP başlat
 */
esp_err_t wifi_ap_init(void);

/**
 * @brief AP'yi aktif et
 */
esp_err_t wifi_ap_start(void);

/**
 * @brief AP'yi durdur
 */
esp_err_t wifi_ap_stop(void);

/**
 * @brief Bağlı istemci sayısı
 */
uint8_t wifi_ap_get_client_count(void);

#endif // WIFI_AP_H