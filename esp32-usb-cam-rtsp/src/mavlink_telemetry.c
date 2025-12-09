/**
 * @file mavlink_telemetry.c
 * @brief MAVLink Telemetri Modülü implementasyonu
 * 
 * Pixhawk <-> ESP32 <-> GCS köprüsü
 */

#include "mavlink_telemetry.h"
#include "mavlink_types.h"
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "freertos/queue.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "driver/uart.h"
#include "lwip/sockets.h"
#include "lwip/netdb.h"

static const char* TAG = "MAVLINK";

// CRC-16/MCRF4XX tablosu (X.25)
static const uint16_t crc_table[256] = {
    0x0000, 0x1021, 0x2042, 0x3063, 0x4084, 0x50a5, 0x60c6, 0x70e7,
    0x8108, 0x9129, 0xa14a, 0xb16b, 0xc18c, 0xd1ad, 0xe1ce, 0xf1ef,
    0x1231, 0x0210, 0x3273, 0x2252, 0x52b5, 0x4294, 0x72f7, 0x62d6,
    0x9339, 0x8318, 0xb37b, 0xa35a, 0xd3bd, 0xc39c, 0xf3ff, 0xe3de,
    0x2462, 0x3443, 0x0420, 0x1401, 0x64e6, 0x74c7, 0x44a4, 0x5485,
    0xa56a, 0xb54b, 0x8528, 0x9509, 0xe5ee, 0xf5cf, 0xc5ac, 0xd58d,
    0x3653, 0x2672, 0x1611, 0x0630, 0x76d7, 0x66f6, 0x5695, 0x46b4,
    0xb75b, 0xa77a, 0x9719, 0x8738, 0xf7df, 0xe7fe, 0xd79d, 0xc7bc,
    0x48c4, 0x58e5, 0x6886, 0x78a7, 0x0840, 0x1861, 0x2802, 0x3823,
    0xc9cc, 0xd9ed, 0xe98e, 0xf9af, 0x8948, 0x9969, 0xa90a, 0xb92b,
    0x5af5, 0x4ad4, 0x7ab7, 0x6a96, 0x1a71, 0x0a50, 0x3a33, 0x2a12,
    0xdbfd, 0xcbdc, 0xfbbf, 0xeb9e, 0x9b79, 0x8b58, 0xbb3b, 0xab1a,
    0x6ca6, 0x7c87, 0x4ce4, 0x5cc5, 0x2c22, 0x3c03, 0x0c60, 0x1c41,
    0xedae, 0xfd8f, 0xcdec, 0xddcd, 0xad2a, 0xbd0b, 0x8d68, 0x9d49,
    0x7e97, 0x6eb6, 0x5ed5, 0x4ef4, 0x3e13, 0x2e32, 0x1e51, 0x0e70,
    0xff9f, 0xefbe, 0xdfdd, 0xcffc, 0xbf1b, 0xaf3a, 0x9f59, 0x8f78,
    0x9188, 0x81a9, 0xb1ca, 0xa1eb, 0xd10c, 0xc12d, 0xf14e, 0xe16f,
    0x1080, 0x00a1, 0x30c2, 0x20e3, 0x5004, 0x4025, 0x7046, 0x6067,
    0x83b9, 0x9398, 0xa3fb, 0xb3da, 0xc33d, 0xd31c, 0xe37f, 0xf35e,
    0x02b1, 0x1290, 0x22f3, 0x32d2, 0x4235, 0x5214, 0x6277, 0x7256,
    0xb5ea, 0xa5cb, 0x95a8, 0x8589, 0xf56e, 0xe54f, 0xd52c, 0xc50d,
    0x34e2, 0x24c3, 0x14a0, 0x0481, 0x7466, 0x6447, 0x5424, 0x4405,
    0xa7db, 0xb7fa, 0x8799, 0x97b8, 0xe75f, 0xf77e, 0xc71d, 0xd73c,
    0x26d3, 0x36f2, 0x0691, 0x16b0, 0x6657, 0x7676, 0x4615, 0x5634,
    0xd94c, 0xc96d, 0xf90e, 0xe92f, 0x99c8, 0x89e9, 0xb98a, 0xa9ab,
    0x5844, 0x4865, 0x7806, 0x6827, 0x18c0, 0x08e1, 0x3882, 0x28a3,
    0xcb7d, 0xdb5c, 0xeb3f, 0xfb1e, 0x8bf9, 0x9bd8, 0xabbb, 0xbb9a,
    0x4a75, 0x5a54, 0x6a37, 0x7a16, 0x0af1, 0x1ad0, 0x2ab3, 0x3a92,
    0xfd2e, 0xed0f, 0xdd6c, 0xcd4d, 0xbdaa, 0xad8b, 0x9de8, 0x8dc9,
    0x7c26, 0x6c07, 0x5c64, 0x4c45, 0x3ca2, 0x2c83, 0x1ce0, 0x0cc1,
    0xef1f, 0xff3e, 0xcf5d, 0xdf7c, 0xaf9b, 0xbfba, 0x8fd9, 0x9ff8,
    0x6e17, 0x7e36, 0x4e55, 0x5e74, 0x2e93, 0x3eb2, 0x0ed1, 0x1ef0
};

// CRC_EXTRA değerleri (yaygın mesajlar için)
static const struct {
    uint32_t msgid;
    uint8_t crc_extra;
} crc_extra_table[] = {
    {0, 50},        // HEARTBEAT
    {1, 124},       // SYS_STATUS
    {2, 137},       // SYSTEM_TIME
    {4, 237},       // PING
    {24, 24},       // GPS_RAW_INT
    {30, 39},       // ATTITUDE
    {33, 104},      // GLOBAL_POSITION_INT
    {35, 244},      // RC_CHANNELS_RAW
    {36, 54},       // SERVO_OUTPUT_RAW
    {65, 118},      // RC_CHANNELS
    {74, 20},       // VFR_HUD
    {76, 152},      // COMMAND_LONG
    {77, 143},      // COMMAND_ACK
    {147, 154},     // BATTERY_STATUS
    {253, 83},      // STATUSTEXT
    {0xFFFFFFFF, 0} // End marker
};

// GCS istemci yapısı
typedef struct {
    bool active;
    struct sockaddr_in addr;
    uint64_t last_seen;
    uint32_t messages_sent;
    uint32_t messages_received;
} gcs_client_internal_t;

// Modül durumu
static struct {
    bool initialized;
    mavlink_state_t state;
    mavlink_config_t config;
    
    // UART
    QueueHandle_t uart_queue;
    
    // UDP
    int udp_socket;
    gcs_client_internal_t gcs_clients[MAVLINK_MAX_GCS_CLIENTS];
    SemaphoreHandle_t clients_mutex;
    
    // Parser
    mavlink_parser_t parser;
    
    // Heartbeat bilgisi
    mavlink_heartbeat_info_t heartbeat;
    SemaphoreHandle_t heartbeat_mutex;
    
    // İstatistikler
    mavlink_stats_t stats;
    uint64_t start_time;
    
    // Task handles
    TaskHandle_t uart_rx_task;
    TaskHandle_t udp_rx_task;
    bool tasks_running;
} s_mavlink = {0};

// Forward declarations
static void uart_rx_task(void* arg);
static void udp_rx_task(void* arg);
static void process_mavlink_message(const mavlink_message_t* msg, bool from_pixhawk);
static void forward_to_gcs(const uint8_t* data, size_t len);
static void forward_to_pixhawk(const uint8_t* data, size_t len);

// ============================================================================
// CRC Functions
// ============================================================================

void mavlink_crc_init(uint16_t* crc)
{
    *crc = 0xFFFF;
}

void mavlink_crc_accumulate(uint8_t byte, uint16_t* crc)
{
    uint8_t tmp = byte ^ (uint8_t)(*crc & 0xFF);
    tmp ^= (tmp << 4);
    *crc = (*crc >> 8) ^ ((uint16_t)tmp << 8) ^ ((uint16_t)tmp << 3) ^ ((uint16_t)tmp >> 4);
}

uint16_t mavlink_crc_calculate(const uint8_t* buffer, uint16_t length)
{
    uint16_t crc;
    mavlink_crc_init(&crc);
    while (length--) {
        mavlink_crc_accumulate(*buffer++, &crc);
    }
    return crc;
}

uint8_t mavlink_get_crc_extra(uint32_t msgid)
{
    for (int i = 0; crc_extra_table[i].msgid != 0xFFFFFFFF; i++) {
        if (crc_extra_table[i].msgid == msgid) {
            return crc_extra_table[i].crc_extra;
        }
    }
    return 0; // Bilinmeyen mesaj
}

// ============================================================================
// Parser Functions
// ============================================================================

void mavlink_parser_init(mavlink_parser_t* parser)
{
    memset(parser, 0, sizeof(mavlink_parser_t));
    parser->state = MAVLINK_PARSE_STATE_IDLE;
}

mavlink_framing_t mavlink_parse_char(mavlink_parser_t* parser, uint8_t byte, mavlink_message_t* msg)
{
    switch (parser->state) {
        case MAVLINK_PARSE_STATE_IDLE:
            if (byte == MAVLINK_STX_V1 || byte == MAVLINK_STX_V2) {
                parser->msg.magic = byte;
                parser->packet_idx = 0;
                mavlink_crc_init(&parser->checksum);
                parser->state = MAVLINK_PARSE_STATE_GOT_STX;
            }
            break;
            
        case MAVLINK_PARSE_STATE_GOT_STX:
            parser->msg.len = byte;
            mavlink_crc_accumulate(byte, &parser->checksum);
            if (parser->msg.magic == MAVLINK_STX_V2) {
                parser->state = MAVLINK_PARSE_STATE_GOT_LENGTH;
            } else {
                parser->msg.incompat_flags = 0;
                parser->msg.compat_flags = 0;
                parser->state = MAVLINK_PARSE_STATE_GOT_COMPAT_FLAGS;
            }
            break;
            
        case MAVLINK_PARSE_STATE_GOT_LENGTH:
            parser->msg.incompat_flags = byte;
            mavlink_crc_accumulate(byte, &parser->checksum);
            parser->state = MAVLINK_PARSE_STATE_GOT_INCOMPAT_FLAGS;
            break;
            
        case MAVLINK_PARSE_STATE_GOT_INCOMPAT_FLAGS:
            parser->msg.compat_flags = byte;
            mavlink_crc_accumulate(byte, &parser->checksum);
            parser->state = MAVLINK_PARSE_STATE_GOT_COMPAT_FLAGS;
            break;
            
        case MAVLINK_PARSE_STATE_GOT_COMPAT_FLAGS:
            parser->msg.seq = byte;
            mavlink_crc_accumulate(byte, &parser->checksum);
            parser->state = MAVLINK_PARSE_STATE_GOT_SEQ;
            break;
            
        case MAVLINK_PARSE_STATE_GOT_SEQ:
            parser->msg.sysid = byte;
            mavlink_crc_accumulate(byte, &parser->checksum);
            parser->state = MAVLINK_PARSE_STATE_GOT_SYSID;
            break;
            
        case MAVLINK_PARSE_STATE_GOT_SYSID:
            parser->msg.compid = byte;
            mavlink_crc_accumulate(byte, &parser->checksum);
            if (parser->msg.magic == MAVLINK_STX_V2) {
                parser->state = MAVLINK_PARSE_STATE_GOT_COMPID;
            } else {
                parser->state = MAVLINK_PARSE_STATE_GOT_MSGID3;
            }
            break;
            
        case MAVLINK_PARSE_STATE_GOT_COMPID:
            parser->msg.msgid = byte;
            mavlink_crc_accumulate(byte, &parser->checksum);
            parser->state = MAVLINK_PARSE_STATE_GOT_MSGID1;
            break;
            
        case MAVLINK_PARSE_STATE_GOT_MSGID1:
            parser->msg.msgid |= ((uint32_t)byte << 8);
            mavlink_crc_accumulate(byte, &parser->checksum);
            parser->state = MAVLINK_PARSE_STATE_GOT_MSGID2;
            break;
            
        case MAVLINK_PARSE_STATE_GOT_MSGID2:
            parser->msg.msgid |= ((uint32_t)byte << 16);
            mavlink_crc_accumulate(byte, &parser->checksum);
            parser->state = MAVLINK_PARSE_STATE_GOT_MSGID3;
            break;
            
        case MAVLINK_PARSE_STATE_GOT_MSGID3:
            if (parser->msg.magic == MAVLINK_STX_V1) {
                parser->msg.msgid = byte;
                mavlink_crc_accumulate(byte, &parser->checksum);
            }
            parser->packet_idx = 0;
            if (parser->msg.len > 0) {
                if (parser->msg.magic == MAVLINK_STX_V1) {
                    parser->state = MAVLINK_PARSE_STATE_GOT_PAYLOAD;
                } else {
                    parser->msg.payload[parser->packet_idx++] = byte;
                    mavlink_crc_accumulate(byte, &parser->checksum);
                    if (parser->packet_idx >= parser->msg.len) {
                        parser->state = MAVLINK_PARSE_STATE_GOT_PAYLOAD;
                    }
                }
            } else {
                parser->state = MAVLINK_PARSE_STATE_GOT_PAYLOAD;
            }
            break;
            
        case MAVLINK_PARSE_STATE_GOT_PAYLOAD:
            if (parser->packet_idx < parser->msg.len) {
                parser->msg.payload[parser->packet_idx++] = byte;
                mavlink_crc_accumulate(byte, &parser->checksum);
                if (parser->packet_idx >= parser->msg.len) {
                    // CRC extra ekle
                    uint8_t crc_extra = mavlink_get_crc_extra(parser->msg.msgid);
                    mavlink_crc_accumulate(crc_extra, &parser->checksum);
                }
            } else {
                // İlk CRC byte
                parser->msg.checksum = byte;
                parser->state = MAVLINK_PARSE_STATE_GOT_CRC1;
            }
            break;
            
        case MAVLINK_PARSE_STATE_GOT_CRC1:
            parser->msg.checksum |= ((uint16_t)byte << 8);
            if (parser->msg.checksum == parser->checksum) {
                // CRC OK
                if (msg) {
                    memcpy(msg, &parser->msg, sizeof(mavlink_message_t));
                }
                parser->state = MAVLINK_PARSE_STATE_IDLE;
                return MAVLINK_FRAMING_OK;
            } else {
                // CRC hatalı
                parser->state = MAVLINK_PARSE_STATE_IDLE;
                return MAVLINK_FRAMING_BAD_CRC;
            }
            break;
            
        default:
            parser->state = MAVLINK_PARSE_STATE_IDLE;
            break;
    }
    
    return MAVLINK_FRAMING_INCOMPLETE;
}

// ============================================================================
// GCS Client Management
// ============================================================================

static gcs_client_internal_t* find_gcs_client(const struct sockaddr_in* addr)
{
    for (int i = 0; i < MAVLINK_MAX_GCS_CLIENTS; i++) {
        if (s_mavlink.gcs_clients[i].active &&
            s_mavlink.gcs_clients[i].addr.sin_addr.s_addr == addr->sin_addr.s_addr &&
            s_mavlink.gcs_clients[i].addr.sin_port == addr->sin_port) {
            return &s_mavlink.gcs_clients[i];
        }
    }
    return NULL;
}

static gcs_client_internal_t* add_gcs_client(const struct sockaddr_in* addr)
{
    // Önce mevcut mu kontrol et
    gcs_client_internal_t* client = find_gcs_client(addr);
    if (client) {
        client->last_seen = esp_timer_get_time() / 1000;
        return client;
    }
    
    // Yeni slot bul
    for (int i = 0; i < MAVLINK_MAX_GCS_CLIENTS; i++) {
        if (!s_mavlink.gcs_clients[i].active) {
            s_mavlink.gcs_clients[i].active = true;
            memcpy(&s_mavlink.gcs_clients[i].addr, addr, sizeof(struct sockaddr_in));
            s_mavlink.gcs_clients[i].last_seen = esp_timer_get_time() / 1000;
            s_mavlink.gcs_clients[i].messages_sent = 0;
            s_mavlink.gcs_clients[i].messages_received = 0;
            
            s_mavlink.stats.gcs_clients++;
            
            ESP_LOGI(TAG, "New GCS client: %s:%d",
                     inet_ntoa(addr->sin_addr), ntohs(addr->sin_port));
            
            if (s_mavlink.config.on_gcs_connect) {
                s_mavlink.config.on_gcs_connect(addr->sin_addr.s_addr, 
                                                 ntohs(addr->sin_port),
                                                 s_mavlink.config.callback_arg);
            }
            
            return &s_mavlink.gcs_clients[i];
        }
    }
    
    ESP_LOGW(TAG, "No free GCS client slots");
    return NULL;
}

static void cleanup_stale_gcs_clients(void)
{
    uint64_t now = esp_timer_get_time() / 1000;
    const uint64_t timeout_ms = 30000; // 30 saniye timeout
    
    for (int i = 0; i < MAVLINK_MAX_GCS_CLIENTS; i++) {
        if (s_mavlink.gcs_clients[i].active) {
            if (now - s_mavlink.gcs_clients[i].last_seen > timeout_ms) {
                ESP_LOGI(TAG, "GCS client timeout: %s:%d",
                         inet_ntoa(s_mavlink.gcs_clients[i].addr.sin_addr),
                         ntohs(s_mavlink.gcs_clients[i].addr.sin_port));
                
                if (s_mavlink.config.on_gcs_disconnect) {
                    s_mavlink.config.on_gcs_disconnect(
                        s_mavlink.gcs_clients[i].addr.sin_addr.s_addr,
                        ntohs(s_mavlink.gcs_clients[i].addr.sin_port),
                        s_mavlink.config.callback_arg);
                }
                
                s_mavlink.gcs_clients[i].active = false;
                if (s_mavlink.stats.gcs_clients > 0) {
                    s_mavlink.stats.gcs_clients--;
                }
            }
        }
    }
}

// ============================================================================
// Message Processing
// ============================================================================

static void process_mavlink_message(const mavlink_message_t* msg, bool from_pixhawk)
{
    s_mavlink.stats.mavlink_messages_rx++;
    
    // Heartbeat işle
    if (msg->msgid == MAVLINK_MSG_ID_HEARTBEAT && from_pixhawk) {
        xSemaphoreTake(s_mavlink.heartbeat_mutex, portMAX_DELAY);
        
        mavlink_heartbeat_t* hb = (mavlink_heartbeat_t*)msg->payload;
        s_mavlink.heartbeat.system_id = msg->sysid;
        s_mavlink.heartbeat.component_id = msg->compid;
        s_mavlink.heartbeat.type = hb->type;
        s_mavlink.heartbeat.autopilot = hb->autopilot;
        s_mavlink.heartbeat.base_mode = hb->base_mode;
        s_mavlink.heartbeat.custom_mode = hb->custom_mode;
        s_mavlink.heartbeat.system_status = hb->system_status;
        s_mavlink.heartbeat.last_heartbeat_time = esp_timer_get_time() / 1000;
        
        s_mavlink.stats.pixhawk_system_id = msg->sysid;
        s_mavlink.stats.pixhawk_component_id = msg->compid;
        
        xSemaphoreGive(s_mavlink.heartbeat_mutex);
        
        // Durum güncelle
        if (s_mavlink.state != MAVLINK_STATE_PIXHAWK_CONNECTED &&
            s_mavlink.state != MAVLINK_STATE_GCS_CONNECTED) {
            s_mavlink.state = MAVLINK_STATE_PIXHAWK_CONNECTED;
            ESP_LOGI(TAG, "Pixhawk connected - SysID: %d, Type: %d, Autopilot: %d",
                     msg->sysid, hb->type, hb->autopilot);
        }
        
        // Callback
        if (s_mavlink.config.on_heartbeat) {
            s_mavlink.config.on_heartbeat(&s_mavlink.heartbeat,
                                           s_mavlink.config.callback_arg);
        }
    }
}

static void forward_to_gcs(const uint8_t* data, size_t len)
{
    if (s_mavlink.udp_socket < 0) return;
    
    xSemaphoreTake(s_mavlink.clients_mutex, portMAX_DELAY);
    
    for (int i = 0; i < MAVLINK_MAX_GCS_CLIENTS; i++) {
        if (s_mavlink.gcs_clients[i].active) {
            int sent = sendto(s_mavlink.udp_socket, data, len, 0,
                              (struct sockaddr*)&s_mavlink.gcs_clients[i].addr,
                              sizeof(struct sockaddr_in));
            if (sent > 0) {
                s_mavlink.stats.udp_tx_bytes += sent;
                s_mavlink.gcs_clients[i].messages_sent++;
            }
        }
    }
    
    xSemaphoreGive(s_mavlink.clients_mutex);
}

static void forward_to_pixhawk(const uint8_t* data, size_t len)
{
    int written = uart_write_bytes(s_mavlink.config.uart_num, data, len);
    if (written > 0) {
        s_mavlink.stats.uart_tx_bytes += written;
        s_mavlink.stats.mavlink_messages_tx++;
    }
}

// ============================================================================
// Tasks
// ============================================================================

static void uart_rx_task(void* arg)
{
    ESP_LOGI(TAG, "UART RX task started");
    
    uint8_t buffer[MAVLINK_BUFFER_SIZE];
    uint8_t raw_packet[MAVLINK_MAX_PACKET_LEN];
    size_t raw_packet_len = 0;
    mavlink_message_t msg;
    
    while (s_mavlink.tasks_running) {
        // UART'tan oku
        int len = uart_read_bytes(s_mavlink.config.uart_num, buffer, 
                                   sizeof(buffer), pdMS_TO_TICKS(10));
        
        if (len > 0) {
            s_mavlink.stats.uart_rx_bytes += len;
            
            // Her byte'ı parse et
            for (int i = 0; i < len; i++) {
                // Raw paketi oluştur
                if (raw_packet_len < MAVLINK_MAX_PACKET_LEN) {
                    raw_packet[raw_packet_len++] = buffer[i];
                }
                
                mavlink_framing_t result = mavlink_parse_char(&s_mavlink.parser, 
                                                               buffer[i], &msg);
                
                if (result == MAVLINK_FRAMING_OK) {
                    // Mesajı işle
                    process_mavlink_message(&msg, true);
                    
                    // GCS'lere ilet
                    forward_to_gcs(raw_packet, raw_packet_len);
                    raw_packet_len = 0;
                } else if (result == MAVLINK_FRAMING_BAD_CRC) {
                    s_mavlink.stats.parse_errors++;
                    raw_packet_len = 0;
                } else if (s_mavlink.parser.state == MAVLINK_PARSE_STATE_IDLE) {
                    raw_packet_len = 0;
                }
            }
        }
        
        // Periyodik temizlik
        static uint32_t last_cleanup = 0;
        uint32_t now = xTaskGetTickCount();
        if (now - last_cleanup > pdMS_TO_TICKS(5000)) {
            cleanup_stale_gcs_clients();
            last_cleanup = now;
        }
    }
    
    ESP_LOGI(TAG, "UART RX task stopped");
    vTaskDelete(NULL);
}

static void udp_rx_task(void* arg)
{
    ESP_LOGI(TAG, "UDP RX task started");
    
    uint8_t buffer[MAVLINK_BUFFER_SIZE];
    struct sockaddr_in src_addr;
    socklen_t src_len = sizeof(src_addr);
    
    while (s_mavlink.tasks_running) {
        // UDP'den oku
        int len = recvfrom(s_mavlink.udp_socket, buffer, sizeof(buffer), 0,
                           (struct sockaddr*)&src_addr, &src_len);
        
        if (len > 0) {
            s_mavlink.stats.udp_rx_bytes += len;
            
            // GCS istemcisini kaydet/güncelle
            xSemaphoreTake(s_mavlink.clients_mutex, portMAX_DELAY);
            gcs_client_internal_t* client = add_gcs_client(&src_addr);
            if (client) {
                client->messages_received++;
                
                // GCS bağlı durumunu güncelle
                if (s_mavlink.state == MAVLINK_STATE_PIXHAWK_CONNECTED) {
                    s_mavlink.state = MAVLINK_STATE_GCS_CONNECTED;
                }
            }
            xSemaphoreGive(s_mavlink.clients_mutex);
            
            // Pixhawk'a ilet
            forward_to_pixhawk(buffer, len);
        } else if (len < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
            ESP_LOGW(TAG, "UDP recv error: %d", errno);
            vTaskDelay(pdMS_TO_TICKS(100));
        }
    }
    
    ESP_LOGI(TAG, "UDP RX task stopped");
    vTaskDelete(NULL);
}

// ============================================================================
// Public API
// ============================================================================

esp_err_t mavlink_telemetry_init(const mavlink_config_t* config)
{
    if (s_mavlink.initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }
    
    esp_err_t ret;
    
    // Yapılandırma
    if (config) {
        memcpy(&s_mavlink.config, config, sizeof(mavlink_config_t));
    } else {
        s_mavlink.config.uart_num = MAVLINK_UART_NUM;
        s_mavlink.config.uart_tx_pin = MAVLINK_UART_TX_PIN;
        s_mavlink.config.uart_rx_pin = MAVLINK_UART_RX_PIN;
        s_mavlink.config.uart_baud = MAVLINK_UART_BAUD;
        s_mavlink.config.udp_port = MAVLINK_UDP_PORT;
    }
    
    // Mutex'leri oluştur
    s_mavlink.clients_mutex = xSemaphoreCreateMutex();
    s_mavlink.heartbeat_mutex = xSemaphoreCreateMutex();
    if (!s_mavlink.clients_mutex || !s_mavlink.heartbeat_mutex) {
        ESP_LOGE(TAG, "Failed to create mutexes");
        return ESP_ERR_NO_MEM;
    }
    
    // UART yapılandır
    uart_config_t uart_config = {
        .baud_rate = s_mavlink.config.uart_baud,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };
    
    ret = uart_driver_install(s_mavlink.config.uart_num, 
                               MAVLINK_BUFFER_SIZE * 2,
                               MAVLINK_BUFFER_SIZE * 2,
                               20, &s_mavlink.uart_queue, 0);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "uart_driver_install failed: %s", esp_err_to_name(ret));
        return ret;
    }
    
    ret = uart_param_config(s_mavlink.config.uart_num, &uart_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "uart_param_config failed: %s", esp_err_to_name(ret));
        uart_driver_delete(s_mavlink.config.uart_num);
        return ret;
    }
    
    ret = uart_set_pin(s_mavlink.config.uart_num,
                       s_mavlink.config.uart_tx_pin,
                       s_mavlink.config.uart_rx_pin,
                       UART_PIN_NO_CHANGE,
                       UART_PIN_NO_CHANGE);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "uart_set_pin failed: %s", esp_err_to_name(ret));
        uart_driver_delete(s_mavlink.config.uart_num);
        return ret;
    }
    
    // Parser'ı başlat
    mavlink_parser_init(&s_mavlink.parser);
    
    // GCS istemcilerini sıfırla
    memset(s_mavlink.gcs_clients, 0, sizeof(s_mavlink.gcs_clients));
    
    s_mavlink.initialized = true;
    s_mavlink.state = MAVLINK_STATE_STOPPED;
    
    ESP_LOGI(TAG, "MAVLink telemetry initialized");
    ESP_LOGI(TAG, "  UART%d: TX=%d, RX=%d, Baud=%d",
             s_mavlink.config.uart_num,
             s_mavlink.config.uart_tx_pin,
             s_mavlink.config.uart_rx_pin,
             s_mavlink.config.uart_baud);
    ESP_LOGI(TAG, "  UDP Port: %d", s_mavlink.config.udp_port);
    
    return ESP_OK;
}

esp_err_t mavlink_telemetry_deinit(void)
{
    if (!s_mavlink.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    
    mavlink_telemetry_stop();
    
    uart_driver_delete(s_mavlink.config.uart_num);
    
    vSemaphoreDelete(s_mavlink.clients_mutex);
    vSemaphoreDelete(s_mavlink.heartbeat_mutex);
    
    s_mavlink.initialized = false;
    
    ESP_LOGI(TAG, "MAVLink telemetry deinitialized");
    return ESP_OK;
}

esp_err_t mavlink_telemetry_start(void)
{
    if (!s_mavlink.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    
    if (s_mavlink.state != MAVLINK_STATE_STOPPED) {
        return ESP_OK;
    }
    
    // UDP socket oluştur
    s_mavlink.udp_socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s_mavlink.udp_socket < 0) {
        ESP_LOGE(TAG, "Failed to create UDP socket");
        return ESP_FAIL;
    }
    
    // Non-blocking yap
    int flags = fcntl(s_mavlink.udp_socket, F_GETFL, 0);
    fcntl(s_mavlink.udp_socket, F_SETFL, flags | O_NONBLOCK);
    
    // Bind
    struct sockaddr_in bind_addr;
    memset(&bind_addr, 0, sizeof(bind_addr));
    bind_addr.sin_family = AF_INET;
    bind_addr.sin_addr.s_addr = INADDR_ANY;
    bind_addr.sin_port = htons(s_mavlink.config.udp_port);
    
    if (bind(s_mavlink.udp_socket, (struct sockaddr*)&bind_addr, 
             sizeof(bind_addr)) < 0) {
        ESP_LOGE(TAG, "UDP bind failed: %d", errno);
        close(s_mavlink.udp_socket);
        return ESP_FAIL;
    }
    
    // Task'ları başlat
    s_mavlink.tasks_running = true;
    s_mavlink.start_time = esp_timer_get_time() / 1000;
    
    xTaskCreatePinnedToCore(uart_rx_task, "mav_uart", 4096, NULL, 6,
                            &s_mavlink.uart_rx_task, 0);
    xTaskCreatePinnedToCore(udp_rx_task, "mav_udp", 4096, NULL, 5,
                            &s_mavlink.udp_rx_task, 1);
    
    s_mavlink.state = MAVLINK_STATE_RUNNING;
    
    ESP_LOGI(TAG, "MAVLink telemetry started on UDP port %d", 
             s_mavlink.config.udp_port);
    
    return ESP_OK;
}

esp_err_t mavlink_telemetry_stop(void)
{
    if (!s_mavlink.initialized || s_mavlink.state == MAVLINK_STATE_STOPPED) {
        return ESP_ERR_INVALID_STATE;
    }
    
    s_mavlink.tasks_running = false;
    vTaskDelay(pdMS_TO_TICKS(200));
    
    if (s_mavlink.udp_socket >= 0) {
        close(s_mavlink.udp_socket);
        s_mavlink.udp_socket = -1;
    }
    
    s_mavlink.state = MAVLINK_STATE_STOPPED;
    
    ESP_LOGI(TAG, "MAVLink telemetry stopped");
    return ESP_OK;
}

mavlink_state_t mavlink_telemetry_get_state(void)
{
    return s_mavlink.state;
}

esp_err_t mavlink_telemetry_get_stats(mavlink_stats_t* stats)
{
    if (!stats) {
        return ESP_ERR_INVALID_ARG;
    }
    
    memcpy(stats, &s_mavlink.stats, sizeof(mavlink_stats_t));
    
    if (s_mavlink.start_time > 0) {
        stats->uptime_ms = (esp_timer_get_time() / 1000) - s_mavlink.start_time;
    }
    
    return ESP_OK;
}

esp_err_t mavlink_telemetry_get_heartbeat(mavlink_heartbeat_info_t* info)
{
    if (!info) {
        return ESP_ERR_INVALID_ARG;
    }
    
    xSemaphoreTake(s_mavlink.heartbeat_mutex, portMAX_DELAY);
    memcpy(info, &s_mavlink.heartbeat, sizeof(mavlink_heartbeat_info_t));
    xSemaphoreGive(s_mavlink.heartbeat_mutex);
    
    return ESP_OK;
}

uint8_t mavlink_telemetry_get_gcs_clients(mavlink_gcs_client_t* clients, uint8_t max_clients)
{
    if (!clients || max_clients == 0) {
        return 0;
    }
    
    uint8_t count = 0;
    
    xSemaphoreTake(s_mavlink.clients_mutex, portMAX_DELAY);
    
    for (int i = 0; i < MAVLINK_MAX_GCS_CLIENTS && count < max_clients; i++) {
        if (s_mavlink.gcs_clients[i].active) {
            clients[count].ip_addr = s_mavlink.gcs_clients[i].addr.sin_addr.s_addr;
            clients[count].port = ntohs(s_mavlink.gcs_clients[i].addr.sin_port);
            clients[count].last_seen = s_mavlink.gcs_clients[i].last_seen;
            clients[count].messages_sent = s_mavlink.gcs_clients[i].messages_sent;
            clients[count].messages_received = s_mavlink.gcs_clients[i].messages_received;
            count++;
        }
    }
    
    xSemaphoreGive(s_mavlink.clients_mutex);
    
    return count;
}

bool mavlink_telemetry_is_pixhawk_connected(void)
{
    if (!s_mavlink.initialized) return false;
    
    xSemaphoreTake(s_mavlink.heartbeat_mutex, portMAX_DELAY);
    uint64_t last_hb = s_mavlink.heartbeat.last_heartbeat_time;
    xSemaphoreGive(s_mavlink.heartbeat_mutex);
    
    uint64_t now = esp_timer_get_time() / 1000;
    return (last_hb > 0 && (now - last_hb) < 3000); // 3 saniye timeout
}

bool mavlink_telemetry_is_gcs_connected(void)
{
    return s_mavlink.stats.gcs_clients > 0;
}

esp_err_t mavlink_telemetry_send_to_pixhawk(const uint8_t* data, size_t len)
{
    if (!data || len == 0) {
        return ESP_ERR_INVALID_ARG;
    }
    
    forward_to_pixhawk(data, len);
    return ESP_OK;
}

esp_err_t mavlink_telemetry_send_to_gcs(const uint8_t* data, size_t len)
{
    if (!data || len == 0) {
        return ESP_ERR_INVALID_ARG;
    }
    
    forward_to_gcs(data, len);
    return ESP_OK;
}
