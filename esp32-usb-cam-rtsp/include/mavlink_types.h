/**
 * @file mavlink_types.h
 * @brief MAVLink protokol temel tanımlamaları
 * 
 * Minimal MAVLink v2 tanımlamaları.
 * Tam kütüphane için: https://github.com/mavlink/c_library_v2
 */

#ifndef MAVLINK_TYPES_H
#define MAVLINK_TYPES_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// MAVLink sürüm
#define MAVLINK_STX_V1          0xFE    // MAVLink v1 start byte
#define MAVLINK_STX_V2          0xFD    // MAVLink v2 start byte

// Mesaj ID'leri
#define MAVLINK_MSG_ID_HEARTBEAT            0
#define MAVLINK_MSG_ID_SYS_STATUS           1
#define MAVLINK_MSG_ID_PING                 4
#define MAVLINK_MSG_ID_GPS_RAW_INT          24
#define MAVLINK_MSG_ID_ATTITUDE             30
#define MAVLINK_MSG_ID_GLOBAL_POSITION_INT  33
#define MAVLINK_MSG_ID_RC_CHANNELS          65
#define MAVLINK_MSG_ID_VFR_HUD              74
#define MAVLINK_MSG_ID_COMMAND_LONG         76
#define MAVLINK_MSG_ID_COMMAND_ACK          77
#define MAVLINK_MSG_ID_BATTERY_STATUS       147
#define MAVLINK_MSG_ID_STATUSTEXT           253

// MAV_TYPE
#define MAV_TYPE_GENERIC            0
#define MAV_TYPE_FIXED_WING         1
#define MAV_TYPE_QUADROTOR          2
#define MAV_TYPE_HEXAROTOR          13
#define MAV_TYPE_OCTOROTOR          14
#define MAV_TYPE_SUBMARINE          12
#define MAV_TYPE_SURFACE_BOAT       11
#define MAV_TYPE_GROUND_ROVER       10
#define MAV_TYPE_GCS                6

// MAV_AUTOPILOT
#define MAV_AUTOPILOT_GENERIC       0
#define MAV_AUTOPILOT_ARDUPILOTMEGA 3
#define MAV_AUTOPILOT_PX4           12

// MAV_STATE
#define MAV_STATE_UNINIT            0
#define MAV_STATE_BOOT              1
#define MAV_STATE_CALIBRATING       2
#define MAV_STATE_STANDBY           3
#define MAV_STATE_ACTIVE            4
#define MAV_STATE_CRITICAL          5
#define MAV_STATE_EMERGENCY         6
#define MAV_STATE_POWEROFF          7

// MAV_MODE_FLAG
#define MAV_MODE_FLAG_SAFETY_ARMED          128
#define MAV_MODE_FLAG_MANUAL_INPUT_ENABLED  64
#define MAV_MODE_FLAG_HIL_ENABLED           32
#define MAV_MODE_FLAG_STABILIZE_ENABLED     16
#define MAV_MODE_FLAG_GUIDED_ENABLED        8
#define MAV_MODE_FLAG_AUTO_ENABLED          4
#define MAV_MODE_FLAG_TEST_ENABLED          2
#define MAV_MODE_FLAG_CUSTOM_MODE_ENABLED   1

// Maksimum payload boyutu
#define MAVLINK_MAX_PAYLOAD_LEN     255
#define MAVLINK_NUM_CHECKSUM_BYTES  2
#define MAVLINK_SIGNATURE_BLOCK_LEN 13

// MAVLink v1 header
typedef struct __attribute__((packed)) {
    uint8_t magic;              // Start byte (0xFE)
    uint8_t len;                // Payload length
    uint8_t seq;                // Sequence number
    uint8_t sysid;              // System ID
    uint8_t compid;             // Component ID
    uint8_t msgid;              // Message ID
} mavlink_v1_header_t;

// MAVLink v2 header
typedef struct __attribute__((packed)) {
    uint8_t magic;              // Start byte (0xFD)
    uint8_t len;                // Payload length
    uint8_t incompat_flags;     // Incompatibility flags
    uint8_t compat_flags;       // Compatibility flags
    uint8_t seq;                // Sequence number
    uint8_t sysid;              // System ID
    uint8_t compid;             // Component ID
    uint8_t msgid_low;          // Message ID low byte
    uint8_t msgid_mid;          // Message ID mid byte
    uint8_t msgid_high;         // Message ID high byte
} mavlink_v2_header_t;

// Heartbeat mesajı payload
typedef struct __attribute__((packed)) {
    uint32_t custom_mode;       // Custom mode
    uint8_t type;               // MAV_TYPE
    uint8_t autopilot;          // MAV_AUTOPILOT
    uint8_t base_mode;          // MAV_MODE_FLAG
    uint8_t system_status;      // MAV_STATE
    uint8_t mavlink_version;    // MAVLink version
} mavlink_heartbeat_t;

// Parser durumu
typedef enum {
    MAVLINK_PARSE_STATE_IDLE = 0,
    MAVLINK_PARSE_STATE_GOT_STX,
    MAVLINK_PARSE_STATE_GOT_LENGTH,
    MAVLINK_PARSE_STATE_GOT_INCOMPAT_FLAGS,
    MAVLINK_PARSE_STATE_GOT_COMPAT_FLAGS,
    MAVLINK_PARSE_STATE_GOT_SEQ,
    MAVLINK_PARSE_STATE_GOT_SYSID,
    MAVLINK_PARSE_STATE_GOT_COMPID,
    MAVLINK_PARSE_STATE_GOT_MSGID1,
    MAVLINK_PARSE_STATE_GOT_MSGID2,
    MAVLINK_PARSE_STATE_GOT_MSGID3,
    MAVLINK_PARSE_STATE_GOT_PAYLOAD,
    MAVLINK_PARSE_STATE_GOT_CRC1,
    MAVLINK_PARSE_STATE_GOT_BAD_CRC,
    MAVLINK_PARSE_STATE_COMPLETE
} mavlink_parse_state_t;

// Parser sonucu
typedef enum {
    MAVLINK_FRAMING_OK = 0,
    MAVLINK_FRAMING_INCOMPLETE,
    MAVLINK_FRAMING_BAD_CRC,
    MAVLINK_FRAMING_BAD_SIGNATURE
} mavlink_framing_t;

// Parse edilmiş mesaj
typedef struct {
    uint8_t magic;              // Start byte
    uint8_t len;                // Payload length
    uint8_t incompat_flags;     // V2 only
    uint8_t compat_flags;       // V2 only
    uint8_t seq;                // Sequence number
    uint8_t sysid;              // System ID
    uint8_t compid;             // Component ID
    uint32_t msgid;             // Message ID (24-bit for v2)
    uint8_t payload[MAVLINK_MAX_PAYLOAD_LEN];
    uint16_t checksum;
    uint8_t signature[MAVLINK_SIGNATURE_BLOCK_LEN];
} mavlink_message_t;

// Parser context
typedef struct {
    mavlink_parse_state_t state;
    uint8_t packet_idx;
    mavlink_message_t msg;
    uint16_t checksum;
} mavlink_parser_t;

/**
 * @brief CRC hesaplama fonksiyonları
 */
void mavlink_crc_init(uint16_t* crc);
void mavlink_crc_accumulate(uint8_t byte, uint16_t* crc);
uint16_t mavlink_crc_calculate(const uint8_t* buffer, uint16_t length);

/**
 * @brief Parser'ı sıfırla
 */
void mavlink_parser_init(mavlink_parser_t* parser);

/**
 * @brief Byte parse et
 * 
 * @param parser Parser context
 * @param byte Gelen byte
 * @param msg Tamamlanan mesaj (çıktı)
 * @return mavlink_framing_t Parse sonucu
 */
mavlink_framing_t mavlink_parse_char(mavlink_parser_t* parser, uint8_t byte, mavlink_message_t* msg);

/**
 * @brief Mesaj ID'sinin CRC_EXTRA değerini al
 */
uint8_t mavlink_get_crc_extra(uint32_t msgid);

#ifdef __cplusplus
}
#endif

#endif // MAVLINK_TYPES_H
