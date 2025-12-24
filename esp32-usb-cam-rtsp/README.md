# ESP32-CAM RTSP Server + MAVLink Bridge

ESP32-CAM modülü için RTSP video streaming ve MAVLink telemetri köprüsü.

## Özellikler

- **RTSP Video Streaming**: VGA 640x480 @ ~10fps
- **MAVLink Bridge**: UART<->UDP telemetri köprüsü (Pixhawk uyumlu)
- **WiFi Access Point**: Bağımsız çalışma modu
- **PSRAM Desteği**: Yüksek çözünürlük için 4MB PSRAM

## Donanım

- ESP32-CAM AI-Thinker modülü
- OV2640 kamera
- 4MB PSRAM (önerilen)

## Pin Bağlantıları

### MAVLink (Pixhawk bağlantısı)
| ESP32-CAM | Pixhawk TELEM |
|-----------|---------------|
| GPIO1 (TX) | RX |
| GPIO3 (RX) | TX |
| GND | GND |

**Not:** GPIO1/GPIO3 USB serial ile paylaşımlıdır. MAVLink kullanırken USB'yi çıkarın.

## Kurulum

### Gereksinimler
- PlatformIO IDE
- ESP32-CAM AI-Thinker modülü

### Derleme ve Yükleme
```bash
# .pio klasörünü temizle (ilk kurulumda)
rm -rf .pio

# Derle ve yükle
pio run -t upload
```

## Kullanım

### Bağlantı Bilgileri
| Servis | Adres |
|--------|-------|
| WiFi SSID | PixhawkDrone |
| WiFi Şifre | 12345678 |
| RTSP URL | rtsp://192.168.4.1:554/stream |
| MAVLink UDP | 192.168.4.1:14550 |

### RTSP Test
```bash
# FFplay ile
ffplay -rtsp_transport tcp rtsp://192.168.4.1:554/stream

# VLC ile
vlc rtsp://192.168.4.1:554/stream
```

### QGroundControl MAVLink Bağlantısı
1. Comm Links -> Add
2. Type: UDP
3. Port: 14550
4. Server: 192.168.4.1

## Proje Yapısı

```
esp32-usb-cam-rtsp/
├── src/
│   ├── main.cpp              # Ana uygulama (Arduino)
│   └── esp-idf-backup/       # ESP-IDF versiyonu (yedek)
│       ├── main.c
│       ├── mavlink_telemetry.c
│       ├── ov2640_camera.c
│       ├── rtsp_server.c
│       └── wifi_ap.c
├── include/                  # Header dosyaları
├── components/               # ESP-IDF bileşenleri (yedek)
│   ├── esp32-camera/
│   └── esp_jpeg/
├── platformio.ini            # PlatformIO yapılandırması (Arduino)
├── platformio.ini.espidf     # ESP-IDF yapılandırması (yedek)
└── README.md
```

## Kütüphaneler

- [Micro-RTSP](https://github.com/geeksville/Micro-RTSP) - RTSP/RTP server
- Arduino ESP32 Camera driver

## Notlar

- PSRAM olmadan QVGA (320x240) çözünürlük kullanılır
- MAVLink bridge GPIO1/GPIO3 pinlerini kullanır (USB serial ile paylaşımlı)
- Flash LED varsayılan olarak kapalıdır (GPIO4)

## Lisans

MIT License
