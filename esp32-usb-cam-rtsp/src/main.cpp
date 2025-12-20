/**
 * ESP32-CAM RTSP Server + MAVLink Telemetry Bridge
 * Arduino Framework + Micro-RTSP
 * 
 * Features:
 * - RTSP video streaming
 * - MAVLink UART<->UDP bridge for Pixhawk telemetry
 * - WiFi Access Point mode
 * - PSRAM support for high resolution
 * 
 * Connections:
 * - RTSP: rtsp://192.168.4.1:554/stream
 * - MAVLink UDP: 192.168.4.1:14550
 * - WiFi: PixhawkDrone / 12345678
 */

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include "OV2640.h"
#include "OV2640Streamer.h"
#include "CRtspSession.h"

// ============================================
// PIN DEFINITIONS - AI-Thinker ESP32-CAM
// ============================================
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22
#define FLASH_GPIO_NUM     4

// ============================================
// CONFIGURATION
// ============================================
// WiFi Access Point
const char* WIFI_SSID = "PixhawkDrone";
const char* WIFI_PASS = "12345678";

// RTSP Server
#define RTSP_PORT 554

// MAVLink Bridge (UART <-> UDP)
#define MAVLINK_UART_NUM   1
#define MAVLINK_UART_TX    1   // GPIO1 (U0TXD - shared with USB debug!)
#define MAVLINK_UART_RX    3   // GPIO3 (U0RXD - shared with USB debug!)
#define MAVLINK_UART_BAUD  115200
#define MAVLINK_UDP_PORT   14550

// Frame rate control - değiştirilebilir ayarlar
// 33ms = ~30fps, 50ms = ~20fps, 67ms = ~15fps, 100ms = ~10fps
#define FRAME_INTERVAL_MS  100   // ~10 fps

// Çözünürlük seçenekleri:
// FRAMESIZE_VGA    = 640x480   (hızlı, düşük kalite)
// FRAMESIZE_SVGA   = 800x600   (dengeli)
// FRAMESIZE_XGA    = 1024x768  (iyi kalite)
// FRAMESIZE_SXGA   = 1280x1024 (yüksek kalite, yavaş)
// FRAMESIZE_UXGA   = 1600x1200 (en yüksek, çok yavaş)
#define CAMERA_RESOLUTION  FRAMESIZE_XGA

// JPEG kalitesi: 4-63 arası, düşük = daha iyi kalite ama büyük dosya
#define JPEG_QUALITY  16

// ============================================
// GLOBAL OBJECTS
// ============================================
// RTSP
OV2640 cam;
WiFiServer rtspServer(RTSP_PORT);
CStreamer *streamer = nullptr;
CRtspSession *session = nullptr;
WiFiClient rtspClient;

// MAVLink Bridge
WiFiUDP mavlinkUdp;
IPAddress gcsAddress;
uint16_t gcsPort = 0;
bool gcsConnected = false;
uint8_t mavlinkBuffer[512];

// Statistics
uint32_t frameCount = 0;
uint32_t lastStatsTime = 0;

// ============================================
// MAVLINK BRIDGE FUNCTIONS
// ============================================
void mavlinkInit() {
    // Initialize UART1 for MAVLink communication with Pixhawk
    // Note: GPIO1/GPIO3 are shared with USB serial, disconnect USB when using MAVLink
    Serial1.begin(MAVLINK_UART_BAUD, SERIAL_8N1, MAVLINK_UART_RX, MAVLINK_UART_TX);
    
    // Initialize UDP socket for GCS communication
    mavlinkUdp.begin(MAVLINK_UDP_PORT);
    
    Serial.printf("[MAVLink] UART1 @ %d baud (TX:%d, RX:%d)\n", 
                  MAVLINK_UART_BAUD, MAVLINK_UART_TX, MAVLINK_UART_RX);
    Serial.printf("[MAVLink] UDP port %d\n", MAVLINK_UDP_PORT);
}

void mavlinkLoop() {
    // ===== UART -> UDP (Pixhawk to GCS) =====
    int available = Serial1.available();
    if (available > 0 && gcsConnected) {
        int len = Serial1.readBytes(mavlinkBuffer, min(available, (int)sizeof(mavlinkBuffer)));
        if (len > 0) {
            mavlinkUdp.beginPacket(gcsAddress, gcsPort);
            mavlinkUdp.write(mavlinkBuffer, len);
            mavlinkUdp.endPacket();
        }
    }
    
    // ===== UDP -> UART (GCS to Pixhawk) =====
    int packetSize = mavlinkUdp.parsePacket();
    if (packetSize > 0) {
        // Store GCS address on first packet or address change
        IPAddress remoteIP = mavlinkUdp.remoteIP();
        uint16_t remotePort = mavlinkUdp.remotePort();
        
        if (!gcsConnected || gcsAddress != remoteIP || gcsPort != remotePort) {
            gcsAddress = remoteIP;
            gcsPort = remotePort;
            gcsConnected = true;
            Serial.printf("[MAVLink] GCS connected: %s:%d\n", 
                         gcsAddress.toString().c_str(), gcsPort);
        }
        
        // Forward to Pixhawk via UART
        int len = mavlinkUdp.read(mavlinkBuffer, sizeof(mavlinkBuffer));
        if (len > 0) {
            Serial1.write(mavlinkBuffer, len);
        }
    }
}

// ============================================
// CAMERA SETUP
// ============================================
void setupCamera() {
    Serial.println("[Camera] Initializing...");
    
    // Use AI-Thinker ESP32-CAM configuration from Micro-RTSP
    esp32cam_aithinker_config.frame_size = CAMERA_RESOLUTION;
    esp32cam_aithinker_config.jpeg_quality = JPEG_QUALITY;
    
    cam.init(esp32cam_aithinker_config);
    
    // Turn off flash LED
    pinMode(FLASH_GPIO_NUM, OUTPUT);
    digitalWrite(FLASH_GPIO_NUM, LOW);
    
    // Resolution names for logging
    const char* resName;
    switch(CAMERA_RESOLUTION) {
        case FRAMESIZE_VGA:  resName = "VGA 640x480"; break;
        case FRAMESIZE_SVGA: resName = "SVGA 800x600"; break;
        case FRAMESIZE_XGA:  resName = "XGA 1024x768"; break;
        case FRAMESIZE_SXGA: resName = "SXGA 1280x1024"; break;
        case FRAMESIZE_UXGA: resName = "UXGA 1600x1200"; break;
        default: resName = "Unknown"; break;
    }
    
    Serial.printf("[Camera] Resolution: %s, Quality: %d\n", resName, JPEG_QUALITY);
}

// ============================================
// WIFI SETUP
// ============================================
void setupWiFi() {
    Serial.println("[WiFi] Starting Access Point...");
    
    WiFi.mode(WIFI_AP);
    WiFi.softAP(WIFI_SSID, WIFI_PASS);
    
    // Wait for AP to start
    delay(100);
    
    Serial.printf("[WiFi] SSID: %s\n", WIFI_SSID);
    Serial.printf("[WiFi] Password: %s\n", WIFI_PASS);
    Serial.printf("[WiFi] IP: %s\n", WiFi.softAPIP().toString().c_str());
}

// ============================================
// RTSP HANDLING
// ============================================
void handleRTSP() {
    static uint32_t lastFrame = 0;
    
    if (session) {
        // Handle RTSP requests (DESCRIBE, SETUP, PLAY, etc.)
        session->handleRequests(0);
        
        // Send frames at specified interval
        uint32_t now = millis();
        if (now >= lastFrame + FRAME_INTERVAL_MS || now < lastFrame) {
            session->broadcastCurrentFrame(now);
            lastFrame = now;
            frameCount++;
        }
        
        // Check if client disconnected
        if (session->m_stopped) {
            Serial.println("[RTSP] Client disconnected");
            delete session;
            delete streamer;
            session = nullptr;
            streamer = nullptr;
        }
    } else {
        // Accept new RTSP client connection
        rtspClient = rtspServer.accept();
        if (rtspClient) {
            Serial.printf("[RTSP] Client connected from %s\n", 
                         rtspClient.remoteIP().toString().c_str());
            streamer = new OV2640Streamer(&rtspClient, cam);
            session = new CRtspSession(&rtspClient, streamer);
        }
    }
}

// ============================================
// STATISTICS
// ============================================
void printStats() {
    uint32_t now = millis();
    if (now - lastStatsTime >= 10000) {  // Every 10 seconds
        float fps = frameCount * 1000.0f / (now - lastStatsTime);
        Serial.printf("[Stats] FPS: %.1f, Heap: %d KB, Clients: %d, GCS: %s\n",
                     fps,
                     ESP.getFreeHeap() / 1024,
                     session ? 1 : 0,
                     gcsConnected ? "Yes" : "No");
        frameCount = 0;
        lastStatsTime = now;
    }
}

// ============================================
// SETUP
// ============================================
void setup() {
    // Initialize debug serial (USB)
    Serial.begin(115200);
    Serial.setDebugOutput(true);
    delay(1000);
    
    // Print banner
    Serial.println();
    Serial.println("================================================");
    Serial.println("   ESP32-CAM RTSP Server + MAVLink Bridge");
    Serial.println("================================================");
    
    // Memory information
    if (psramFound()) {
        Serial.printf("[Memory] PSRAM: %d KB\n", ESP.getPsramSize() / 1024);
    } else {
        Serial.println("[Memory] WARNING: No PSRAM detected!");
    }
    Serial.printf("[Memory] Free Heap: %d KB\n", ESP.getFreeHeap() / 1024);
    
    // Initialize subsystems
    setupCamera();
    setupWiFi();
    mavlinkInit();
    
    // Start RTSP server
    rtspServer.begin();
    Serial.printf("[RTSP] Server started on port %d\n", RTSP_PORT);
    
    // Print connection info
    Serial.println();
    Serial.println("================================================");
    Serial.println("                CONNECTION INFO");
    Serial.println("================================================");
    Serial.printf("  WiFi:    %s / %s\n", WIFI_SSID, WIFI_PASS);
    Serial.printf("  RTSP:    rtsp://%s:%d/mjpeg/1\n", 
                  WiFi.softAPIP().toString().c_str(), RTSP_PORT);
    Serial.printf("  MAVLink: UDP %s:%d\n", 
                  WiFi.softAPIP().toString().c_str(), MAVLINK_UDP_PORT);
    Serial.println("================================================");
    Serial.println();
    
    lastStatsTime = millis();
}

// ============================================
// MAIN LOOP
// ============================================
void loop() {
    // Handle RTSP streaming
    handleRTSP();
    
    // Handle MAVLink bridge
    mavlinkLoop();
    
    // Print statistics periodically
    printStats();
    
    // Small delay to prevent watchdog issues
    delay(1);
}