/**
 * @file wifi_ap.c
 * @brief WiFi Access Point modülü implementasyonu
 */

#include "wifi_ap.h"
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_mac.h"
#include "lwip/err.h"
#include "lwip/sys.h"
#include "dhcpserver/dhcpserver.h"

static const char *TAG = "WIFI_AP";

// Modül durumu
static struct
{
    bool initialized;
    wifi_ap_state_t state;
    esp_netif_t *netif;
    wifi_ap_callback_t callback;
    void *callback_arg;
    uint8_t client_count;
} s_wifi_ap = {0};

// Event handler
static void wifi_event_handler(void *arg, esp_event_base_t event_base,
                               int32_t event_id, void *event_data)
{
    if (event_base == WIFI_EVENT)
    {
        switch (event_id)
        {
        case WIFI_EVENT_AP_START:
            ESP_LOGI(TAG, "AP Started - SSID: %s", WIFI_AP_SSID);
            s_wifi_ap.state = WIFI_AP_STATE_STARTED;
            if (s_wifi_ap.callback)
            {
                s_wifi_ap.callback(s_wifi_ap.state, s_wifi_ap.callback_arg);
            }
            break;

        case WIFI_EVENT_AP_STOP:
            ESP_LOGI(TAG, "AP Stopped");
            s_wifi_ap.state = WIFI_AP_STATE_STOPPED;
            s_wifi_ap.client_count = 0;
            if (s_wifi_ap.callback)
            {
                s_wifi_ap.callback(s_wifi_ap.state, s_wifi_ap.callback_arg);
            }
            break;

        case WIFI_EVENT_AP_STACONNECTED:
        {
            wifi_event_ap_staconnected_t *event = (wifi_event_ap_staconnected_t *)event_data;
            ESP_LOGI(TAG, "Client connected - MAC: " MACSTR ", AID: %d",
                     MAC2STR(event->mac), event->aid);
            s_wifi_ap.client_count++;
            s_wifi_ap.state = WIFI_AP_STATE_CLIENT_CONNECTED;
            if (s_wifi_ap.callback)
            {
                s_wifi_ap.callback(s_wifi_ap.state, s_wifi_ap.callback_arg);
            }
            break;
        }

        case WIFI_EVENT_AP_STADISCONNECTED:
        {
            wifi_event_ap_stadisconnected_t *event = (wifi_event_ap_stadisconnected_t *)event_data;
            ESP_LOGI(TAG, "Client disconnected - MAC: " MACSTR ", AID: %d",
                     MAC2STR(event->mac), event->aid);
            if (s_wifi_ap.client_count > 0)
            {
                s_wifi_ap.client_count--;
            }
            if (s_wifi_ap.client_count == 0)
            {
                s_wifi_ap.state = WIFI_AP_STATE_STARTED;
            }
            if (s_wifi_ap.callback)
            {
                s_wifi_ap.callback(s_wifi_ap.state, s_wifi_ap.callback_arg);
            }
            break;
        }

        default:
            break;
        }
    }
}

esp_err_t wifi_ap_init(void)
{
    if (s_wifi_ap.initialized)
    {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    esp_err_t ret;

    // Network interface başlat
    ret = esp_netif_init();
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE)
    {
        ESP_LOGE(TAG, "esp_netif_init failed: %s", esp_err_to_name(ret));
        return ret;
    }

    // Event loop oluştur
    ret = esp_event_loop_create_default();
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE)
    {
        ESP_LOGE(TAG, "esp_event_loop_create_default failed: %s", esp_err_to_name(ret));
        return ret;
    }

    // AP network interface oluştur
    s_wifi_ap.netif = esp_netif_create_default_wifi_ap();
    if (!s_wifi_ap.netif)
    {
        ESP_LOGE(TAG, "Failed to create AP netif");
        return ESP_FAIL;
    }

    // Statik IP yapılandırması (192.168.4.1)
    esp_netif_ip_info_t ip_info;
    memset(&ip_info, 0, sizeof(esp_netif_ip_info_t));

    ip_info.ip.addr = ipaddr_addr(WIFI_AP_IP);
    ip_info.gw.addr = ipaddr_addr(WIFI_AP_GATEWAY);
    ip_info.netmask.addr = ipaddr_addr(WIFI_AP_NETMASK);

    // DHCP server'ı durdur, IP ayarla, tekrar başlat
    esp_netif_dhcps_stop(s_wifi_ap.netif);

    ret = esp_netif_set_ip_info(s_wifi_ap.netif, &ip_info);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to set IP info: %s", esp_err_to_name(ret));
        return ret;
    }

    // DHCP lease aralığını ayarla
    dhcps_lease_t dhcp_lease;
    dhcp_lease.enable = true;
    dhcp_lease.start_ip.addr = ipaddr_addr(WIFI_AP_DHCP_START);
    dhcp_lease.end_ip.addr = ipaddr_addr(WIFI_AP_DHCP_END);

    esp_netif_dhcps_option(s_wifi_ap.netif, ESP_NETIF_OP_SET,
                           ESP_NETIF_REQUESTED_IP_ADDRESS, &dhcp_lease, sizeof(dhcp_lease));

    // DHCP server'ı başlat
    ret = esp_netif_dhcps_start(s_wifi_ap.netif);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to start DHCP server: %s", esp_err_to_name(ret));
        return ret;
    }

    // WiFi başlat
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ret = esp_wifi_init(&cfg);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "esp_wifi_init failed: %s", esp_err_to_name(ret));
        return ret;
    }

    // Event handler kaydet
    ret = esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID,
                                              &wifi_event_handler, NULL, NULL);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Failed to register event handler: %s", esp_err_to_name(ret));
        return ret;
    }

    // AP modunu ayarla
    ret = esp_wifi_set_mode(WIFI_MODE_AP);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "esp_wifi_set_mode failed: %s", esp_err_to_name(ret));
        return ret;
    }

    // AP yapılandırması
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

    // Şifre boşsa open AP
    if (strlen(WIFI_AP_PASS) == 0)
    {
        wifi_config.ap.authmode = WIFI_AUTH_OPEN;
    }

    ret = esp_wifi_set_config(WIFI_IF_AP, &wifi_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "esp_wifi_set_config failed: %s", esp_err_to_name(ret));
        return ret;
    }

    s_wifi_ap.initialized = true;
    s_wifi_ap.state = WIFI_AP_STATE_STOPPED;

    ESP_LOGI(TAG, "WiFi AP initialized");
    ESP_LOGI(TAG, "  SSID: %s", WIFI_AP_SSID);
    ESP_LOGI(TAG, "  Password: %s", WIFI_AP_PASS);
    ESP_LOGI(TAG, "  IP: %s", WIFI_AP_IP);
    ESP_LOGI(TAG, "  Subnet: %s", WIFI_AP_NETMASK);
    ESP_LOGI(TAG, "  DHCP Range: %s - %s", WIFI_AP_DHCP_START, WIFI_AP_DHCP_END);

    return ESP_OK;
}

esp_err_t wifi_ap_start(void)
{
    if (!s_wifi_ap.initialized)
    {
        ESP_LOGE(TAG, "Not initialized");
        return ESP_ERR_INVALID_STATE;
    }

    esp_err_t ret = esp_wifi_start();
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "esp_wifi_start failed: %s", esp_err_to_name(ret));
        s_wifi_ap.state = WIFI_AP_STATE_ERROR;
        return ret;
    }

    ESP_LOGI(TAG, "WiFi AP started");
    return ESP_OK;
}

esp_err_t wifi_ap_stop(void)
{
    if (!s_wifi_ap.initialized)
    {
        return ESP_ERR_INVALID_STATE;
    }

    esp_err_t ret = esp_wifi_stop();
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "esp_wifi_stop failed: %s", esp_err_to_name(ret));
        return ret;
    }

    s_wifi_ap.state = WIFI_AP_STATE_STOPPED;
    s_wifi_ap.client_count = 0;

    ESP_LOGI(TAG, "WiFi AP stopped");
    return ESP_OK;
}

wifi_ap_state_t wifi_ap_get_state(void)
{
    return s_wifi_ap.state;
}

uint8_t wifi_ap_get_client_count(void)
{
    return s_wifi_ap.client_count;
}

uint8_t wifi_ap_get_clients(wifi_ap_client_t *clients, uint8_t max_clients)
{
    if (!clients || max_clients == 0)
    {
        return 0;
    }

    wifi_sta_list_t sta_list;
    esp_wifi_ap_get_sta_list(&sta_list);

    uint8_t count = (sta_list.num < max_clients) ? sta_list.num : max_clients;

    for (uint8_t i = 0; i < count; i++)
    {
        memcpy(clients[i].mac, sta_list.sta[i].mac, 6);
        clients[i].ip = 0; // IP DHCP'den alınabilir
    }

    return count;
}

void wifi_ap_set_callback(wifi_ap_callback_t callback, void *arg)
{
    s_wifi_ap.callback = callback;
    s_wifi_ap.callback_arg = arg;
}

const char *wifi_ap_get_ip(void)
{
    return WIFI_AP_IP;
}
