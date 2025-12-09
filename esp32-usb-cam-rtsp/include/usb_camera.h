/**
 * @file usb_camera.h
 * @brief USB UVC Kamera modülü
 * 
 * ESP32-S3 USB Host üzerinden UVC kamera yönetimi.
 * USB kameradan frame yakalama ve buffer yönetimi.
 */

#ifndef USB_CAMERA_H
#define USB_CAMERA_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

// Varsayılan kamera ayarları
#ifndef CAM_FRAME_WIDTH
#define CAM_FRAME_WIDTH 640
#endif

#ifndef CAM_FRAME_HEIGHT
#define CAM_FRAME_HEIGHT 480
#endif

#ifndef CAM_FPS
#define CAM_FPS 15
#endif

// Frame formatları
typedef enum {
    USB_CAM_FORMAT_MJPEG = 0,   // Motion JPEG (varsayılan)
    USB_CAM_FORMAT_YUY2,        // YUV 4:2:2
    USB_CAM_FORMAT_NV12,        // YUV 4:2:0
    USB_CAM_FORMAT_H264,        // H.264 (eğer destekleniyorsa)
    USB_CAM_FORMAT_UNKNOWN
} usb_cam_format_t;

// Kamera durumu
typedef enum {
    USB_CAM_STATE_DISCONNECTED = 0,
    USB_CAM_STATE_CONNECTED,
    USB_CAM_STATE_STREAMING,
    USB_CAM_STATE_ERROR
} usb_cam_state_t;

/**
 * @brief Frame buffer yapısı
 */
typedef struct {
    uint8_t* data;          // Frame verisi
    size_t size;            // Veri boyutu (byte)
    size_t capacity;        // Buffer kapasitesi
    uint32_t width;         // Genişlik (piksel)
    uint32_t height;        // Yükseklik (piksel)
    usb_cam_format_t format;// Frame formatı
    uint64_t timestamp;     // Yakalama zamanı (us)
    uint32_t sequence;      // Frame sıra numarası
} usb_cam_frame_t;

/**
 * @brief Kamera bilgisi
 */
typedef struct {
    uint16_t vid;           // Vendor ID
    uint16_t pid;           // Product ID
    char manufacturer[64];  // Üretici
    char product[64];       // Ürün adı
    uint32_t max_width;     // Maksimum genişlik
    uint32_t max_height;    // Maksimum yükseklik
    uint8_t max_fps;        // Maksimum FPS
    usb_cam_format_t supported_formats[8];
    uint8_t format_count;
} usb_cam_info_t;

/**
 * @brief Yeni frame callback tipi
 */
typedef void (*usb_cam_frame_callback_t)(usb_cam_frame_t* frame, void* arg);

/**
 * @brief Durum değişikliği callback tipi
 */
typedef void (*usb_cam_state_callback_t)(usb_cam_state_t state, void* arg);

/**
 * @brief Kamera yapılandırması
 */
typedef struct {
    uint32_t width;
    uint32_t height;
    uint8_t fps;
    usb_cam_format_t format;
    uint8_t frame_buffer_count;  // Kaç frame buffer kullanılacak
    usb_cam_frame_callback_t frame_callback;
    usb_cam_state_callback_t state_callback;
    void* callback_arg;
} usb_cam_config_t;

/**
 * @brief USB kamera modülünü başlat
 * 
 * @param config Kamera yapılandırması
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t usb_camera_init(const usb_cam_config_t* config);

/**
 * @brief USB kamera modülünü kapat
 * 
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t usb_camera_deinit(void);

/**
 * @brief Kamera akışını başlat
 * 
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t usb_camera_start(void);

/**
 * @brief Kamera akışını durdur
 * 
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t usb_camera_stop(void);

/**
 * @brief Mevcut durumu al
 * 
 * @return usb_cam_state_t Kamera durumu
 */
usb_cam_state_t usb_camera_get_state(void);

/**
 * @brief Kamera bilgisini al
 * 
 * @param info Bilgi yapısı (çıktı)
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t usb_camera_get_info(usb_cam_info_t* info);

/**
 * @brief Son frame'i al (kopyalama ile)
 * 
 * @param frame Frame buffer (çıktı)
 * @param timeout_ms Bekleme süresi (ms)
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t usb_camera_get_frame(usb_cam_frame_t* frame, uint32_t timeout_ms);

/**
 * @brief Frame buffer'ı serbest bırak
 * 
 * @param frame Serbest bırakılacak frame
 */
void usb_camera_release_frame(usb_cam_frame_t* frame);

/**
 * @brief Anlık FPS değerini al
 * 
 * @return float Saniyedeki frame sayısı
 */
float usb_camera_get_fps(void);

/**
 * @brief Kamera parametresini ayarla
 * 
 * @param param Parametre ID
 * @param value Değer
 * @return esp_err_t ESP_OK başarılı
 */
esp_err_t usb_camera_set_param(uint32_t param, int32_t value);

#ifdef __cplusplus
}
#endif

#endif // USB_CAMERA_H
