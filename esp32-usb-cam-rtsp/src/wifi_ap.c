/**
 * @file wifi_ap.c
 * @brief WiFi Access Point modülü
 */

#include "wifi_ap.h"
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"

static const char *TAG = "WIFI_AP";

static wifi_ap_callback_t s_callback = NULL;
static void *s_callback_arg = NULL;
static uint8_t s_client_count = 0;
static bool s_initialized = false;

static void wifi_event_handler(void *arg, esp_event_base_t event_base,
                               int32_t event_id, void *event_data)
{
    if (event_base == WIFI_EVENT) {
        switch (event_id) {
        case WIFI_EVENT_AP_START:
            ESP_LOGI(TAG, "AP Started - SSID: %s", WIFI_AP_SSID);
            if (s_callback) {
                s_callback(WIFI_AP_STATE_STARTED, s_callback_arg);
            }
            break;
            
        case WIFI_EVENT_AP_STOP:
            ESP_LOGI(TAG, "AP Stopped");
            if (s_callback) {
                s_callback(WIFI_AP_STATE_STOPPED, s_callback_arg);
            }
            break;
            
        case WIFI_EVENT_AP_STACONNECTED: {
            wifi_event_ap_staconnected_t *event = (wifi_event_ap_staconnected_t *)event_data;
            ESP_LOGI(TAG, "Client connected - MAC: %02x:%02x:%02x:%02x:%02x:%02x",
                     event->mac[0], event->mac[1], event->mac[2],
                     event->mac[3], event->mac[4], event->mac[5]);
            s_client_count++;
            if (s_callback) {
                s_callback(WIFI_AP_STATE_CLIENT_CONNECTED, s_callback_arg);
            }
            break;
        }
        
        case WIFI_EVENT_AP_STADISCONNECTED: {
            wifi_event_ap_stadisconnected_t *event = (wifi_event_ap_stadisconnected_t *)event_data;
            ESP_LOGI(TAG, "Client disconnected - MAC: %02x:%02x:%02x:%02x:%02x:%02x",
                     event->mac[0], event->mac[1], event->mac[2],
                     event->mac[3], event->mac[4], event->mac[5]);
            if (s_client_count > 0) s_client_count--;
            if (s_callback) {
                s_callback(WIFI_AP_STATE_CLIENT_DISCONNECTED, s_callback_arg);
            }
            break;
        }
        
        default:
            break;
        }
    }
}

void wifi_ap_set_callback(wifi_ap_callback_t cb, void *arg)
{
    s_callback = cb;
    s_callback_arg = arg;
}

esp_err_t wifi_ap_init(void)
{
    if (s_initialized) {
        return ESP_OK;
    }
    
    // Network interface başlat
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    
    esp_netif_create_default_wifi_ap();
    
    // WiFi başlat
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));
    
    // Event handler kaydet
    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT,
                                                        ESP_EVENT_ANY_ID,
                                                        &wifi_event_handler,
                                                        NULL,
                                                        NULL));
    
    // AP konfigürasyonu
    wifi_config_t wifi_config = {
        .ap = {
            .ssid = WIFI_AP_SSID,
            .ssid_len = strlen(WIFI_AP_SSID),
            .channel = WIFI_AP_CHANNEL,
            .password = WIFI_AP_PASS,
            .max_connection = WIFI_AP_MAX_CONN,
            .authmode = WIFI_AUTH_WPA2_PSK,
            .pmf_cfg = {
                .required = false,
            },
        },
    };
    
    // Şifre boşsa açık ağ yap
    if (strlen(WIFI_AP_PASS) == 0) {
        wifi_config.ap.authmode = WIFI_AUTH_OPEN;
    }
    
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_AP));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &wifi_config));
    
    s_initialized = true;
    return ESP_OK;
}

esp_err_t wifi_ap_start(void)
{
    return esp_wifi_start();
}

esp_err_t wifi_ap_stop(void)
{
    return esp_wifi_stop();
}

uint8_t wifi_ap_get_client_count(void)
{
    return s_client_count;
}
