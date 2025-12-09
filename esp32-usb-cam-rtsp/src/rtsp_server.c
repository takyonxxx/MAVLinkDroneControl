/**
 * @file rtsp_server.c
 * @brief Basit RTSP Server implementasyonu
 * 
 * MJPEG stream için RTSP/RTP server.
 * RFC 2326 (RTSP) ve RFC 3550 (RTP) standartlarına uygun.
 */

#include "rtsp_server.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "lwip/sockets.h"
#include "lwip/netdb.h"
#include "wifi_ap.h"

static const char* TAG = "RTSP_SRV";

// RTSP komutları
#define RTSP_CMD_OPTIONS    "OPTIONS"
#define RTSP_CMD_DESCRIBE   "DESCRIBE"
#define RTSP_CMD_SETUP      "SETUP"
#define RTSP_CMD_PLAY       "PLAY"
#define RTSP_CMD_TEARDOWN   "TEARDOWN"
#define RTSP_CMD_PAUSE      "PAUSE"

// RTP header boyutu
#define RTP_HEADER_SIZE     12
#define RTP_PAYLOAD_TYPE    26  // MJPEG

// Maksimum RTP paket boyutu (MTU - IP - UDP headers)
#define RTP_MAX_PACKET_SIZE 1400

// RTSP istemci yapısı
typedef struct {
    bool active;
    int rtsp_socket;
    int rtp_socket;
    int rtcp_socket;
    struct sockaddr_in rtp_addr;
    uint16_t rtp_port;
    uint16_t rtcp_port;
    rtsp_client_state_t state;
    uint32_t session_id;
    uint32_t cseq;
    uint64_t connected_time;
    uint32_t frames_sent;
    uint64_t bytes_sent;
    uint16_t rtp_sequence;
    uint32_t rtp_timestamp;
    uint32_t ssrc;
} rtsp_client_t;

// Server durumu
static struct {
    bool initialized;
    rtsp_server_state_t state;
    rtsp_server_config_t config;
    
    // Server socket
    int server_socket;
    
    // İstemciler
    rtsp_client_t clients[RTSP_MAX_CLIENTS];
    SemaphoreHandle_t clients_mutex;
    
    // İstatistikler
    rtsp_server_stats_t stats;
    uint64_t start_time;
    
    // Task handle
    TaskHandle_t server_task;
    bool task_running;
} s_rtsp = {0};

// Forward declarations
static void rtsp_server_task(void* arg);
static void handle_rtsp_request(rtsp_client_t* client, const char* request);
static void send_rtsp_response(rtsp_client_t* client, int status, const char* status_msg,
                                const char* headers, const char* body);
static esp_err_t send_rtp_frame(rtsp_client_t* client, const usb_cam_frame_t* frame);

/**
 * @brief Session ID oluştur
 */
static uint32_t generate_session_id(void)
{
    return (uint32_t)(esp_timer_get_time() & 0xFFFFFFFF);
}

/**
 * @brief SSRC oluştur
 */
static uint32_t generate_ssrc(void)
{
    return (uint32_t)((esp_timer_get_time() >> 16) ^ esp_random());
}

/**
 * @brief Boş istemci slot'u bul
 */
static rtsp_client_t* find_free_client_slot(void)
{
    for (int i = 0; i < RTSP_MAX_CLIENTS; i++) {
        if (!s_rtsp.clients[i].active) {
            return &s_rtsp.clients[i];
        }
    }
    return NULL;
}

/**
 * @brief İstemciyi temizle
 */
static void cleanup_client(rtsp_client_t* client)
{
    if (!client || !client->active) return;
    
    if (client->rtsp_socket >= 0) {
        close(client->rtsp_socket);
        client->rtsp_socket = -1;
    }
    
    if (client->rtp_socket >= 0) {
        close(client->rtp_socket);
        client->rtp_socket = -1;
    }
    
    if (client->rtcp_socket >= 0) {
        close(client->rtcp_socket);
        client->rtcp_socket = -1;
    }
    
    client->active = false;
    client->state = RTSP_CLIENT_STATE_INIT;
    
    if (s_rtsp.stats.active_clients > 0) {
        s_rtsp.stats.active_clients--;
    }
    
    ESP_LOGI(TAG, "Client cleaned up");
}

/**
 * @brief SDP içeriği oluştur
 */
static int create_sdp_content(char* buffer, size_t buffer_size)
{
    const char* ip = wifi_ap_get_ip();
    
    return snprintf(buffer, buffer_size,
        "v=0\r\n"
        "o=- %lu %lu IN IP4 %s\r\n"
        "s=ESP32 Camera Stream\r\n"
        "i=USB Camera RTSP Stream\r\n"
        "c=IN IP4 %s\r\n"
        "t=0 0\r\n"
        "a=tool:ESP32-RTSP-Server\r\n"
        "a=type:broadcast\r\n"
        "a=control:*\r\n"
        "m=video 0 RTP/AVP %d\r\n"
        "a=rtpmap:%d JPEG/90000\r\n"
        "a=control:track1\r\n",
        (unsigned long)esp_timer_get_time(),
        (unsigned long)esp_timer_get_time(),
        ip, ip,
        RTP_PAYLOAD_TYPE,
        RTP_PAYLOAD_TYPE
    );
}

/**
 * @brief OPTIONS isteğini işle
 */
static void handle_options(rtsp_client_t* client)
{
    send_rtsp_response(client, 200, "OK",
        "Public: OPTIONS, DESCRIBE, SETUP, PLAY, TEARDOWN\r\n",
        NULL);
}

/**
 * @brief DESCRIBE isteğini işle
 */
static void handle_describe(rtsp_client_t* client)
{
    char sdp[512];
    int sdp_len = create_sdp_content(sdp, sizeof(sdp));
    
    char headers[256];
    snprintf(headers, sizeof(headers),
        "Content-Type: application/sdp\r\n"
        "Content-Length: %d\r\n",
        sdp_len);
    
    send_rtsp_response(client, 200, "OK", headers, sdp);
}

/**
 * @brief SETUP isteğini işle
 */
static void handle_setup(rtsp_client_t* client, const char* request)
{
    // Transport header'ını parse et
    const char* transport = strstr(request, "Transport:");
    if (!transport) {
        send_rtsp_response(client, 400, "Bad Request", NULL, NULL);
        return;
    }
    
    // Client port'larını bul
    const char* client_port = strstr(transport, "client_port=");
    if (!client_port) {
        send_rtsp_response(client, 400, "Bad Request", NULL, NULL);
        return;
    }
    
    int rtp_port, rtcp_port;
    if (sscanf(client_port, "client_port=%d-%d", &rtp_port, &rtcp_port) < 1) {
        send_rtsp_response(client, 400, "Bad Request", NULL, NULL);
        return;
    }
    
    if (rtcp_port == 0) {
        rtcp_port = rtp_port + 1;
    }
    
    client->rtp_port = rtp_port;
    client->rtcp_port = rtcp_port;
    
    // Session ID oluştur
    if (client->session_id == 0) {
        client->session_id = generate_session_id();
    }
    
    // RTP socket oluştur
    client->rtp_socket = socket(AF_INET, SOCK_DGRAM, 0);
    if (client->rtp_socket < 0) {
        ESP_LOGE(TAG, "Failed to create RTP socket");
        send_rtsp_response(client, 500, "Internal Server Error", NULL, NULL);
        return;
    }
    
    // İstemci RTP adresini kaydet
    memset(&client->rtp_addr, 0, sizeof(client->rtp_addr));
    client->rtp_addr.sin_family = AF_INET;
    client->rtp_addr.sin_port = htons(client->rtp_port);
    
    // İstemci IP'sini al
    struct sockaddr_in peer_addr;
    socklen_t peer_len = sizeof(peer_addr);
    getpeername(client->rtsp_socket, (struct sockaddr*)&peer_addr, &peer_len);
    client->rtp_addr.sin_addr = peer_addr.sin_addr;
    
    // SSRC oluştur
    client->ssrc = generate_ssrc();
    client->rtp_sequence = 0;
    client->rtp_timestamp = 0;
    
    // Response gönder
    char headers[256];
    snprintf(headers, sizeof(headers),
        "Transport: RTP/AVP;unicast;client_port=%d-%d;server_port=%d-%d\r\n"
        "Session: %lu;timeout=60\r\n",
        rtp_port, rtcp_port,
        RTP_DEFAULT_VIDEO_PORT, RTCP_DEFAULT_VIDEO_PORT,
        (unsigned long)client->session_id);
    
    send_rtsp_response(client, 200, "OK", headers, NULL);
    
    client->state = RTSP_CLIENT_STATE_READY;
    
    ESP_LOGI(TAG, "Client setup complete - RTP port: %d", rtp_port);
}

/**
 * @brief PLAY isteğini işle
 */
static void handle_play(rtsp_client_t* client)
{
    if (client->state != RTSP_CLIENT_STATE_READY) {
        send_rtsp_response(client, 455, "Method Not Valid in This State", NULL, NULL);
        return;
    }
    
    char headers[128];
    snprintf(headers, sizeof(headers),
        "Session: %lu\r\n"
        "Range: npt=0.000-\r\n",
        (unsigned long)client->session_id);
    
    send_rtsp_response(client, 200, "OK", headers, NULL);
    
    client->state = RTSP_CLIENT_STATE_PLAYING;
    
    ESP_LOGI(TAG, "Client playing");
}

/**
 * @brief TEARDOWN isteğini işle
 */
static void handle_teardown(rtsp_client_t* client)
{
    char headers[64];
    snprintf(headers, sizeof(headers),
        "Session: %lu\r\n",
        (unsigned long)client->session_id);
    
    send_rtsp_response(client, 200, "OK", headers, NULL);
    
    client->state = RTSP_CLIENT_STATE_TEARDOWN;
    
    ESP_LOGI(TAG, "Client teardown");
}

/**
 * @brief RTSP isteğini işle
 */
static void handle_rtsp_request(rtsp_client_t* client, const char* request)
{
    // CSeq'i parse et
    const char* cseq_str = strstr(request, "CSeq:");
    if (cseq_str) {
        sscanf(cseq_str, "CSeq: %lu", (unsigned long*)&client->cseq);
    }
    
    // Komutu belirle
    if (strncmp(request, RTSP_CMD_OPTIONS, strlen(RTSP_CMD_OPTIONS)) == 0) {
        handle_options(client);
    }
    else if (strncmp(request, RTSP_CMD_DESCRIBE, strlen(RTSP_CMD_DESCRIBE)) == 0) {
        handle_describe(client);
    }
    else if (strncmp(request, RTSP_CMD_SETUP, strlen(RTSP_CMD_SETUP)) == 0) {
        handle_setup(client, request);
    }
    else if (strncmp(request, RTSP_CMD_PLAY, strlen(RTSP_CMD_PLAY)) == 0) {
        handle_play(client);
    }
    else if (strncmp(request, RTSP_CMD_TEARDOWN, strlen(RTSP_CMD_TEARDOWN)) == 0) {
        handle_teardown(client);
    }
    else {
        send_rtsp_response(client, 501, "Not Implemented", NULL, NULL);
    }
}

/**
 * @brief RTSP response gönder
 */
static void send_rtsp_response(rtsp_client_t* client, int status, const char* status_msg,
                                const char* headers, const char* body)
{
    char response[1024];
    int len = snprintf(response, sizeof(response),
        "RTSP/1.0 %d %s\r\n"
        "CSeq: %lu\r\n"
        "%s"
        "\r\n"
        "%s",
        status, status_msg,
        (unsigned long)client->cseq,
        headers ? headers : "",
        body ? body : "");
    
    send(client->rtsp_socket, response, len, 0);
}

/**
 * @brief RTP header oluştur
 */
static void create_rtp_header(uint8_t* header, uint16_t seq, uint32_t timestamp,
                               uint32_t ssrc, bool marker)
{
    header[0] = 0x80;  // Version 2, no padding, no extension, no CSRC
    header[1] = RTP_PAYLOAD_TYPE | (marker ? 0x80 : 0x00);
    header[2] = (seq >> 8) & 0xFF;
    header[3] = seq & 0xFF;
    header[4] = (timestamp >> 24) & 0xFF;
    header[5] = (timestamp >> 16) & 0xFF;
    header[6] = (timestamp >> 8) & 0xFF;
    header[7] = timestamp & 0xFF;
    header[8] = (ssrc >> 24) & 0xFF;
    header[9] = (ssrc >> 16) & 0xFF;
    header[10] = (ssrc >> 8) & 0xFF;
    header[11] = ssrc & 0xFF;
}

/**
 * @brief JPEG RTP header oluştur (RFC 2435)
 */
static void create_jpeg_header(uint8_t* header, uint32_t offset, uint8_t type,
                                uint8_t q, uint16_t width, uint16_t height)
{
    header[0] = 0;  // Type-specific
    header[1] = (offset >> 16) & 0xFF;
    header[2] = (offset >> 8) & 0xFF;
    header[3] = offset & 0xFF;
    header[4] = type;
    header[5] = q;
    header[6] = width / 8;
    header[7] = height / 8;
}

/**
 * @brief RTP üzerinden frame gönder
 */
static esp_err_t send_rtp_frame(rtsp_client_t* client, const usb_cam_frame_t* frame)
{
    if (!client || !frame || client->state != RTSP_CLIENT_STATE_PLAYING) {
        return ESP_ERR_INVALID_STATE;
    }
    
    if (client->rtp_socket < 0) {
        return ESP_ERR_INVALID_STATE;
    }
    
    const uint8_t* data = frame->data;
    size_t remaining = frame->size;
    uint32_t offset = 0;
    
    // JPEG header boyutu
    const int jpeg_header_size = 8;
    const int max_payload = RTP_MAX_PACKET_SIZE - RTP_HEADER_SIZE - jpeg_header_size;
    
    uint8_t packet[RTP_MAX_PACKET_SIZE];
    
    while (remaining > 0) {
        size_t payload_size = (remaining > max_payload) ? max_payload : remaining;
        bool marker = (remaining <= max_payload);  // Son paket
        
        // RTP header
        create_rtp_header(packet, client->rtp_sequence++, 
                          client->rtp_timestamp, client->ssrc, marker);
        
        // JPEG header
        create_jpeg_header(packet + RTP_HEADER_SIZE, offset, 
                           1,    // Type 1 = YUV 4:2:2
                           80,   // Q = 80 (kalite)
                           frame->width, frame->height);
        
        // Payload
        memcpy(packet + RTP_HEADER_SIZE + jpeg_header_size, data + offset, payload_size);
        
        // Gönder
        int packet_size = RTP_HEADER_SIZE + jpeg_header_size + payload_size;
        int sent = sendto(client->rtp_socket, packet, packet_size, 0,
                          (struct sockaddr*)&client->rtp_addr, sizeof(client->rtp_addr));
        
        if (sent < 0) {
            ESP_LOGW(TAG, "RTP send failed: %d", errno);
            return ESP_FAIL;
        }
        
        client->bytes_sent += sent;
        offset += payload_size;
        remaining -= payload_size;
    }
    
    // Timestamp güncelle (90kHz clock)
    client->rtp_timestamp += 90000 / CAM_FPS;
    client->frames_sent++;
    
    return ESP_OK;
}

/**
 * @brief RTSP server task
 */
static void rtsp_server_task(void* arg)
{
    ESP_LOGI(TAG, "RTSP Server task started");
    
    char buffer[1024];
    fd_set read_fds;
    struct timeval tv;
    
    while (s_rtsp.task_running) {
        FD_ZERO(&read_fds);
        FD_SET(s_rtsp.server_socket, &read_fds);
        
        int max_fd = s_rtsp.server_socket;
        
        // Aktif istemcileri ekle
        for (int i = 0; i < RTSP_MAX_CLIENTS; i++) {
            if (s_rtsp.clients[i].active && s_rtsp.clients[i].rtsp_socket >= 0) {
                FD_SET(s_rtsp.clients[i].rtsp_socket, &read_fds);
                if (s_rtsp.clients[i].rtsp_socket > max_fd) {
                    max_fd = s_rtsp.clients[i].rtsp_socket;
                }
            }
        }
        
        tv.tv_sec = 0;
        tv.tv_usec = 100000;  // 100ms timeout
        
        int ret = select(max_fd + 1, &read_fds, NULL, NULL, &tv);
        
        if (ret < 0) {
            ESP_LOGE(TAG, "select error: %d", errno);
            continue;
        }
        
        if (ret == 0) {
            continue;  // Timeout
        }
        
        // Yeni bağlantı kontrolü
        if (FD_ISSET(s_rtsp.server_socket, &read_fds)) {
            struct sockaddr_in client_addr;
            socklen_t addr_len = sizeof(client_addr);
            
            int client_socket = accept(s_rtsp.server_socket,
                                       (struct sockaddr*)&client_addr, &addr_len);
            
            if (client_socket >= 0) {
                xSemaphoreTake(s_rtsp.clients_mutex, portMAX_DELAY);
                
                rtsp_client_t* client = find_free_client_slot();
                if (client) {
                    memset(client, 0, sizeof(rtsp_client_t));
                    client->active = true;
                    client->rtsp_socket = client_socket;
                    client->rtp_socket = -1;
                    client->rtcp_socket = -1;
                    client->state = RTSP_CLIENT_STATE_INIT;
                    client->connected_time = esp_timer_get_time();
                    
                    s_rtsp.stats.total_clients++;
                    s_rtsp.stats.active_clients++;
                    
                    ESP_LOGI(TAG, "New client connected from %s",
                             inet_ntoa(client_addr.sin_addr));
                    
                    if (s_rtsp.config.client_callback) {
                        s_rtsp.config.client_callback(
                            (uint32_t)(client - s_rtsp.clients),
                            true, s_rtsp.config.callback_arg);
                    }
                } else {
                    ESP_LOGW(TAG, "No free client slot, rejecting connection");
                    close(client_socket);
                }
                
                xSemaphoreGive(s_rtsp.clients_mutex);
            }
        }
        
        // İstemci isteklerini kontrol et
        for (int i = 0; i < RTSP_MAX_CLIENTS; i++) {
            rtsp_client_t* client = &s_rtsp.clients[i];
            
            if (!client->active || client->rtsp_socket < 0) {
                continue;
            }
            
            if (FD_ISSET(client->rtsp_socket, &read_fds)) {
                int len = recv(client->rtsp_socket, buffer, sizeof(buffer) - 1, 0);
                
                if (len <= 0) {
                    // Bağlantı kapandı
                    ESP_LOGI(TAG, "Client %d disconnected", i);
                    
                    if (s_rtsp.config.client_callback) {
                        s_rtsp.config.client_callback(i, false, s_rtsp.config.callback_arg);
                    }
                    
                    xSemaphoreTake(s_rtsp.clients_mutex, portMAX_DELAY);
                    cleanup_client(client);
                    xSemaphoreGive(s_rtsp.clients_mutex);
                } else {
                    buffer[len] = '\0';
                    handle_rtsp_request(client, buffer);
                    
                    // Teardown sonrası temizle
                    if (client->state == RTSP_CLIENT_STATE_TEARDOWN) {
                        xSemaphoreTake(s_rtsp.clients_mutex, portMAX_DELAY);
                        cleanup_client(client);
                        xSemaphoreGive(s_rtsp.clients_mutex);
                    }
                }
            }
        }
    }
    
    ESP_LOGI(TAG, "RTSP Server task stopped");
    vTaskDelete(NULL);
}

esp_err_t rtsp_server_init(const rtsp_server_config_t* config)
{
    if (s_rtsp.initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }
    
    // Yapılandırma
    if (config) {
        memcpy(&s_rtsp.config, config, sizeof(rtsp_server_config_t));
    } else {
        s_rtsp.config.port = RTSP_PORT;
        s_rtsp.config.stream_name = RTSP_STREAM_NAME;
        s_rtsp.config.max_clients = RTSP_MAX_CLIENTS;
    }
    
    // Mutex oluştur
    s_rtsp.clients_mutex = xSemaphoreCreateMutex();
    if (!s_rtsp.clients_mutex) {
        ESP_LOGE(TAG, "Failed to create clients mutex");
        return ESP_ERR_NO_MEM;
    }
    
    // İstemcileri sıfırla
    memset(s_rtsp.clients, 0, sizeof(s_rtsp.clients));
    for (int i = 0; i < RTSP_MAX_CLIENTS; i++) {
        s_rtsp.clients[i].rtsp_socket = -1;
        s_rtsp.clients[i].rtp_socket = -1;
        s_rtsp.clients[i].rtcp_socket = -1;
    }
    
    s_rtsp.initialized = true;
    s_rtsp.state = RTSP_SERVER_STATE_STOPPED;
    
    ESP_LOGI(TAG, "RTSP Server initialized");
    ESP_LOGI(TAG, "  Port: %d", s_rtsp.config.port);
    ESP_LOGI(TAG, "  Stream: %s", s_rtsp.config.stream_name);
    
    return ESP_OK;
}

esp_err_t rtsp_server_deinit(void)
{
    if (!s_rtsp.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    
    rtsp_server_stop();
    
    vSemaphoreDelete(s_rtsp.clients_mutex);
    
    s_rtsp.initialized = false;
    
    ESP_LOGI(TAG, "RTSP Server deinitialized");
    return ESP_OK;
}

esp_err_t rtsp_server_start(void)
{
    if (!s_rtsp.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    
    if (s_rtsp.state == RTSP_SERVER_STATE_RUNNING) {
        return ESP_OK;
    }
    
    // Server socket oluştur
    s_rtsp.server_socket = socket(AF_INET, SOCK_STREAM, 0);
    if (s_rtsp.server_socket < 0) {
        ESP_LOGE(TAG, "Failed to create server socket");
        return ESP_FAIL;
    }
    
    // Socket seçenekleri
    int opt = 1;
    setsockopt(s_rtsp.server_socket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    // Bind
    struct sockaddr_in server_addr;
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(s_rtsp.config.port);
    
    if (bind(s_rtsp.server_socket, (struct sockaddr*)&server_addr, 
             sizeof(server_addr)) < 0) {
        ESP_LOGE(TAG, "Bind failed: %d", errno);
        close(s_rtsp.server_socket);
        return ESP_FAIL;
    }
    
    // Listen
    if (listen(s_rtsp.server_socket, 4) < 0) {
        ESP_LOGE(TAG, "Listen failed: %d", errno);
        close(s_rtsp.server_socket);
        return ESP_FAIL;
    }
    
    // Task başlat
    s_rtsp.task_running = true;
    s_rtsp.start_time = esp_timer_get_time();
    
    xTaskCreatePinnedToCore(rtsp_server_task, "rtsp_srv", 8192, NULL, 4,
                            &s_rtsp.server_task, 1);
    
    s_rtsp.state = RTSP_SERVER_STATE_RUNNING;
    
    char url[64];
    rtsp_server_get_url(url, sizeof(url));
    ESP_LOGI(TAG, "RTSP Server started: %s", url);
    
    return ESP_OK;
}

esp_err_t rtsp_server_stop(void)
{
    if (!s_rtsp.initialized || s_rtsp.state != RTSP_SERVER_STATE_RUNNING) {
        return ESP_ERR_INVALID_STATE;
    }
    
    // Task'ı durdur
    s_rtsp.task_running = false;
    vTaskDelay(pdMS_TO_TICKS(200));
    
    // Tüm istemcileri temizle
    xSemaphoreTake(s_rtsp.clients_mutex, portMAX_DELAY);
    for (int i = 0; i < RTSP_MAX_CLIENTS; i++) {
        cleanup_client(&s_rtsp.clients[i]);
    }
    xSemaphoreGive(s_rtsp.clients_mutex);
    
    // Server socket'i kapat
    if (s_rtsp.server_socket >= 0) {
        close(s_rtsp.server_socket);
        s_rtsp.server_socket = -1;
    }
    
    s_rtsp.state = RTSP_SERVER_STATE_STOPPED;
    
    ESP_LOGI(TAG, "RTSP Server stopped");
    return ESP_OK;
}

rtsp_server_state_t rtsp_server_get_state(void)
{
    return s_rtsp.state;
}

esp_err_t rtsp_server_send_frame(const usb_cam_frame_t* frame)
{
    if (!s_rtsp.initialized || !frame) {
        return ESP_ERR_INVALID_ARG;
    }
    
    if (s_rtsp.state != RTSP_SERVER_STATE_RUNNING) {
        return ESP_ERR_INVALID_STATE;
    }
    
    xSemaphoreTake(s_rtsp.clients_mutex, portMAX_DELAY);
    
    for (int i = 0; i < RTSP_MAX_CLIENTS; i++) {
        rtsp_client_t* client = &s_rtsp.clients[i];
        
        if (client->active && client->state == RTSP_CLIENT_STATE_PLAYING) {
            esp_err_t ret = send_rtp_frame(client, frame);
            if (ret == ESP_OK) {
                s_rtsp.stats.total_frames_sent++;
                s_rtsp.stats.total_bytes_sent += frame->size;
            }
        }
    }
    
    xSemaphoreGive(s_rtsp.clients_mutex);
    
    return ESP_OK;
}

uint8_t rtsp_server_get_clients(rtsp_client_info_t* clients, uint8_t max_clients)
{
    if (!clients || max_clients == 0) {
        return 0;
    }
    
    uint8_t count = 0;
    
    xSemaphoreTake(s_rtsp.clients_mutex, portMAX_DELAY);
    
    for (int i = 0; i < RTSP_MAX_CLIENTS && count < max_clients; i++) {
        if (s_rtsp.clients[i].active) {
            clients[count].client_id = i;
            clients[count].rtp_port = s_rtsp.clients[i].rtp_port;
            clients[count].state = s_rtsp.clients[i].state;
            clients[count].connected_time = s_rtsp.clients[i].connected_time;
            clients[count].frames_sent = s_rtsp.clients[i].frames_sent;
            clients[count].bytes_sent = s_rtsp.clients[i].bytes_sent;
            
            // IP adresini al
            struct sockaddr_in peer_addr;
            socklen_t peer_len = sizeof(peer_addr);
            if (getpeername(s_rtsp.clients[i].rtsp_socket, 
                           (struct sockaddr*)&peer_addr, &peer_len) == 0) {
                strncpy(clients[count].ip_addr, inet_ntoa(peer_addr.sin_addr), 15);
            }
            
            count++;
        }
    }
    
    xSemaphoreGive(s_rtsp.clients_mutex);
    
    return count;
}

esp_err_t rtsp_server_get_stats(rtsp_server_stats_t* stats)
{
    if (!stats) {
        return ESP_ERR_INVALID_ARG;
    }
    
    memcpy(stats, &s_rtsp.stats, sizeof(rtsp_server_stats_t));
    
    if (s_rtsp.start_time > 0) {
        stats->uptime_seconds = (esp_timer_get_time() - s_rtsp.start_time) / 1000000;
    }
    
    return ESP_OK;
}

esp_err_t rtsp_server_get_url(char* url_buffer, size_t buffer_size)
{
    if (!url_buffer || buffer_size == 0) {
        return ESP_ERR_INVALID_ARG;
    }
    
    snprintf(url_buffer, buffer_size, "rtsp://%s:%d%s",
             wifi_ap_get_ip(), s_rtsp.config.port, s_rtsp.config.stream_name);
    
    return ESP_OK;
}

esp_err_t rtsp_server_disconnect_client(uint32_t client_id)
{
    if (client_id >= RTSP_MAX_CLIENTS) {
        return ESP_ERR_INVALID_ARG;
    }
    
    xSemaphoreTake(s_rtsp.clients_mutex, portMAX_DELAY);
    cleanup_client(&s_rtsp.clients[client_id]);
    xSemaphoreGive(s_rtsp.clients_mutex);
    
    return ESP_OK;
}
