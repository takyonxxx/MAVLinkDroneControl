/**
 * @file rtsp_server.c
 * @brief MJPEG HTTP Streaming Server with debug
 */

#include "rtsp_server.h"
#include <string.h>
#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "lwip/sockets.h"
#include "lwip/netdb.h"

static const char *TAG = "STREAM";

#define MAX_CLIENTS     4
#define BOUNDARY        "mjpegboundary"
#define FRAME_BUF_SIZE  (60 * 1024)

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
    
    // Frame buffer
    uint8_t *frame_buf;
    size_t frame_size;
    uint32_t frame_width;
    uint32_t frame_height;
} s_server = {0};

// HTTP Response headers
static const char HTTP_STREAM_HEADER[] = 
    "HTTP/1.1 200 OK\r\n"
    "Content-Type: multipart/x-mixed-replace;boundary=" BOUNDARY "\r\n"
    "Cache-Control: no-cache\r\n"
    "Connection: close\r\n"
    "Access-Control-Allow-Origin: *\r\n"
    "\r\n";

static const char HTTP_FRAME_HEADER[] = 
    "--" BOUNDARY "\r\n"
    "Content-Type: image/jpeg\r\n"
    "Content-Length: %u\r\n"
    "\r\n";

// ═══════════════════════════════════════════════════════
// Client streaming task
// ═══════════════════════════════════════════════════════
static void client_stream_task(void *arg)
{
    client_t *client = (client_t *)arg;
    char header_buf[128];
    uint32_t last_seq = 0;
    uint32_t frames_sent = 0;
    int64_t last_log = esp_timer_get_time();
    
    ESP_LOGI(TAG, ">>> Client #%lu stream task started", (unsigned long)client->id);
    
    // Send MJPEG stream header
    int ret = send(client->sock, HTTP_STREAM_HEADER, strlen(HTTP_STREAM_HEADER), 0);
    if (ret < 0) {
        ESP_LOGE(TAG, "Failed to send HTTP header");
        goto cleanup;
    }
    ESP_LOGI(TAG, "HTTP header sent to client #%lu", (unsigned long)client->id);
    
    // Set socket options
    int flag = 1;
    setsockopt(client->sock, IPPROTO_TCP, TCP_NODELAY, &flag, sizeof(flag));
    
    struct timeval tv = { .tv_sec = 2, .tv_usec = 0 };
    setsockopt(client->sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    
    while (client->active && s_server.running) {
        // Check if new frame available
        if (xSemaphoreTake(s_server.frame_mutex, pdMS_TO_TICKS(100)) == pdTRUE) {
            // Check if we have a new frame
            if (s_server.frame_size > 0 && s_server.frame_seq != last_seq) {
                last_seq = s_server.frame_seq;
                size_t frame_size = s_server.frame_size;
                
                // Send frame header
                int hdr_len = snprintf(header_buf, sizeof(header_buf), 
                                       HTTP_FRAME_HEADER, (unsigned)frame_size);
                
                ret = send(client->sock, header_buf, hdr_len, 0);
                if (ret < 0) {
                    xSemaphoreGive(s_server.frame_mutex);
                    ESP_LOGW(TAG, "Send header failed: %d", errno);
                    break;
                }
                
                // Send frame data
                ret = send(client->sock, s_server.frame_buf, frame_size, 0);
                if (ret < 0) {
                    xSemaphoreGive(s_server.frame_mutex);
                    ESP_LOGW(TAG, "Send frame failed: %d", errno);
                    break;
                }
                
                xSemaphoreGive(s_server.frame_mutex);
                
                // Send boundary separator
                ret = send(client->sock, "\r\n", 2, 0);
                if (ret < 0) {
                    ESP_LOGW(TAG, "Send separator failed");
                    break;
                }
                
                frames_sent++;
                
                // Log FPS every 5 seconds
                int64_t now = esp_timer_get_time();
                if (now - last_log >= 5000000) {
                    float fps = (float)frames_sent * 1000000.0f / (float)(now - last_log);
                    ESP_LOGI(TAG, "Client #%lu: %.1f fps, %lu frames", 
                             (unsigned long)client->id, fps, (unsigned long)frames_sent);
                    frames_sent = 0;
                    last_log = now;
                }
            } else {
                xSemaphoreGive(s_server.frame_mutex);
            }
        }
        
        vTaskDelay(pdMS_TO_TICKS(30));  // ~30fps max
    }
    
cleanup:
    close(client->sock);
    client->active = false;
    
    if (s_server.config.client_callback) {
        s_server.config.client_callback(client->id, false, s_server.config.callback_arg);
    }
    
    ESP_LOGI(TAG, "<<< Client #%lu disconnected", (unsigned long)client->id);
    vTaskDelete(NULL);
}

// ═══════════════════════════════════════════════════════
// Accept task
// ═══════════════════════════════════════════════════════
static void accept_task(void *arg)
{
    struct sockaddr_in client_addr;
    socklen_t addr_len = sizeof(client_addr);
    char buf[512];
    
    ESP_LOGI(TAG, "========================================");
    ESP_LOGI(TAG, "MJPEG Stream Server Ready");
    ESP_LOGI(TAG, "http://192.168.4.1:%d/stream", s_server.config.port);
    ESP_LOGI(TAG, "========================================");
    
    while (s_server.running) {
        int client_sock = accept(s_server.server_sock, (struct sockaddr *)&client_addr, &addr_len);
        if (client_sock < 0) {
            if (s_server.running) {
                vTaskDelay(pdMS_TO_TICKS(100));
            }
            continue;
        }
        
        char ip_str[16];
        inet_ntoa_r(client_addr.sin_addr, ip_str, sizeof(ip_str));
        ESP_LOGI(TAG, ">>> New TCP connection from %s", ip_str);
        
        // Read HTTP request
        struct timeval tv = { .tv_sec = 2, .tv_usec = 0 };
        setsockopt(client_sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        
        int len = recv(client_sock, buf, sizeof(buf) - 1, 0);
        if (len <= 0) {
            ESP_LOGW(TAG, "No HTTP request received");
            close(client_sock);
            continue;
        }
        buf[len] = '\0';
        
        // Log first line of request
        char *newline = strchr(buf, '\r');
        if (newline) *newline = '\0';
        ESP_LOGI(TAG, "Request: %s", buf);
        if (newline) *newline = '\r';
        
        // Any GET request starts streaming
        if (strncmp(buf, "GET ", 4) == 0) {
            // Find free client slot
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
                ESP_LOGI(TAG, "Starting stream for client #%lu", (unsigned long)client->id);
                
                if (s_server.config.client_callback) {
                    s_server.config.client_callback(client->id, true, s_server.config.callback_arg);
                }
                
                char task_name[16];
                snprintf(task_name, sizeof(task_name), "strm%lu", (unsigned long)client->id);
                BaseType_t res = xTaskCreate(client_stream_task, task_name, 4096, client, 4, &client->task);
                if (res != pdPASS) {
                    ESP_LOGE(TAG, "Failed to create stream task!");
                    client->active = false;
                    close(client_sock);
                }
            } else {
                ESP_LOGW(TAG, "Max clients reached");
                const char *busy = "HTTP/1.1 503 Busy\r\n\r\n";
                send(client_sock, busy, strlen(busy), 0);
                close(client_sock);
            }
        } else {
            ESP_LOGW(TAG, "Not a GET request, closing");
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
    if (s_server.initialized) {
        return ESP_OK;
    }
    
    ESP_LOGI(TAG, "Initializing stream server...");
    
    if (config) {
        memcpy(&s_server.config, config, sizeof(rtsp_server_config_t));
    } else {
        s_server.config.port = 8080;
        s_server.config.max_clients = MAX_CLIENTS;
    }
    
    // Create semaphores
    s_server.clients_mutex = xSemaphoreCreateMutex();
    s_server.frame_mutex = xSemaphoreCreateMutex();
    
    if (!s_server.clients_mutex || !s_server.frame_mutex) {
        ESP_LOGE(TAG, "Failed to create semaphores");
        return ESP_ERR_NO_MEM;
    }
    
    // Allocate frame buffer
    s_server.frame_buf = heap_caps_malloc(FRAME_BUF_SIZE, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!s_server.frame_buf) {
        s_server.frame_buf = malloc(FRAME_BUF_SIZE);
    }
    if (!s_server.frame_buf) {
        ESP_LOGE(TAG, "Failed to allocate frame buffer");
        return ESP_ERR_NO_MEM;
    }
    ESP_LOGI(TAG, "Frame buffer: %d KB", FRAME_BUF_SIZE / 1024);
    
    // Create server socket
    s_server.server_sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s_server.server_sock < 0) {
        ESP_LOGE(TAG, "Socket create failed");
        return ESP_FAIL;
    }
    
    int opt = 1;
    setsockopt(s_server.server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    struct sockaddr_in bind_addr = {
        .sin_family = AF_INET,
        .sin_port = htons(s_server.config.port),
        .sin_addr.s_addr = htonl(INADDR_ANY),
    };
    
    if (bind(s_server.server_sock, (struct sockaddr *)&bind_addr, sizeof(bind_addr)) < 0) {
        ESP_LOGE(TAG, "Bind failed on port %d", s_server.config.port);
        close(s_server.server_sock);
        return ESP_FAIL;
    }
    
    if (listen(s_server.server_sock, 4) < 0) {
        ESP_LOGE(TAG, "Listen failed");
        close(s_server.server_sock);
        return ESP_FAIL;
    }
    
    s_server.initialized = true;
    ESP_LOGI(TAG, "Server socket ready on port %d", s_server.config.port);
    
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
    BaseType_t res = xTaskCreate(accept_task, "stream_srv", 4096, NULL, 5, &s_server.accept_task);
    if (res != pdPASS) {
        ESP_LOGE(TAG, "Failed to create accept task");
        s_server.running = false;
        return ESP_FAIL;
    }
    
    ESP_LOGI(TAG, "Stream server started");
    return ESP_OK;
}

esp_err_t rtsp_server_stop(void)
{
    s_server.running = false;
    
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
    
    if (xSemaphoreTake(s_server.frame_mutex, pdMS_TO_TICKS(10)) == pdTRUE) {
        size_t copy_size = frame->size;
        if (copy_size > FRAME_BUF_SIZE) {
            copy_size = FRAME_BUF_SIZE;
        }
        
        memcpy(s_server.frame_buf, frame->data, copy_size);
        s_server.frame_size = copy_size;
        s_server.frame_width = frame->width;
        s_server.frame_height = frame->height;
        s_server.frame_seq++;
        
        xSemaphoreGive(s_server.frame_mutex);
    }
    
    return ESP_OK;
}

uint8_t rtsp_server_get_client_count(void)
{
    uint8_t count = 0;
    xSemaphoreTake(s_server.clients_mutex, portMAX_DELAY);
    for (int i = 0; i < MAX_CLIENTS; i++) {
        if (s_server.clients[i].active) {
            count++;
        }
    }
    xSemaphoreGive(s_server.clients_mutex);
    return count;
}
