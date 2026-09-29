// MavlinkManager.cpp - DroneControlQt

#include "MavlinkManager.h"
#include "DefaultParameters.h"

#include <QDebug>
#include <QSet>
#include <cmath>
#include <cstring>

namespace {

struct ModeInfo {
    uint mode;
    const char *name;
    const char *icon;     // short glyph used by the UI
    const char *color;    // hex, mirrors the SwiftUI system colors
    const char *description;
};

// ArduCopter custom modes (port of CopterFlightMode)
const ModeInfo kModes[] = {
    {0,  "Stabilize",   "=",  "#34C759", "Manual with leveling"},
    {1,  "Acro",        "~",  "#FF9500", "Full manual"},
    {2,  "Alt Hold",    "|",  "#007AFF", "Hold altitude"},
    {3,  "Auto",        "@",  "#AF52DE", "Follow waypoints"},
    {4,  "Guided",      "o",  "#32ADE6", "Computer control"},
    {5,  "Loiter",      "O",  "#5856D6", "GPS hold"},
    {6,  "RTL",         "H",  "#FF3B30", "Return home"},
    {7,  "Circle",      "C",  "#5AC8FA", "Circle point"},
    {9,  "Land",        "v",  "#A2845E", "Auto landing"},
    {11, "Drift",       "w",  "#00C7BE", ""},
    {13, "Sport",       "s",  "#FFCC00", ""},
    {14, "Flip",        "f",  "#FF2D55", ""},
    {15, "Autotune",    "T",  "#FF9500", ""},
    {16, "Pos Hold",    "P",  "#34C759", "Hold position"},
    {17, "Brake",       "!",  "#FF3B30", "Emergency brake"},
    {18, "Throw",       "^",  "#FF9500", ""},
    {19, "Avoid ADSB",  "A",  "#FFCC00", ""},
    {20, "Guided NoGPS","g",  "#8E8E93", ""},
    {21, "Smart RTL",   "h",  "#AF52DE", "Smart return"},
    {22, "Flow Hold",   "F",  "#32ADE6", ""},
    {23, "Follow",      "u",  "#007AFF", ""},
    {24, "ZigZag",      "Z",  "#5856D6", ""},
    {25, "System ID",   "#",  "#8E8E93", ""},
    {26, "Autorotate",  "R",  "#FF9500", ""},
    {27, "Auto RTL",    "K",  "#FF3B30", ""},
};

const ModeInfo *findMode(uint mode)
{
    for (const ModeInfo &m : kModes)
        if (m.mode == mode)
            return &m;
    return nullptr;
}

QString messageIdToName(quint32 id)
{
    switch (id) {
    case MAVLINK_MSG_ID_HEARTBEAT: return QStringLiteral("HEARTBEAT");
    case MAVLINK_MSG_ID_SYS_STATUS: return QStringLiteral("SYS_STATUS");
    case MAVLINK_MSG_ID_GLOBAL_POSITION_INT: return QStringLiteral("GLOBAL_POSITION_INT");
    case MAVLINK_MSG_ID_GPS_RAW_INT: return QStringLiteral("GPS_RAW_INT");
    case MAVLINK_MSG_ID_ATTITUDE: return QStringLiteral("ATTITUDE");
    case MAVLINK_MSG_ID_SERVO_OUTPUT_RAW: return QStringLiteral("SERVO_OUTPUT_RAW");
    case MAVLINK_MSG_ID_VFR_HUD: return QStringLiteral("VFR_HUD");
    case MAVLINK_MSG_ID_SCALED_PRESSURE: return QStringLiteral("SCALED_PRESSURE");
    case MAVLINK_MSG_ID_COMMAND_ACK: return QStringLiteral("COMMAND_ACK");
    case MAVLINK_MSG_ID_STATUSTEXT: return QStringLiteral("STATUSTEXT");
    case MAVLINK_MSG_ID_PARAM_VALUE: return QStringLiteral("PARAM_VALUE");
    default: return QStringLiteral("ID_%1").arg(id);
    }
}

QString magCalStatusName(quint8 s)
{
    switch (s) {
    case 0: return QStringLiteral("NOT STARTED");
    case 1: return QStringLiteral("WAITING TO START");
    case 2: return QStringLiteral("RUNNING (step 1)");
    case 3: return QStringLiteral("RUNNING (step 2)");
    case 4: return QStringLiteral("SUCCESS");
    case 5: return QStringLiteral("FAILED");
    case 6: return QStringLiteral("BAD ORIENTATION");
    case 7: return QStringLiteral("BAD RADIUS");
    default: return QStringLiteral("UNKNOWN (%1)").arg(s);
    }
}

QString fixName(quint8 fixType)
{
    switch (fixType) {
    case 0: return QStringLiteral("NO GPS");
    case 1: return QStringLiteral("NO FIX");
    case 2: return QStringLiteral("2D FIX");
    case 3: return QStringLiteral("3D FIX");
    case 4: return QStringLiteral("DGPS");
    case 5: return QStringLiteral("RTK FLOAT");
    case 6: return QStringLiteral("RTK FIXED");
    case 7: return QStringLiteral("STATIC");
    case 8: return QStringLiteral("PPP");
    default: return QStringLiteral("UNKNOWN (%1)").arg(fixType);
    }
}

// Copy a fixed-size, possibly non-terminated char array into a QString
template <size_t N>
QString fixedString(const char (&arr)[N])
{
    size_t len = 0;
    while (len < N && arr[len] != '\0')
        ++len;
    return QString::fromUtf8(arr, int(len));
}

template <size_t N>
void fillFixedString(char (&arr)[N], const QString &s)
{
    std::memset(arr, 0, N);
    const QByteArray bytes = s.toUtf8().left(int(N));
    std::memcpy(arr, bytes.constData(), size_t(bytes.size()));
}

} // namespace

MavlinkManager::MavlinkManager(QObject *parent)
    : QObject(parent)
{
    // MAVLink channel setup: emit MAVLink v1 like the iOS app does
    mavlink_reset_channel_status(MAVLINK_COMM_0);
    if (mavlink_status_t *st = mavlink_get_channel_status(MAVLINK_COMM_0))
        st->flags |= MAVLINK_STATUS_FLAG_OUT_MAVLINK1;
    qDebug() << "[MAVLINK] Protocol initialized on channel 0";

    for (int i = 0; i < 16; ++i)
        m_servoValues.append(0);

    m_gyroCalState = calState(QStringLiteral("idle"), QString());
    m_baroCalState = calState(QStringLiteral("idle"), QString());

    connect(&m_udp, &UdpConnection::dataReceived, this, &MavlinkManager::parseData);
    connect(&m_udp, &UdpConnection::connectedChanged, this, [this](bool c) {
        if (m_connected == c)
            return;
        m_connected = c;
        emit connectedChanged();
    });

    m_heartbeatTimer.setInterval(500);
    connect(&m_heartbeatTimer, &QTimer::timeout, this, &MavlinkManager::sendHeartbeat);

    m_watchdogTimer.setInterval(1000);
    connect(&m_watchdogTimer, &QTimer::timeout, this, [this]() {
        const bool alive = m_heartbeatEver && m_lastHeartbeat.elapsed() < 5000;
        if (alive != m_heartbeatAlive) {
            m_heartbeatAlive = alive;
            if (!alive)
                qWarning() << "[MAVLINK] Connection timeout - no heartbeat for 5 s";
            emit heartbeatAliveChanged();
        }
    });

    m_restoreTimer.setInterval(25);   // ~40 msg/s so the ESP bridge is not flooded
    connect(&m_restoreTimer, &QTimer::timeout, this, [this]() {
        const auto &items = DefaultParameters::values();
        if (m_restoreIndex >= items.size()) {
            m_restoreTimer.stop();
            m_restoreInProgress = false;
            emit restoreChanged();
            return;
        }
        const auto &item = items.at(m_restoreIndex++);
        setParameter(item.first, item.second);
        m_restoreProgress = m_restoreIndex;
        emit restoreChanged();
    });

    m_motorTestClearTimer.setSingleShot(true);
    m_motorTestClearTimer.setInterval(2000);
    connect(&m_motorTestClearTimer, &QTimer::timeout, this, [this]() {
        m_motorTestActive = false;
        emit motorTestChanged();
        emit armedChanged();
    });
}

MavlinkManager::~MavlinkManager()
{
    disconnectVehicle();
}

// ---------------------------------------------------------------------------
// Link

void MavlinkManager::setEndpoint(const QString &host, int port, int localPort)
{
    m_udp.setEndpoint(host, quint16(port), quint16(localPort));
}

void MavlinkManager::connectVehicle()
{
    m_udp.connectSocket();
    m_heartbeatTimer.start();
    m_watchdogTimer.start();
    qDebug() << "[MAVLINK] Heartbeat timer started (500 ms)";
    QTimer::singleShot(1000, this, &MavlinkManager::requestTelemetryMessages);
}

void MavlinkManager::disconnectVehicle()
{
    m_heartbeatTimer.stop();
    m_watchdogTimer.stop();
    m_udp.disconnectSocket();
    if (m_heartbeatAlive) {
        m_heartbeatAlive = false;
        emit heartbeatAliveChanged();
    }
}

void MavlinkManager::requestTelemetryMessages()
{
    qDebug() << "[MAVLINK] Requesting telemetry messages";
    // Message ID -> interval in microseconds
    static const struct { quint32 id; qint32 us; } messages[] = {
        {MAVLINK_MSG_ID_SYS_STATUS, 500000},           // 2 Hz
        {MAVLINK_MSG_ID_GPS_RAW_INT, 200000},          // 5 Hz
        {MAVLINK_MSG_ID_ATTITUDE, 100000},             // 10 Hz
        {MAVLINK_MSG_ID_GLOBAL_POSITION_INT, 200000},  // 5 Hz
        {MAVLINK_MSG_ID_SERVO_OUTPUT_RAW, 100000},     // 10 Hz
        {MAVLINK_MSG_ID_VFR_HUD, 200000},              // 5 Hz
        {MAVLINK_MSG_ID_SCALED_PRESSURE, 500000},      // 2 Hz
        {MAVLINK_MSG_ID_SCALED_IMU, 100000},           // 10 Hz (IMU dead-reckoning speed)
        {MAVLINK_MSG_ID_EKF_STATUS_REPORT, 500000},    // 2 Hz
    };
    for (const auto &m : messages)
        setMessageInterval(m.id, m.us);
}

void MavlinkManager::setMessageInterval(quint32 messageId, qint32 intervalUs)
{
    sendCommandLong(MAV_CMD_SET_MESSAGE_INTERVAL, float(messageId), float(intervalUs));
}

void MavlinkManager::sendHeartbeat()
{
    mavlink_message_t msg;
    mavlink_msg_heartbeat_pack(m_systemId, m_componentId, &msg,
                               MAV_TYPE_GCS, MAV_AUTOPILOT_INVALID, 0, 0, 0);
    sendMessage(msg);
}

void MavlinkManager::sendMessage(const mavlink_message_t &msg)
{
    quint8 buffer[MAVLINK_MAX_PACKET_LEN];
    const uint16_t len = mavlink_msg_to_send_buffer(buffer, &msg);
    m_udp.send(QByteArray(reinterpret_cast<const char *>(buffer), len));
}

void MavlinkManager::sendCommandLong(quint16 command, float p1, float p2, float p3, float p4,
                                     float p5, float p6, float p7)
{
    mavlink_message_t msg;
    mavlink_command_long_t cmd{};
    cmd.target_system = m_targetSystemId;
    cmd.target_component = m_targetComponentId;
    cmd.command = command;
    cmd.confirmation = 0;
    cmd.param1 = p1; cmd.param2 = p2; cmd.param3 = p3; cmd.param4 = p4;
    cmd.param5 = p5; cmd.param6 = p6; cmd.param7 = p7;
    mavlink_msg_command_long_encode(m_systemId, m_componentId, &msg, &cmd);
    sendMessage(msg);
}

// ---------------------------------------------------------------------------
// Parsing

void MavlinkManager::parseData(const QByteArray &data)
{
    for (char c : data) {
        if (mavlink_parse_char(MAVLINK_COMM_0, quint8(c), &m_message, &m_status) != 0)
            processMessage(m_message);
    }
}

void MavlinkManager::processMessage(const mavlink_message_t &msg)
{
    if (!m_seenMessageIds.contains(msg.msgid)) {
        m_seenMessageIds.insert(msg.msgid);
        qDebug() << "[MAVLINK] New message type:" << msg.msgid << messageIdToName(msg.msgid);
    }

    switch (msg.msgid) {
    case MAVLINK_MSG_ID_HEARTBEAT: {
        mavlink_heartbeat_t m; mavlink_msg_heartbeat_decode(&msg, &m); handleHeartbeat(m); break; }
    case MAVLINK_MSG_ID_SYS_STATUS: {
        mavlink_sys_status_t m; mavlink_msg_sys_status_decode(&msg, &m); handleSysStatus(m); break; }
    case MAVLINK_MSG_ID_GLOBAL_POSITION_INT: {
        mavlink_global_position_int_t m; mavlink_msg_global_position_int_decode(&msg, &m); handleGlobalPositionInt(m); break; }
    case MAVLINK_MSG_ID_GPS_RAW_INT: {
        mavlink_gps_raw_int_t m; mavlink_msg_gps_raw_int_decode(&msg, &m); handleGpsRawInt(m); break; }
    case MAVLINK_MSG_ID_ATTITUDE: {
        mavlink_attitude_t m; mavlink_msg_attitude_decode(&msg, &m); handleAttitude(m); break; }
    case MAVLINK_MSG_ID_SERVO_OUTPUT_RAW: {
        mavlink_servo_output_raw_t m; mavlink_msg_servo_output_raw_decode(&msg, &m); handleServoOutputRaw(m); break; }
    case MAVLINK_MSG_ID_VFR_HUD: {
        mavlink_vfr_hud_t m; mavlink_msg_vfr_hud_decode(&msg, &m); handleVfrHud(m); break; }
    case MAVLINK_MSG_ID_SCALED_PRESSURE: {
        mavlink_scaled_pressure_t m; mavlink_msg_scaled_pressure_decode(&msg, &m); handleScaledPressure(m); break; }
    case MAVLINK_MSG_ID_SCALED_IMU: {
        mavlink_scaled_imu_t m; mavlink_msg_scaled_imu_decode(&msg, &m); handleScaledImu(m); break; }
    case MAVLINK_MSG_ID_PARAM_VALUE: {
        mavlink_param_value_t m; mavlink_msg_param_value_decode(&msg, &m); handleParamValue(m); break; }
    case MAVLINK_MSG_ID_EKF_STATUS_REPORT: {
        mavlink_ekf_status_report_t m; mavlink_msg_ekf_status_report_decode(&msg, &m); handleEkfStatusReport(m); break; }
    case MAVLINK_MSG_ID_MAG_CAL_PROGRESS: {
        mavlink_mag_cal_progress_t m; mavlink_msg_mag_cal_progress_decode(&msg, &m); handleMagCalProgress(m); break; }
    case MAVLINK_MSG_ID_MAG_CAL_REPORT: {
        mavlink_mag_cal_report_t m; mavlink_msg_mag_cal_report_decode(&msg, &m); handleMagCalReport(m); break; }
    case MAVLINK_MSG_ID_COMMAND_ACK: {
        mavlink_command_ack_t m; mavlink_msg_command_ack_decode(&msg, &m); handleCommandAck(m); break; }
    case MAVLINK_MSG_ID_STATUSTEXT: {
        mavlink_statustext_t m; mavlink_msg_statustext_decode(&msg, &m); handleStatusText(m); break; }
    case MAVLINK_MSG_ID_MISSION_COUNT: {
        mavlink_mission_count_t m; mavlink_msg_mission_count_decode(&msg, &m);
        qDebug() << "[MAVLINK] Mission count:" << m.count; break; }
    case MAVLINK_MSG_ID_MISSION_CURRENT: {
        mavlink_mission_current_t m; mavlink_msg_mission_current_decode(&msg, &m);
        qDebug() << "[MAVLINK] Current mission item:" << m.seq; break; }
    case MAVLINK_MSG_ID_MISSION_ITEM_REACHED: {
        mavlink_mission_item_reached_t m; mavlink_msg_mission_item_reached_decode(&msg, &m);
        qDebug() << "[MAVLINK] Mission item reached:" << m.seq; break; }
    case MAVLINK_MSG_ID_NAMED_VALUE_FLOAT: {
        mavlink_named_value_float_t m; mavlink_msg_named_value_float_decode(&msg, &m);
        qDebug() << "[MAVLINK]" << fixedString(m.name) << "=" << m.value; break; }
    default:
        break;
    }
}

// ---------------------------------------------------------------------------
// Handlers

void MavlinkManager::handleHeartbeat(const mavlink_heartbeat_t &m)
{
    // Only listen to the autopilot itself (ignore other GCS / companion heartbeats)
    if (m.type == MAV_TYPE_GCS)
        return;

    m_lastHeartbeat.restart();
    m_heartbeatEver = true;
    if (!m_heartbeatAlive) {
        m_heartbeatAlive = true;
        emit heartbeatAliveChanged();
    }

    const bool armed = (m.base_mode & MAV_MODE_FLAG_SAFETY_ARMED) != 0;

    // Capture ground references at the moment of arming (AGL zero) and reset IMU velocity
    if (armed && !m_lastArmedState) {
        m_hasGpsAltRef = m_currentFixType >= 3;
        m_gpsAltRef = m_gpsAltitudeMsl;
        m_hasBaroAltRef = m_baroAltitude != 0.0f;
        m_baroAltRef = m_baroAltitude;
        m_imuVx = 0; m_imuVy = 0;
        qDebug() << "[MAVLINK] Ground reference captured (arm): gpsRef="
                 << (m_hasGpsAltRef ? QString::number(double(m_gpsAltRef), 'f', 1) : QStringLiteral("nil"))
                 << "baroRef=" << (m_hasBaroAltRef ? QString::number(double(m_baroAltRef), 'f', 1) : QStringLiteral("nil"));
    }
    m_lastArmedState = armed;

    if (m_armed != armed) {
        qDebug() << "[MAVLINK] Armed state changed:" << armed;
        m_armed = armed;
        emit armedChanged();
    }
    if (m_vehicleType != m.type) {
        m_vehicleType = m.type;
        emit vehicleTypeChanged();
    }
    if (findMode(m.custom_mode) && m_flightMode != m.custom_mode) {
        m_flightMode = m.custom_mode;
        emit flightModeChanged();
    }
}

void MavlinkManager::handleSysStatus(const mavlink_sys_status_t &m)
{
    const float voltage = float(m.voltage_battery) / 1000.0f;
    const float current = float(m.current_battery) / 100.0f;
    const int remaining = m.battery_remaining;

    const bool firstUpdate = m_batteryVoltage == 0.0f;
    const bool voltageChanged = std::fabs(voltage - m_batteryVoltage) > 0.5f;
    const bool remainingChanged = std::abs(remaining - m_batteryRemaining) > 10;

    m_sensorsPresent = m.onboard_control_sensors_present;
    m_sensorsEnabled = m.onboard_control_sensors_enabled;
    m_sensorsHealth = m.onboard_control_sensors_health;
    m_sysStatusReceived = true;
    emit sysStatusChanged();

    m_batteryVoltage = voltage;
    m_batteryCurrent = current;
    m_batteryRemaining = remaining;
    emit batteryChanged();

    if (firstUpdate || voltageChanged || remainingChanged)
        qDebug() << "[MAVLINK] Battery:" << voltage << "V" << current << "A" << remaining << "%";
}

void MavlinkManager::handleGlobalPositionInt(const mavlink_global_position_int_t &m)
{
    m_latitude = double(m.lat) / 1e7;
    m_longitude = double(m.lon) / 1e7;
    m_altitude = float(m.alt) / 1000.0f;
    m_relativeAltitude = float(m.relative_alt) / 1000.0f;
    m_heading = float(m.hdg) / 100.0f;
    emit positionChanged();
}

void MavlinkManager::handleGpsRawInt(const mavlink_gps_raw_int_t &m)
{
    const quint8 fixType = m.fix_type;
    const quint8 satellites = m.satellites_visible;

    const bool firstUpdate = m_gpsFixType == 0;
    const bool fixChanged = fixType != m_gpsFixType;
    const bool satCountChanged = std::abs(int(satellites) - m_gpsSatellites) > 2;

    m_currentFixType = fixType;

    bool hasGpsSpeed = false, hasGpsAgl = false;
    float gpsSpeed = 0, gpsAgl = 0;

    if (fixType >= 3) {
        if (m.vel != UINT16_MAX) {
            gpsSpeed = float(m.vel) / 100.0f;
            hasGpsSpeed = true;
        }
        m_gpsAltitudeMsl = float(m.alt) / 1000.0f;
        if (!m_hasGpsAltRef) {
            m_gpsAltRef = m_gpsAltitudeMsl;   // ground reference at first 3D fix
            m_hasGpsAltRef = true;
        }
        gpsAgl = m_gpsAltitudeMsl - m_gpsAltRef;
        hasGpsAgl = true;

        // Sync IMU dead-reckoning velocity with GPS
        if (hasGpsSpeed) {
            if (m.cog != UINT16_MAX) {
                const float cogRad = float(m.cog) / 100.0f * float(M_PI) / 180.0f;
                m_imuVx = gpsSpeed * std::cos(cogRad);
                m_imuVy = gpsSpeed * std::sin(cogRad);
            } else {
                const float mag = std::sqrt(m_imuVx * m_imuVx + m_imuVy * m_imuVy);
                if (mag > 0.01f) {
                    m_imuVx = m_imuVx / mag * gpsSpeed;
                    m_imuVy = m_imuVy / mag * gpsSpeed;
                }
            }
        }
    }

    const float hdop = m.eph != UINT16_MAX ? float(m.eph) / 100.0f : 99.99f;

    // Receive rate over the last 2 s
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    m_gpsRawTimestamps.append(now);
    while (!m_gpsRawTimestamps.isEmpty() && now - m_gpsRawTimestamps.first() > 2000)
        m_gpsRawTimestamps.removeFirst();
    float rate = 0;
    if (m_gpsRawTimestamps.size() > 1) {
        const qint64 span = now - m_gpsRawTimestamps.first();
        if (span > 0)
            rate = float(m_gpsRawTimestamps.size() - 1) * 1000.0f / float(span);
    }
    m_gpsMessageCount++;

    QVariantMap raw;
    raw.insert(QStringLiteral("received"), true);
    raw.insert(QStringLiteral("messageCount"), m_gpsMessageCount);
    raw.insert(QStringLiteral("lastReceived"), now);
    raw.insert(QStringLiteral("rateHz"), rate);
    raw.insert(QStringLiteral("timeUsec"), qulonglong(m.time_usec));
    raw.insert(QStringLiteral("fixType"), int(fixType));
    raw.insert(QStringLiteral("fixName"), fixName(fixType));
    raw.insert(QStringLiteral("lat"), m.lat);
    raw.insert(QStringLiteral("lon"), m.lon);
    raw.insert(QStringLiteral("alt"), m.alt);
    raw.insert(QStringLiteral("eph"), int(m.eph));
    raw.insert(QStringLiteral("epv"), int(m.epv));
    raw.insert(QStringLiteral("vel"), int(m.vel));
    raw.insert(QStringLiteral("cog"), int(m.cog));
    raw.insert(QStringLiteral("satellitesVisible"), int(satellites));
    raw.insert(QStringLiteral("altEllipsoid"), m.alt_ellipsoid);
    raw.insert(QStringLiteral("hAcc"), uint(m.h_acc));
    raw.insert(QStringLiteral("vAcc"), uint(m.v_acc));
    raw.insert(QStringLiteral("velAcc"), uint(m.vel_acc));
    raw.insert(QStringLiteral("hdgAcc"), uint(m.hdg_acc));
    raw.insert(QStringLiteral("yaw"), int(m.yaw));
    m_gpsRaw = raw;

    m_gpsFixType = fixType;
    m_gpsSatellites = satellites;
    m_gpsHdop = hdop;
    emit gpsChanged();

    m_usingGpsSource = fixType >= 3;
    if (fixType >= 3) {
        if (hasGpsSpeed) m_displaySpeed = gpsSpeed;
        if (hasGpsAgl) m_displayAltitude = gpsAgl;
    }
    emit hudChanged();

    if (fixType >= 2 && (firstUpdate || fixChanged || satCountChanged))
        qDebug() << "[MAVLINK] GPS:" << fixName(fixType) << satellites << "sats";
}

void MavlinkManager::handleAttitude(const mavlink_attitude_t &m)
{
    m_attRollRad = m.roll;
    m_attPitchRad = m.pitch;
    m_attYawRad = m.yaw;

    const float k = 180.0f / float(M_PI);
    const bool firstUpdate = m_roll == 0.0f && m_pitch == 0.0f;
    m_roll = m.roll * k;
    m_pitch = m.pitch * k;
    m_yaw = m.yaw * k;
    emit attitudeChanged();

    if (firstUpdate)
        qDebug() << "[MAVLINK] Attitude: roll" << m_roll << "pitch" << m_pitch << "yaw" << m_yaw;
}

void MavlinkManager::handleServoOutputRaw(const mavlink_servo_output_raw_t &m)
{
    const bool firstUpdate = m_servoValues.value(0).toInt() == 0 && m_servoValues.value(2).toInt() == 0;
    const quint16 v[16] = {m.servo1_raw, m.servo2_raw, m.servo3_raw, m.servo4_raw,
                           m.servo5_raw, m.servo6_raw, m.servo7_raw, m.servo8_raw,
                           m.servo9_raw, m.servo10_raw, m.servo11_raw, m.servo12_raw,
                           m.servo13_raw, m.servo14_raw, m.servo15_raw, m.servo16_raw};
    for (int i = 0; i < 16; ++i)
        m_servoValues[i] = int(v[i]);
    emit servosChanged();

    if (firstUpdate) {
        qDebug() << "[MAVLINK] Servo output (PWM):";
        for (int i = 0; i < 8; ++i)
            if (v[i] > 0)
                qDebug() << "   CH" << (i + 1) << ":" << v[i] << "us";
    }
}

void MavlinkManager::handleVfrHud(const mavlink_vfr_hud_t &m)
{
    const bool firstUpdate = m_groundSpeed == 0.0f && m_altitude == 0.0f;
    m_groundSpeed = m.groundspeed;
    m_climbRate = m.climb;
    m_altitude = m.alt;
    m_heading = float(m.heading);
    emit hudChanged();
    emit positionChanged();

    if (firstUpdate)
        qDebug() << "[MAVLINK] VFR_HUD: speed" << m.groundspeed << "climb" << m.climb
                 << "alt" << m.alt << "hdg" << m.heading;
}

void MavlinkManager::handleScaledPressure(const mavlink_scaled_pressure_t &m)
{
    const float press = m.press_abs;
    const float temp = float(m.temperature) / 100.0f;

    // Barometric altitude (ISA): h = 44330 * (1 - (P/P0)^0.190295)
    if (press > 0) {
        m_baroAltitude = 44330.0f * (1.0f - std::pow(press / 1013.25f, 0.190295f));
        if (!m_hasBaroAltRef) {
            m_baroAltRef = m_baroAltitude;   // ground reference at first sample
            m_hasBaroAltRef = true;
        }
    }

    m_pressure = press;
    m_temperature = temp;

    // Altitude from barometer while there is no GPS fix
    if (m_currentFixType < 3 && m_hasBaroAltRef) {
        m_usingGpsSource = false;
        m_displayAltitude = m_baroAltitude - m_baroAltRef;
    }
    emit hudChanged();
}

void MavlinkManager::handleScaledImu(const mavlink_scaled_imu_t &m)
{
    // Speed while there is no GPS fix: rotate body specific force to earth frame and
    // integrate the horizontal components. Dead-reckoning drifts; GPS re-syncs it.
    const bool hadLast = m_hasLastImuTime;
    const quint32 lastMs = m_lastImuTimeMs;
    m_lastImuTimeMs = m.time_boot_ms;
    m_hasLastImuTime = true;

    if (!hadLast || m.time_boot_ms <= lastMs)
        return;
    const float dt = float(m.time_boot_ms - lastMs) / 1000.0f;
    if (dt <= 0 || dt >= 0.5f)
        return;   // do not integrate across a broken/paused stream

    const float g = 9.80665f;
    const float ax = float(m.xacc) * g / 1000.0f;
    const float ay = float(m.yacc) * g / 1000.0f;
    const float az = float(m.zacc) * g / 1000.0f;

    const float cr = std::cos(m_attRollRad), sr = std::sin(m_attRollRad);
    const float cp = std::cos(m_attPitchRad), sp = std::sin(m_attPitchRad);
    const float cy = std::cos(m_attYawRad), sy = std::sin(m_attYawRad);

    const float aN = cy * cp * ax + (cy * sp * sr - sy * cr) * ay + (cy * sp * cr + sy * sr) * az;
    const float aE = sy * cp * ax + (sy * sp * sr + cy * cr) * ay + (sy * sp * cr - cy * sr) * az;

    // Zero-velocity update: total ~1 g and small horizontal accel -> damp velocity quickly
    const float totalMag = std::sqrt(ax * ax + ay * ay + az * az);
    const float horizMag = std::sqrt(aN * aN + aE * aE);
    const bool stationary = std::fabs(totalMag - g) < 0.3f && horizMag < 0.25f;

    if (stationary) {
        m_imuVx *= 0.80f;
        m_imuVy *= 0.80f;
        if (std::fabs(m_imuVx) < 0.05f) m_imuVx = 0;
        if (std::fabs(m_imuVy) < 0.05f) m_imuVy = 0;
    } else {
        m_imuVx += aN * dt;
        m_imuVy += aE * dt;
        const float leak = 1.0f - 0.02f * dt / 0.1f;   // leaky integration against bias drift
        m_imuVx *= leak;
        m_imuVy *= leak;
    }

    if (m_currentFixType < 3) {
        m_usingGpsSource = false;
        m_displaySpeed = std::sqrt(m_imuVx * m_imuVx + m_imuVy * m_imuVy);
        emit hudChanged();
    }
}

void MavlinkManager::handleParamValue(const mavlink_param_value_t &m)
{
    const QString name = fixedString(m.param_id);
    const int index = m.param_index;
    const int count = m.param_count;

    m_parameters.setValue(name, m.param_value);
    bool changed = false;
    if (count > 0 && m_paramTotalCount != count) {
        m_paramTotalCount = count;
        changed = true;
    }
    if (m_paramDownloading && (index >= count - 1 || (count > 0 && m_parameters.count() >= count))) {
        m_paramDownloading = false;
        changed = true;
    }
    if (changed)
        emit paramStateChanged();

    if (index < count)
        qDebug() << "[MAVLINK] Param [" << (index + 1) << "/" << count << "]" << name << "=" << m.param_value;
}

void MavlinkManager::handleEkfStatusReport(const mavlink_ekf_status_report_t &m)
{
    m_ekfFlags = m.flags;
    m_ekfVelocityVariance = m.velocity_variance;
    m_ekfPosHorizVariance = m.pos_horiz_variance;
    m_ekfCompassVariance = m.compass_variance;
    m_ekfReportReceived = true;
    emit ekfChanged();
}

void MavlinkManager::handleMagCalProgress(const mavlink_mag_cal_progress_t &m)
{
    QVariantList mask;
    int sectionsDone = 0;
    for (int i = 0; i < 10; ++i) {
        mask.append(int(m.completion_mask[i]));
        for (int b = 0; b < 8; ++b)
            if (m.completion_mask[i] & (1 << b))
                sectionsDone++;
    }
    QVariantMap d;
    d.insert(QStringLiteral("compassId"), int(m.compass_id));
    d.insert(QStringLiteral("calMask"), int(m.cal_mask));
    d.insert(QStringLiteral("status"), int(m.cal_status));
    d.insert(QStringLiteral("statusName"), magCalStatusName(m.cal_status));
    d.insert(QStringLiteral("attempt"), int(m.attempt));
    d.insert(QStringLiteral("completionPct"), int(m.completion_pct));
    d.insert(QStringLiteral("completionMask"), mask);
    d.insert(QStringLiteral("sectionsDone"), sectionsDone);
    d.insert(QStringLiteral("directionX"), m.direction_x);
    d.insert(QStringLiteral("directionY"), m.direction_y);
    d.insert(QStringLiteral("directionZ"), m.direction_z);
    m_magCalProgress[m.compass_id] = d;
    m_magCalRunning = true;
    emit magCalChanged();
}

void MavlinkManager::handleMagCalReport(const mavlink_mag_cal_report_t &m)
{
    QVariantMap d;
    d.insert(QStringLiteral("compassId"), int(m.compass_id));
    d.insert(QStringLiteral("calMask"), int(m.cal_mask));
    d.insert(QStringLiteral("status"), int(m.cal_status));
    d.insert(QStringLiteral("statusName"), magCalStatusName(m.cal_status));
    d.insert(QStringLiteral("success"), m.cal_status == 4);
    d.insert(QStringLiteral("autosaved"), m.autosaved != 0);
    d.insert(QStringLiteral("fitness"), m.fitness);
    QString quality;
    if (m.fitness < 5) quality = QStringLiteral("Excellent");
    else if (m.fitness < 10) quality = QStringLiteral("Good");
    else if (m.fitness < 20) quality = QStringLiteral("Acceptable");
    else if (m.fitness < 40) quality = QStringLiteral("Poor");
    else quality = QStringLiteral("Bad");
    d.insert(QStringLiteral("qualityText"), quality);
    d.insert(QStringLiteral("ofsX"), m.ofs_x); d.insert(QStringLiteral("ofsY"), m.ofs_y); d.insert(QStringLiteral("ofsZ"), m.ofs_z);
    d.insert(QStringLiteral("diagX"), m.diag_x); d.insert(QStringLiteral("diagY"), m.diag_y); d.insert(QStringLiteral("diagZ"), m.diag_z);
    d.insert(QStringLiteral("offdiagX"), m.offdiag_x); d.insert(QStringLiteral("offdiagY"), m.offdiag_y); d.insert(QStringLiteral("offdiagZ"), m.offdiag_z);
    d.insert(QStringLiteral("orientationConfidence"), m.orientation_confidence);
    d.insert(QStringLiteral("oldOrientation"), int(m.old_orientation));
    d.insert(QStringLiteral("newOrientation"), int(m.new_orientation));
    d.insert(QStringLiteral("scaleFactor"), m.scale_factor);

    qDebug() << "[CAL] MAG_CAL_REPORT compass=" << m.compass_id << "status=" << magCalStatusName(m.cal_status)
             << "fitness=" << m.fitness << "autosaved=" << m.autosaved;

    m_magCalReports[m.compass_id] = d;

    // Reports for every calibrated compass received?
    bool allReported = true;
    for (auto it = m_magCalProgress.cbegin(); it != m_magCalProgress.cend(); ++it)
        if (!m_magCalReports.contains(it.key()))
            allReported = false;
    bool allSuccess = true;
    for (const QVariantMap &r : m_magCalReports)
        if (!r.value(QStringLiteral("success")).toBool())
            allSuccess = false;

    if (allReported) {
        m_magCalRunning = false;
        if (m.autosaved) {
            m_magCalSaved = true;
        } else if (allSuccess && m_magCalAutoAccept && !m_magCalAcceptSent) {
            acceptCompassCalibration();   // fitness seen, write offsets to the device
        }
    }
    emit magCalChanged();
}

void MavlinkManager::handleCommandAck(const mavlink_command_ack_t &m)
{
    const QString resultStr = resultToString(m.result);
    qDebug() << "[MAVLINK] Command" << m.command << "ACK:" << resultStr;
    const bool accepted = m.result == MAV_RESULT_ACCEPTED;

    switch (m.command) {
    case MAV_CMD_DO_START_MAG_CAL:
        m_magCalStartAck = resultStr;
        if (!accepted)
            m_magCalRunning = false;
        emit magCalChanged();
        break;
    case MAV_CMD_DO_ACCEPT_MAG_CAL:
        m_magCalAcceptAck = resultStr;
        m_magCalSaved = accepted;
        emit magCalChanged();
        break;
    case MAV_CMD_PREFLIGHT_CALIBRATION: {
        const bool inProgress = m.result == MAV_RESULT_IN_PROGRESS;
        const QString which = m_pendingPreflightCal;
        if (!inProgress)
            m_pendingPreflightCal.clear();
        QVariantMap state = inProgress
            ? calState(QStringLiteral("inProgress"), QString())
            : (accepted ? calState(QStringLiteral("success"), QStringLiteral("ACK: ") + resultStr)
                        : calState(QStringLiteral("failed"), QStringLiteral("ACK: ") + resultStr));
        if (inProgress) {
            // keep the original start time
            const QVariantMap &old = which == QLatin1String("gyro") ? m_gyroCalState : m_baroCalState;
            state.insert(QStringLiteral("startedMs"), old.value(QStringLiteral("startedMs")));
        }
        if (which == QLatin1String("gyro")) m_gyroCalState = state;
        if (which == QLatin1String("baro")) m_baroCalState = state;
        emit simpleCalChanged();
        break;
    }
    case MAV_CMD_DO_MOTOR_TEST:
        m_motorTestAckAccepted = accepted ? 1 : 0;
        m_motorTestAckText = resultStr;
        emit motorTestChanged();
        break;
    case MAV_CMD_COMPONENT_ARM_DISARM:
        if (accepted)
            qDebug() << "[MAVLINK] ARM/DISARM command accepted";
        else
            qWarning() << "[MAVLINK] ARM/DISARM command failed:" << resultStr;
        break;
    default:
        break;
    }
    emit commandAck(m.command, m.result, resultStr);
}

void MavlinkManager::handleStatusText(const mavlink_statustext_t &m)
{
    const QString text = fixedString(m.text);
    qDebug() << "[STATUSTEXT]" << MessagesModel::severityName(m.severity) << text;
    m_messages.append(m.severity, text);
}

// ---------------------------------------------------------------------------
// Commands

void MavlinkManager::armVehicle(bool force)
{
    qDebug() << "[MAVLINK] Arming vehicle (force=" << force << ")";
    sendCommandLong(MAV_CMD_COMPONENT_ARM_DISARM, 1.0f, force ? 21196.0f : 0.0f);
}

void MavlinkManager::disarmVehicle(bool force)
{
    qDebug() << "[MAVLINK] Disarming vehicle (force=" << force << ")";
    sendCommandLong(MAV_CMD_COMPONENT_ARM_DISARM, 0.0f, force ? 21196.0f : 0.0f);
}

void MavlinkManager::setFlightMode(uint customMode)
{
    qDebug() << "[MAVLINK] Setting mode:" << customMode;
    mavlink_message_t msg;
    mavlink_set_mode_t sm{};
    sm.target_system = m_targetSystemId;
    sm.base_mode = MAV_MODE_FLAG_CUSTOM_MODE_ENABLED;
    sm.custom_mode = customMode;
    mavlink_msg_set_mode_encode(m_systemId, m_componentId, &msg, &sm);
    sendMessage(msg);
}

void MavlinkManager::sendManualControl(int x, int y, int z, int r, int buttons)
{
    mavlink_message_t msg;
    mavlink_manual_control_t mc{};
    mc.target = m_targetSystemId;
    mc.x = int16_t(qBound(-1000, x, 1000));
    mc.y = int16_t(qBound(-1000, y, 1000));
    mc.z = int16_t(qBound(-1000, z, 1000));
    mc.r = int16_t(qBound(-1000, r, 1000));
    mc.buttons = uint16_t(buttons);
    mavlink_msg_manual_control_encode(m_systemId, m_componentId, &msg, &mc);
    sendMessage(msg);
}

void MavlinkManager::setServo(int channel, int pwm)
{
    qDebug() << "[MAVLINK] Setting servo" << channel << "to" << pwm;
    sendCommandLong(MAV_CMD_DO_SET_SERVO, float(channel), float(pwm));
}

// ArduCopter motor test. motorSeq = ArduPilot test order (A=1, B=2, C=3, D=4 clockwise
// from front-right), NOT the MOTOR_x output number. Throttle type PWM, timeout seconds;
// timeout 0 = stop now.
void MavlinkManager::motorTest(int motorSeq, int pwm, float timeoutSec)
{
    qDebug() << "[MOTOR TEST] seq=" << motorSeq << "pwm=" << pwm << "timeout=" << timeoutSec << "s";
    sendCommandLong(MAV_CMD_DO_MOTOR_TEST,
                    float(motorSeq),
                    float(MOTOR_TEST_THROTTLE_PWM),
                    float(pwm),
                    timeoutSec,
                    0,
                    float(MOTOR_TEST_ORDER_DEFAULT),
                    0);
    if (timeoutSec > 0) {
        m_motorTestClearTimer.stop();
        if (!m_motorTestActive) {
            m_motorTestActive = true;
            emit motorTestChanged();
            emit armedChanged();
        }
    }
}

void MavlinkManager::stopMotorTest(int motorSeq)
{
    motorTest(motorSeq, 1000, 0);
    // FC may report "armed" for a few more heartbeats; clear the flag after 2 s
    m_motorTestClearTimer.start();
}

void MavlinkManager::startCompassCalibration(bool retryOnFailure, bool autoSave, bool autoAccept)
{
    qDebug() << "[CAL] Starting compass calibration (retry=" << retryOnFailure << "autosave=" << autoSave << ")";
    m_magCalProgress.clear();
    m_magCalReports.clear();
    m_magCalRunning = true;
    m_magCalStartAck.clear();
    m_magCalAcceptAck.clear();
    m_magCalSaved = false;
    m_magCalAcceptSent = false;
    m_magCalAutoAccept = autoAccept;
    emit magCalChanged();
    sendCommandLong(MAV_CMD_DO_START_MAG_CAL,
                    0,                          // bitmask 0 = all compasses
                    retryOnFailure ? 1 : 0,
                    autoSave ? 1 : 0,           // 0 = wait for ACCEPT
                    0,                          // delay (s)
                    0);                         // autoreboot
}

void MavlinkManager::cancelCompassCalibration()
{
    qDebug() << "[CAL] Cancel compass calibration";
    sendCommandLong(MAV_CMD_DO_CANCEL_MAG_CAL, 0);
    m_magCalRunning = false;
    emit magCalChanged();
}

void MavlinkManager::acceptCompassCalibration()
{
    qDebug() << "[CAL] Accept compass calibration (write to params)";
    m_magCalAcceptSent = true;
    sendCommandLong(MAV_CMD_DO_ACCEPT_MAG_CAL, 0);
}

QVariantMap MavlinkManager::calState(const QString &state, const QString &text)
{
    QVariantMap m;
    m.insert(QStringLiteral("state"), state);
    m.insert(QStringLiteral("text"), text);
    m.insert(QStringLiteral("startedMs"), QDateTime::currentMSecsSinceEpoch());
    return m;
}

void MavlinkManager::calibrateGyro()
{
    qDebug() << "[CAL] Gyro calibration";
    m_pendingPreflightCal = QStringLiteral("gyro");
    m_gyroCalState = calState(QStringLiteral("inProgress"), QString());
    emit simpleCalChanged();
    sendCommandLong(MAV_CMD_PREFLIGHT_CALIBRATION, 1);
    startPreflightCalTimeout(QStringLiteral("gyro"));
}

void MavlinkManager::calibrateBarometer()
{
    qDebug() << "[CAL] Barometer ground pressure calibration";
    m_pendingPreflightCal = QStringLiteral("baro");
    m_baroCalState = calState(QStringLiteral("inProgress"), QString());
    emit simpleCalChanged();
    sendCommandLong(MAV_CMD_PREFLIGHT_CALIBRATION, 0, 0, 1);
    startPreflightCalTimeout(QStringLiteral("baro"));
}

void MavlinkManager::rebootFlightController()
{
    qDebug() << "[CAL] Reboot flight controller";
    sendCommandLong(MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN, 1);
}

void MavlinkManager::startPreflightCalTimeout(const QString &which)
{
    QTimer::singleShot(15000, this, [this, which]() {
        QVariantMap &st = which == QLatin1String("gyro") ? m_gyroCalState : m_baroCalState;
        if (st.value(QStringLiteral("state")).toString() == QLatin1String("inProgress")) {
            st = calState(QStringLiteral("failed"), QStringLiteral("No ACK within 15 s"));
            emit simpleCalChanged();
        }
    });
}

void MavlinkManager::requestAllParameters()
{
    qDebug() << "[MAVLINK] Requesting all parameters";
    m_paramDownloading = true;
    emit paramStateChanged();
    mavlink_message_t msg;
    mavlink_param_request_list_t req{};
    req.target_system = m_targetSystemId;
    req.target_component = m_targetComponentId;
    mavlink_msg_param_request_list_encode(m_systemId, m_componentId, &msg, &req);
    sendMessage(msg);
}

void MavlinkManager::requestParameter(const QString &name)
{
    if (name.size() > 16)
        return;
    mavlink_message_t msg;
    mavlink_param_request_read_t req{};
    req.target_system = m_targetSystemId;
    req.target_component = m_targetComponentId;
    req.param_index = -1;   // -1: query by name
    fillFixedString(req.param_id, name);
    mavlink_msg_param_request_read_encode(m_systemId, m_componentId, &msg, &req);
    sendMessage(msg);
}

void MavlinkManager::setParameter(const QString &name, float value)
{
    if (name.size() > 16)
        return;
    mavlink_message_t msg;
    mavlink_param_set_t ps{};
    ps.target_system = m_targetSystemId;
    ps.target_component = m_targetComponentId;
    ps.param_value = value;
    ps.param_type = MAV_PARAM_TYPE_REAL32;
    fillFixedString(ps.param_id, name);
    mavlink_msg_param_set_encode(m_systemId, m_componentId, &msg, &ps);
    sendMessage(msg);
}

int MavlinkManager::defaultParameterCount() const
{
    return DefaultParameters::values().size();
}

void MavlinkManager::restoreDefaultParameters()
{
    if (m_restoreInProgress)
        return;
    m_restoreInProgress = true;
    m_restoreIndex = 0;
    m_restoreProgress = 0;
    m_restoreTotal = DefaultParameters::values().size();
    emit restoreChanged();
    m_restoreTimer.start();
}

void MavlinkManager::cancelRestore()
{
    if (!m_restoreInProgress)
        return;
    m_restoreTimer.stop();
    m_restoreInProgress = false;
    emit restoreChanged();
}

// ---------------------------------------------------------------------------
// Presentation helpers

QString MavlinkManager::resultToString(quint8 result)
{
    switch (result) {
    case MAV_RESULT_ACCEPTED: return QStringLiteral("ACCEPTED");
    case MAV_RESULT_TEMPORARILY_REJECTED: return QStringLiteral("TEMPORARILY_REJECTED");
    case MAV_RESULT_DENIED: return QStringLiteral("DENIED");
    case MAV_RESULT_UNSUPPORTED: return QStringLiteral("UNSUPPORTED");
    case MAV_RESULT_FAILED: return QStringLiteral("FAILED");
    case MAV_RESULT_IN_PROGRESS: return QStringLiteral("IN_PROGRESS");
    default: return QStringLiteral("UNKNOWN(%1)").arg(result);
    }
}

QString MavlinkManager::vehicleTypeName() const
{
    switch (m_vehicleType) {
    case 1: return QStringLiteral("Fixed Wing");
    case 2: return QStringLiteral("Quadrotor");
    case 10: return QStringLiteral("Ground Rover");
    case 12: return QStringLiteral("Submarine");
    default: return QStringLiteral("Unknown (%1)").arg(m_vehicleType);
    }
}

QString MavlinkManager::flightModeName() const
{
    const ModeInfo *m = findMode(m_flightMode);
    return m ? QString::fromLatin1(m->name) : QStringLiteral("Mode %1").arg(m_flightMode);
}

QString MavlinkManager::flightModeColor() const
{
    const ModeInfo *m = findMode(m_flightMode);
    return m ? QString::fromLatin1(m->color) : QStringLiteral("#8E8E93");
}

QString MavlinkManager::flightModeIcon() const
{
    const ModeInfo *m = findMode(m_flightMode);
    return m ? QString::fromLatin1(m->icon) : QStringLiteral("?");
}

QVariantMap MavlinkManager::modeInfo(uint customMode) const
{
    QVariantMap out;
    const ModeInfo *m = findMode(customMode);
    out.insert(QStringLiteral("mode"), customMode);
    out.insert(QStringLiteral("name"), m ? QString::fromLatin1(m->name) : QStringLiteral("Mode %1").arg(customMode));
    out.insert(QStringLiteral("icon"), m ? QString::fromLatin1(m->icon) : QStringLiteral("?"));
    out.insert(QStringLiteral("color"), m ? QString::fromLatin1(m->color) : QStringLiteral("#8E8E93"));
    out.insert(QStringLiteral("description"), m ? QString::fromLatin1(m->description) : QString());
    return out;
}

QVariantList MavlinkManager::availableModes() const
{
    // Same selection as FlightModeView.swift
    static const uint modes[] = {0, 2, 16, 5, 9, 6, 3, 15};
    QVariantList out;
    for (uint m : modes)
        out.append(modeInfo(m));
    return out;
}

QVariantList MavlinkManager::magCalProgress() const
{
    QVariantList out;
    for (const QVariantMap &m : m_magCalProgress)
        out.append(m);
    return out;
}

QVariantList MavlinkManager::magCalReports() const
{
    QVariantList out;
    for (const QVariantMap &m : m_magCalReports)
        out.append(m);
    return out;
}
