/**
 * @file mavlink_telemetry.h
 * @brief MAVLink telemetri modülü
 */

#ifndef MAVLINK_TELEMETRY_H
#define MAVLINK_TELEMETRY_H

#include "esp_err.h"
#include <stdint.h>
#include <stdbool.h>

// Varsayılan ayarlar
#ifndef MAVLINK_UART_NUM
#define MAVLINK_UART_NUM 1
#endif

#ifndef MAVLINK_UART_TX_PIN
#define MAVLINK_UART_TX_PIN 1  // ESP32-CAM: GPIO1 (TX)
#endif

#ifndef MAVLINK_UART_RX_PIN
#define MAVLINK_UART_RX_PIN 3  // ESP32-CAM: GPIO3 (RX)
#endif

#ifndef MAVLINK_UART_BAUD
#define MAVLINK_UART_BAUD 57600
#endif

#ifndef MAVLINK_UDP_PORT
#define MAVLINK_UDP_PORT 14550
#endif

// Heartbeat bilgisi
typedef struct {
    uint8_t type;
    uint8_t autopilot;
    uint8_t base_mode;
    uint32_t custom_mode;
    uint8_t system_status;
} mavlink_heartbeat_info_t;

// Callback tipi
typedef void (*mavlink_heartbeat_cb_t)(const mavlink_heartbeat_info_t *info, void *arg);

// Konfigürasyon
typedef struct {
    int uart_num;
    int uart_tx_pin;
    int uart_rx_pin;
    int uart_baud;
    int udp_port;
    mavlink_heartbeat_cb_t on_heartbeat;
    void *callback_arg;
} mavlink_config_t;

/**
 * @brief MAVLink başlat
 */
esp_err_t mavlink_telemetry_init(const mavlink_config_t *config);

/**
 * @brief MAVLink durdur
 */
esp_err_t mavlink_telemetry_deinit(void);

/**
 * @brief Telemetri başlat
 */
esp_err_t mavlink_telemetry_start(void);

/**
 * @brief Telemetri durdur
 */
esp_err_t mavlink_telemetry_stop(void);

/**
 * @brief GCS bağlı mı
 */
bool mavlink_telemetry_is_gcs_connected(void);

#endif // MAVLINK_TELEMETRY_H
