/**
 * @file usb_camera.c
 * @brief USB UVC Kamera modülü implementasyonu
 *
 * ESP32-S3 USB Host üzerinden UVC kamera yönetimi.
 * usb_host_uvc v2.3.0 API ile uyumlu.
 */

#include "usb_camera.h"
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "freertos/queue.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "usb/usb_host.h"
#include "usb/uvc_host.h"

static const char *TAG = "USB_CAM";

// Frame buffer sayısı
#define FRAME_BUFFER_COUNT 3

// Modül durumu
static struct
{
    bool initialized;
    usb_cam_state_t state;
    usb_cam_config_t config;
    usb_cam_info_t info;

    // Frame buffers
    usb_cam_frame_t frames[FRAME_BUFFER_COUNT];
    uint8_t current_frame_idx;
    SemaphoreHandle_t frame_mutex;
    QueueHandle_t frame_queue;

    // UVC handles (yeni API)
    uvc_host_stream_hdl_t uvc_stream;

    // İstatistikler
    uint32_t frame_count;
    uint64_t last_frame_time;
    float current_fps;

    // Task handles
    TaskHandle_t usb_host_task;
    TaskHandle_t stream_task;
    bool tasks_running;
} s_usb_cam = {0};

// Forward declarations
static void usb_host_task(void *arg);
static void stream_task(void *arg);
static bool uvc_frame_callback(const uvc_host_frame_t *frame, void *user_ctx);
static void uvc_stream_callback(const uvc_host_stream_event_data_t *event, void *user_ctx);

/**
 * @brief Frame buffer'ları başlat
 */
static esp_err_t init_frame_buffers(void)
{
    size_t buffer_size = s_usb_cam.config.width * s_usb_cam.config.height * 2;

    if (s_usb_cam.config.format == USB_CAM_FORMAT_MJPEG)
    {
        buffer_size = s_usb_cam.config.width * s_usb_cam.config.height / 2;
    }

    for (int i = 0; i < FRAME_BUFFER_COUNT; i++)
    {
        s_usb_cam.frames[i].data = heap_caps_malloc(buffer_size, MALLOC_CAP_SPIRAM);
        if (!s_usb_cam.frames[i].data)
        {
            ESP_LOGE(TAG, "Failed to allocate frame buffer %d", i);
            for (int j = 0; j < i; j++)
            {
                free(s_usb_cam.frames[j].data);
                s_usb_cam.frames[j].data = NULL;
            }
            return ESP_ERR_NO_MEM;
        }

        s_usb_cam.frames[i].capacity = buffer_size;
        s_usb_cam.frames[i].size = 0;
        s_usb_cam.frames[i].width = s_usb_cam.config.width;
        s_usb_cam.frames[i].height = s_usb_cam.config.height;
        s_usb_cam.frames[i].format = s_usb_cam.config.format;
        s_usb_cam.frames[i].sequence = 0;

        ESP_LOGI(TAG, "Frame buffer %d allocated: %zu bytes", i, buffer_size);
    }

    return ESP_OK;
}

/**
 * @brief Frame buffer'ları temizle
 */
static void deinit_frame_buffers(void)
{
    for (int i = 0; i < FRAME_BUFFER_COUNT; i++)
    {
        if (s_usb_cam.frames[i].data)
        {
            free(s_usb_cam.frames[i].data);
            s_usb_cam.frames[i].data = NULL;
        }
    }
}

/**
 * @brief USB Host task
 */
static void usb_host_task(void *arg)
{
    ESP_LOGI(TAG, "USB Host task started");

    while (s_usb_cam.tasks_running)
    {
        uint32_t event_flags;
        esp_err_t ret = usb_host_lib_handle_events(portMAX_DELAY, &event_flags);

        if (ret != ESP_OK)
        {
            ESP_LOGW(TAG, "USB Host event error: %s", esp_err_to_name(ret));
        }

        if (event_flags & USB_HOST_LIB_EVENT_FLAGS_NO_CLIENTS)
        {
            ESP_LOGI(TAG, "No more USB clients");
        }

        if (event_flags & USB_HOST_LIB_EVENT_FLAGS_ALL_FREE)
        {
            ESP_LOGI(TAG, "All USB devices freed");
        }
    }

    ESP_LOGI(TAG, "USB Host task stopped");
    vTaskDelete(NULL);
}

/**
 * @brief Stream yönetim task
 */
static void stream_task(void *arg)
{
    ESP_LOGI(TAG, "Stream task started");

    usb_cam_frame_t *frame;

    while (s_usb_cam.tasks_running)
    {
        if (xQueueReceive(s_usb_cam.frame_queue, &frame, pdMS_TO_TICKS(100)) == pdTRUE)
        {
            if (s_usb_cam.config.frame_callback && frame)
            {
                s_usb_cam.config.frame_callback(frame, s_usb_cam.config.callback_arg);
            }
        }

        if (s_usb_cam.frame_count > 0)
        {
            uint64_t now = esp_timer_get_time();
            if (now - s_usb_cam.last_frame_time > 1000000)
            {
                s_usb_cam.current_fps = (float)s_usb_cam.frame_count * 1000000.0f /
                                        (float)(now - s_usb_cam.last_frame_time);
                s_usb_cam.frame_count = 0;
                s_usb_cam.last_frame_time = now;
            }
        }
    }

    ESP_LOGI(TAG, "Stream task stopped");
    vTaskDelete(NULL);
}

/**
 * @brief UVC stream event callback (yeni API)
 */
static void uvc_stream_callback(const uvc_host_stream_event_data_t *event, void *user_ctx)
{
    switch (event->type)
    {
    case UVC_HOST_DEVICE_DISCONNECTED:
        ESP_LOGI(TAG, "UVC Camera disconnected");
        s_usb_cam.state = USB_CAM_STATE_DISCONNECTED;
        s_usb_cam.uvc_stream = NULL;
        if (s_usb_cam.config.state_callback)
        {
            s_usb_cam.config.state_callback(s_usb_cam.state, s_usb_cam.config.callback_arg);
        }
        break;

    case UVC_HOST_TRANSFER_ERROR:
        ESP_LOGW(TAG, "UVC Transfer error");
        break;

    case UVC_HOST_FRAME_BUFFER_OVERFLOW:
        ESP_LOGW(TAG, "UVC Frame buffer overflow");
        break;

    case UVC_HOST_FRAME_BUFFER_UNDERFLOW:
        ESP_LOGW(TAG, "UVC Frame buffer underflow");
        break;

    default:
        break;
    }
}

/**
 * @brief UVC frame callback (yeni API)
 */
static bool uvc_frame_callback(const uvc_host_frame_t *uvc_frame, void *user_ctx)
{
    if (!uvc_frame || !uvc_frame->data || uvc_frame->data_len == 0)
    {
        return true;
    }

    if (xSemaphoreTake(s_usb_cam.frame_mutex, pdMS_TO_TICKS(10)) != pdTRUE)
    {
        return true;
    }

    usb_cam_frame_t *frame = &s_usb_cam.frames[s_usb_cam.current_frame_idx];

    if (uvc_frame->data_len <= frame->capacity)
    {
        memcpy(frame->data, uvc_frame->data, uvc_frame->data_len);
        frame->size = uvc_frame->data_len;
        frame->timestamp = esp_timer_get_time();
        frame->sequence++;
        frame->width = s_usb_cam.config.width;
        frame->height = s_usb_cam.config.height;
        frame->format = s_usb_cam.config.format;

        usb_cam_frame_t *frame_ptr = frame;
        xQueueSend(s_usb_cam.frame_queue, &frame_ptr, 0);

        s_usb_cam.current_frame_idx = (s_usb_cam.current_frame_idx + 1) % FRAME_BUFFER_COUNT;
        s_usb_cam.frame_count++;
    }
    else
    {
        ESP_LOGW(TAG, "Frame too large: %zu > %zu", uvc_frame->data_len, frame->capacity);
    }

    xSemaphoreGive(s_usb_cam.frame_mutex);
    return true;
}

esp_err_t usb_camera_init(const usb_cam_config_t *config)
{
    if (s_usb_cam.initialized)
    {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    esp_err_t ret;

    if (config)
    {
        memcpy(&s_usb_cam.config, config, sizeof(usb_cam_config_t));
    }
    else
    {
        s_usb_cam.config.width = CAM_FRAME_WIDTH;
        s_usb_cam.config.height = CAM_FRAME_HEIGHT;
        s_usb_cam.config.fps = CAM_FPS;
        s_usb_cam.config.format = USB_CAM_FORMAT_MJPEG;
        s_usb_cam.config.frame_buffer_count = FRAME_BUFFER_COUNT;
    }

    s_usb_cam.frame_mutex = xSemaphoreCreateMutex();
    if (!s_usb_cam.frame_mutex)
    {
        ESP_LOGE(TAG, "Failed to create frame mutex");
        return ESP_ERR_NO_MEM;
    }

    s_usb_cam.frame_queue = xQueueCreate(FRAME_BUFFER_COUNT, sizeof(usb_cam_frame_t *));
    if (!s_usb_cam.frame_queue)
    {
        ESP_LOGE(TAG, "Failed to create frame queue");
        vSemaphoreDelete(s_usb_cam.frame_mutex);
        return ESP_ERR_NO_MEM;
    }

    ret = init_frame_buffers();
    if (ret != ESP_OK)
    {
        vQueueDelete(s_usb_cam.frame_queue);
        vSemaphoreDelete(s_usb_cam.frame_mutex);
        return ret;
    }

    usb_host_config_t host_config = {
        .skip_phy_setup = false,
        .intr_flags = ESP_INTR_FLAG_LEVEL1,
    };

    ret = usb_host_install(&host_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "usb_host_install failed: %s", esp_err_to_name(ret));
        deinit_frame_buffers();
        vQueueDelete(s_usb_cam.frame_queue);
        vSemaphoreDelete(s_usb_cam.frame_mutex);
        return ret;
    }

    uvc_host_driver_config_t uvc_config = {
        .driver_task_stack_size = 4096,
        .driver_task_priority = 5,
        .xCoreID = 0,
        .create_background_task = true,
    };

    ret = uvc_host_install(&uvc_config);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "uvc_host_install failed: %s", esp_err_to_name(ret));
        usb_host_uninstall();
        deinit_frame_buffers();
        vQueueDelete(s_usb_cam.frame_queue);
        vSemaphoreDelete(s_usb_cam.frame_mutex);
        return ret;
    }

    s_usb_cam.tasks_running = true;

    xTaskCreatePinnedToCore(usb_host_task, "usb_host", 4096, NULL, 5,
                            &s_usb_cam.usb_host_task, 0);
    xTaskCreatePinnedToCore(stream_task, "stream", 4096, NULL, 4,
                            &s_usb_cam.stream_task, 1);

    s_usb_cam.initialized = true;
    s_usb_cam.state = USB_CAM_STATE_DISCONNECTED;

    ESP_LOGI(TAG, "USB Camera module initialized");
    ESP_LOGI(TAG, "  Resolution: %lux%lu @ %d fps",
             s_usb_cam.config.width, s_usb_cam.config.height, s_usb_cam.config.fps);

    return ESP_OK;
}

esp_err_t usb_camera_deinit(void)
{
    if (!s_usb_cam.initialized)
    {
        return ESP_ERR_INVALID_STATE;
    }

    usb_camera_stop();
    s_usb_cam.tasks_running = false;
    vTaskDelay(pdMS_TO_TICKS(200));

    uvc_host_uninstall();
    usb_host_uninstall();

    deinit_frame_buffers();
    vQueueDelete(s_usb_cam.frame_queue);
    vSemaphoreDelete(s_usb_cam.frame_mutex);

    s_usb_cam.initialized = false;
    s_usb_cam.state = USB_CAM_STATE_DISCONNECTED;

    ESP_LOGI(TAG, "USB Camera module deinitialized");
    return ESP_OK;
}

esp_err_t usb_camera_start(void)
{
    if (!s_usb_cam.initialized)
    {
        return ESP_ERR_INVALID_STATE;
    }

    if (s_usb_cam.state == USB_CAM_STATE_STREAMING)
    {
        return ESP_OK;
    }

    // Stream yapılandırması (yeni API 2.3.0)
    uvc_host_stream_config_t stream_config = {
        .event_cb = uvc_stream_callback,
        .frame_cb = uvc_frame_callback,
        .user_ctx = NULL,
        .usb = {
            .vid = 0,
            .pid = 0,
            .uvc_stream_index = 0,
        },
        .vs_format = {
            .h_res = s_usb_cam.config.width,
            .v_res = s_usb_cam.config.height,
            .fps = s_usb_cam.config.fps,
            .format = (s_usb_cam.config.format == USB_CAM_FORMAT_MJPEG) ? UVC_VS_FORMAT_MJPEG : UVC_VS_FORMAT_YUY2,
        },
        .advanced = {
            .number_of_frame_buffers = FRAME_BUFFER_COUNT,
            .frame_size = 0,
            .frame_heap_caps = MALLOC_CAP_SPIRAM,
            .number_of_urbs = 3,
            .urb_size = 0,
        },
    };

    esp_err_t ret = uvc_host_stream_open(&stream_config, 5000, &s_usb_cam.uvc_stream);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "uvc_host_stream_open failed: %s", esp_err_to_name(ret));
        return ret;
    }

    s_usb_cam.state = USB_CAM_STATE_CONNECTED;
    ESP_LOGI(TAG, "UVC stream opened");

    ret = uvc_host_stream_start(s_usb_cam.uvc_stream);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "uvc_host_stream_start failed: %s", esp_err_to_name(ret));
        uvc_host_stream_close(s_usb_cam.uvc_stream);
        s_usb_cam.uvc_stream = NULL;
        return ret;
    }

    s_usb_cam.state = USB_CAM_STATE_STREAMING;
    s_usb_cam.last_frame_time = esp_timer_get_time();
    s_usb_cam.frame_count = 0;

    ESP_LOGI(TAG, "Camera streaming started");

    if (s_usb_cam.config.state_callback)
    {
        s_usb_cam.config.state_callback(s_usb_cam.state, s_usb_cam.config.callback_arg);
    }

    return ESP_OK;
}

esp_err_t usb_camera_stop(void)
{
    if (!s_usb_cam.initialized)
    {
        return ESP_ERR_INVALID_STATE;
    }

    if (s_usb_cam.state != USB_CAM_STATE_STREAMING && s_usb_cam.uvc_stream == NULL)
    {
        return ESP_OK;
    }

    if (s_usb_cam.uvc_stream)
    {
        uvc_host_stream_stop(s_usb_cam.uvc_stream);
        uvc_host_stream_close(s_usb_cam.uvc_stream);
        s_usb_cam.uvc_stream = NULL;
    }

    s_usb_cam.state = USB_CAM_STATE_DISCONNECTED;

    ESP_LOGI(TAG, "Camera streaming stopped");

    if (s_usb_cam.config.state_callback)
    {
        s_usb_cam.config.state_callback(s_usb_cam.state, s_usb_cam.config.callback_arg);
    }

    return ESP_OK;
}

usb_cam_state_t usb_camera_get_state(void)
{
    return s_usb_cam.state;
}

esp_err_t usb_camera_get_info(usb_cam_info_t *info)
{
    if (!info)
    {
        return ESP_ERR_INVALID_ARG;
    }
    memcpy(info, &s_usb_cam.info, sizeof(usb_cam_info_t));
    return ESP_OK;
}

esp_err_t usb_camera_get_frame(usb_cam_frame_t *frame, uint32_t timeout_ms)
{
    if (!frame || !s_usb_cam.initialized)
    {
        return ESP_ERR_INVALID_ARG;
    }

    usb_cam_frame_t *src_frame;

    if (xQueueReceive(s_usb_cam.frame_queue, &src_frame, pdMS_TO_TICKS(timeout_ms)) != pdTRUE)
    {
        return ESP_ERR_TIMEOUT;
    }

    if (xSemaphoreTake(s_usb_cam.frame_mutex, pdMS_TO_TICKS(100)) != pdTRUE)
    {
        return ESP_ERR_TIMEOUT;
    }

    if (frame->data && frame->capacity >= src_frame->size)
    {
        memcpy(frame->data, src_frame->data, src_frame->size);
        frame->size = src_frame->size;
    }
    frame->width = src_frame->width;
    frame->height = src_frame->height;
    frame->format = src_frame->format;
    frame->timestamp = src_frame->timestamp;
    frame->sequence = src_frame->sequence;

    xSemaphoreGive(s_usb_cam.frame_mutex);
    return ESP_OK;
}

void usb_camera_release_frame(usb_cam_frame_t *frame)
{
    (void)frame;
}

float usb_camera_get_fps(void)
{
    return s_usb_cam.current_fps;
}

esp_err_t usb_camera_set_param(uint32_t param, int32_t value)
{
    (void)param;
    (void)value;
    return ESP_ERR_NOT_SUPPORTED;
}