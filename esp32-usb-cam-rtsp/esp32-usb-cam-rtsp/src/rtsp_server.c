/**
 * @file rtsp_server.c
 * @brief MJPEG HTTP Streaming Server (optimized for ESP32-CAM)
 */

#include "rtsp_server.h"
#include <string.h>
#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#include "lwip/sockets.h"
#include "lwip/netdb.h"

static const char *TAG = "STREAM";

#define MAX_CLIENTS     4
#define BOUNDARY        "frame"
#define FRAME_BUF_SIZE_PSRAM (100 * 1024)  // 100KB with PSRAM
#define FRAME_BUF_SIZE_DRAM  (25 * 1024)   // 25KB without PSRAM

typedef struct {
    int sock;
    bool active;
    uint32_t id;
    TaskHandle_t task;
} client_t;

static struct {
    bool initialized;
    bool running;
    rtsp_server_config_t config;
    int server_sock;
    client_t clients[MAX_CLIENTS];
    SemaphoreHandle_t clients_mutex;
    SemaphoreHandle_t frame_mutex;
    TaskHandle_t accept_task;
    uint32_t client_id_counter;
    uint32_t frame_seq;
    
    uint8_t *frame_buf;
    size_t frame_size;
    size_t frame_buf_capacity;
} s_server = {0};

static const char HTTP_HEADER[] = 
    "HTTP/1.1 200 OK\r\n"
    "Content-Type: multipart/x-mixed-replace;boundary=" BOUNDARY "\r\n"
    "Cache-Control: no-cache, no-store, must-revalidate\r\n"
    "Pragma: no-cache\r\n"
    "Expires: 0\r\n"
    "Connection: close\r\n"
    "Access-Control-Allow-Origin: *\r\n"
    "\r\n";

static const char FRAME_HEADER[] = 
    "--" BOUNDARY "\r\n"
    "Content-Type: image/jpeg\r\n"
    "Content-Length: %u\r\n"
    "\r\n";

// ═══════════════════════════════════════════════════════
// Client Stream Task
// ═══════════════════════════════════════════════════════
static void client_stream_task(void *arg)
{
    client_t *client = (client_t *)arg;
    char header_buf[128];
    uint32_t last_seq = 0;
    uint32_t frames_sent = 0;
    int64_t last_stats = esp_timer_get_time();
    
    ESP_LOGI(TAG, ">>> Client #%lu stream started", (unsigned long)client->id);
    
    // Send HTTP header
    int ret = send(client->sock, HTTP_HEADER, strlen(HTTP_HEADER), 0);
    if (ret < 0) {
        ESP_LOGE(TAG, "Failed to send HTTP header: %d", errno);
        goto cleanup;
    }
    
    // Socket options for low latency
    int flag = 1;
    setsockopt(client->sock, IPPROTO_TCP, TCP_NODELAY, &flag, sizeof(flag));
    
    struct timeval tv = { .tv_sec = 5, .tv_usec = 0 };
    setsockopt(client->sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    
    int sndbuf = 32768;
    setsockopt(client->sock, SOL_SOCKET, SO_SNDBUF, &sndbuf, sizeof(sndbuf));
    
    while (client->active && s_server.running) {
        if (xSemaphoreTake(s_server.frame_mutex, pdMS_TO_TICKS(100)) == pdTRUE) {
            // Check for new frame
            if (s_server.frame_size > 0 && s_server.frame_seq != last_seq) {
                last_seq = s_server.frame_seq;
                size_t frame_size = s_server.frame_size;
                
                // Send frame header
                int hdr_len = snprintf(header_buf, sizeof(header_buf), 
                                       FRAME_HEADER, (unsigned)frame_size);
                
                ret = send(client->sock, header_buf, hdr_len, 0);
                if (ret < 0) {
                    xSemaphoreGive(s_server.frame_mutex);
                    ESP_LOGW(TAG, "Header send failed: %d", errno);
                    break;
                }
                
                // Send frame data
                ret = send(client->sock, s_server.frame_buf, frame_size, 0);
                if (ret < 0) {
                    xSemaphoreGive(s_server.frame_mutex);
                    ESP_LOGW(TAG, "Frame send failed: %d", errno);
                    break;
                }
                
                xSemaphoreGive(s_server.frame_mutex);
                
                // Send boundary terminator
                ret = send(client->sock, "\r\n", 2, 0);
                if (ret < 0) break;
                
                frames_sent++;
                
                // Stats every 5 seconds
                int64_t now = esp_timer_get_time();
                if (now - last_stats >= 5000000) {
                    float fps = (float)frames_sent * 1000000.0f / (float)(now - last_stats);
                    ESP_LOGI(TAG, "Client #%lu: %.1f fps (%lu frames)", 
                             (unsigned long)client->id, fps, (unsigned long)frames_sent);
                    frames_sent = 0;
                    last_stats = now;
                }
            } else {
                xSemaphoreGive(s_server.frame_mutex);
            }
        }
        
        // Small delay to prevent CPU hogging
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    
cleanup:
    ESP_LOGI(TAG, "<<< Client #%lu disconnected", (unsigned long)client->id);
    
    close(client->sock);
    client->active = false;
    
    if (s_server.config.client_callback) {
        s_server.config.client_callback(client->id, false, s_server.config.callback_arg);
    }
    
    vTaskDelete(NULL);
}

// ═══════════════════════════════════════════════════════
// Accept Task
// ═══════════════════════════════════════════════════════
static void accept_task(void *arg)
{
    struct sockaddr_in client_addr;
    socklen_t addr_len = sizeof(client_addr);
    char buf[256];
    
    ESP_LOGI(TAG, "HTTP server listening on port %d", s_server.config.port);
    
    while (s_server.running) {
        int client_sock = accept(s_server.server_sock, 
                                 (struct sockaddr *)&client_addr, &addr_len);
        if (client_sock < 0) {
            if (s_server.running) {
                vTaskDelay(pdMS_TO_TICKS(100));
            }
            continue;
        }
        
        // Get client IP
        char ip_str[16];
        inet_ntoa_r(client_addr.sin_addr, ip_str, sizeof(ip_str));
        ESP_LOGI(TAG, "New connection from %s", ip_str);
        
        // Read HTTP request with timeout
        struct timeval tv = { .tv_sec = 2, .tv_usec = 0 };
        setsockopt(client_sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        
        int len = recv(client_sock, buf, sizeof(buf) - 1, 0);
        if (len <= 0) {
            close(client_sock);
            continue;
        }
        buf[len] = '\0';
        
        // Check for GET request
        if (strncmp(buf, "GET ", 4) != 0) {
            const char *bad = "HTTP/1.1 400 Bad Request\r\n\r\n";
            send(client_sock, bad, strlen(bad), 0);
            close(client_sock);
            continue;
        }
        
        // Find available client slot
        client_t *client = NULL;
        xSemaphoreTake(s_server.clients_mutex, portMAX_DELAY);
        for (int i = 0; i < MAX_CLIENTS; i++) {
            if (!s_server.clients[i].active) {
                client = &s_server.clients[i];
                client->sock = client_sock;
                client->active = true;
                client->id = ++s_server.client_id_counter;
                break;
            }
        }
        xSemaphoreGive(s_server.clients_mutex);
        
        if (client) {
            // Notify callback
            if (s_server.config.client_callback) {
                s_server.config.client_callback(client->id, true, 
                                               s_server.config.callback_arg);
            }
            
            // Create stream task
            char task_name[16];
            snprintf(task_name, sizeof(task_name), "strm%lu", (unsigned long)client->id);
            
            BaseType_t res = xTaskCreatePinnedToCore(
                client_stream_task, task_name, 4096, client, 4, &client->task, 1);
            
            if (res != pdPASS) {
                ESP_LOGE(TAG, "Failed to create stream task");
                client->active = false;
                close(client_sock);
            }
        } else {
            ESP_LOGW(TAG, "Max clients (%d) reached", MAX_CLIENTS);
            const char *busy = "HTTP/1.1 503 Service Unavailable\r\n\r\nServer busy\r\n";
            send(client_sock, busy, strlen(busy), 0);
            close(client_sock);
        }
    }
    
    vTaskDelete(NULL);
}

// ═══════════════════════════════════════════════════════
// Public API
// ═══════════════════════════════════════════════════════

esp_err_t rtsp_server_init(const rtsp_server_config_t *config)
{
    if (s_server.initialized) return ESP_OK;
    
    ESP_LOGI(TAG, "Initializing stream server...");
    
    // Copy config
    if (config) {
        memcpy(&s_server.config, config, sizeof(rtsp_server_config_t));
    } else {
        s_server.config.port = 8080;
        s_server.config.max_clients = MAX_CLIENTS;
    }
    
    // Create synchronization primitives
    s_server.clients_mutex = xSemaphoreCreateMutex();
    s_server.frame_mutex = xSemaphoreCreateMutex();
    
    if (!s_server.clients_mutex || !s_server.frame_mutex) {
        ESP_LOGE(TAG, "Failed to create semaphores");
        return ESP_ERR_NO_MEM;
    }
    
    // Allocate frame buffer (prefer PSRAM)
    size_t psram = heap_caps_get_total_size(MALLOC_CAP_SPIRAM);
    if (psram > 0) {
        s_server.frame_buf_capacity = FRAME_BUF_SIZE_PSRAM;
        s_server.frame_buf = heap_caps_malloc(s_server.frame_buf_capacity, 
                                              MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
        if (s_server.frame_buf) {
            ESP_LOGI(TAG, "Frame buffer: %u KB (PSRAM)", 
                     (unsigned)(s_server.frame_buf_capacity / 1024));
        }
    }
    
    if (!s_server.frame_buf) {
        s_server.frame_buf_capacity = FRAME_BUF_SIZE_DRAM;
        s_server.frame_buf = malloc(s_server.frame_buf_capacity);
        ESP_LOGI(TAG, "Frame buffer: %u KB (DRAM)", 
                 (unsigned)(s_server.frame_buf_capacity / 1024));
    }
    
    if (!s_server.frame_buf) {
        ESP_LOGE(TAG, "Failed to allocate frame buffer");
        return ESP_ERR_NO_MEM;
    }
    
    // Create server socket
    s_server.server_sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s_server.server_sock < 0) {
        ESP_LOGE(TAG, "Socket creation failed: %d", errno);
        return ESP_FAIL;
    }
    
    // Socket options
    int opt = 1;
    setsockopt(s_server.server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    // Bind
    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_port = htons(s_server.config.port),
        .sin_addr.s_addr = htonl(INADDR_ANY),
    };
    
    if (bind(s_server.server_sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        ESP_LOGE(TAG, "Bind failed: %d", errno);
        close(s_server.server_sock);
        return ESP_FAIL;
    }
    
    // Listen
    if (listen(s_server.server_sock, 4) < 0) {
        ESP_LOGE(TAG, "Listen failed: %d", errno);
        close(s_server.server_sock);
        return ESP_FAIL;
    }
    
    s_server.initialized = true;
    ESP_LOGI(TAG, "Server ready on port %d", s_server.config.port);
    
    return ESP_OK;
}

esp_err_t rtsp_server_deinit(void)
{
    rtsp_server_stop();
    
    if (s_server.server_sock >= 0) {
        close(s_server.server_sock);
        s_server.server_sock = -1;
    }
    
    if (s_server.frame_buf) {
        free(s_server.frame_buf);
        s_server.frame_buf = NULL;
    }
    
    if (s_server.clients_mutex) {
        vSemaphoreDelete(s_server.clients_mutex);
        s_server.clients_mutex = NULL;
    }
    
    if (s_server.frame_mutex) {
        vSemaphoreDelete(s_server.frame_mutex);
        s_server.frame_mutex = NULL;
    }
    
    s_server.initialized = false;
    return ESP_OK;
}

esp_err_t rtsp_server_start(void)
{
    if (!s_server.initialized || s_server.running) {
        return ESP_ERR_INVALID_STATE;
    }
    
    s_server.running = true;
    
    BaseType_t res = xTaskCreatePinnedToCore(
        accept_task, "http_srv", 4096, NULL, 5, &s_server.accept_task, 1);
    
    if (res != pdPASS) {
        ESP_LOGE(TAG, "Failed to create accept task");
        s_server.running = false;
        return ESP_FAIL;
    }
    
    ESP_LOGI(TAG, "════════════════════════════════════════");
    ESP_LOGI(TAG, "MJPEG Stream Server Started");
    ESP_LOGI(TAG, "URL: http://192.168.4.1:%d/stream", s_server.config.port);
    ESP_LOGI(TAG, "════════════════════════════════════════");
    
    return ESP_OK;
}

esp_err_t rtsp_server_stop(void)
{
    if (!s_server.running) return ESP_OK;
    
    s_server.running = false;
    
    // Close all client connections
    xSemaphoreTake(s_server.clients_mutex, portMAX_DELAY);
    for (int i = 0; i < MAX_CLIENTS; i++) {
        if (s_server.clients[i].active) {
            close(s_server.clients[i].sock);
            s_server.clients[i].active = false;
        }
    }
    xSemaphoreGive(s_server.clients_mutex);
    
    vTaskDelay(pdMS_TO_TICKS(200));
    return ESP_OK;
}

esp_err_t rtsp_server_send_frame(const rtsp_frame_t *frame)
{
    if (!s_server.initialized || !frame || !frame->data || frame->size == 0) {
        return ESP_ERR_INVALID_ARG;
    }
    
    if (frame->size > s_server.frame_buf_capacity) {
        ESP_LOGW(TAG, "Frame too large: %u > %u", 
                 frame->size, s_server.frame_buf_capacity);
        return ESP_ERR_NO_MEM;
    }
    
    if (xSemaphoreTake(s_server.frame_mutex, pdMS_TO_TICKS(10)) == pdTRUE) {
        memcpy(s_server.frame_buf, frame->data, frame->size);
        s_server.frame_size = frame->size;
        s_server.frame_seq++;
        xSemaphoreGive(s_server.frame_mutex);
        return ESP_OK;
    }
    
    return ESP_ERR_TIMEOUT;
}

uint8_t rtsp_server_get_client_count(void)
{
    uint8_t count = 0;
    
    if (xSemaphoreTake(s_server.clients_mutex, pdMS_TO_TICKS(100)) == pdTRUE) {
        for (int i = 0; i < MAX_CLIENTS; i++) {
            if (s_server.clients[i].active) count++;
        }
        xSemaphoreGive(s_server.clients_mutex);
    }
    
    return count;
}
