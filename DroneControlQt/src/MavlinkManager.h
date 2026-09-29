// MavlinkManager.h - DroneControlQt
//
// Port of MAVLinkManager.swift + MAVLinkProtocol.swift: MAVLink parsing,
// telemetry state exposed to QML through properties, and vehicle commands.
// Everything runs on the GUI thread (QUdpSocket readyRead + QTimers).

#pragma once

#include <QDateTime>
#include <QElapsedTimer>
#include <QList>
#include <QMap>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

#include "MessagesModel.h"
#include "ParameterModel.h"
#include "UdpConnection.h"

// Pull in the ArduPilot dialect (contains common). Compiled as C++.
#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpedantic"
#pragma GCC diagnostic ignored "-Wunused-parameter"
#endif
#include "ardupilotmega/mavlink.h"
#if defined(__GNUC__)
#pragma GCC diagnostic pop
#endif

class MavlinkManager : public QObject
{
    Q_OBJECT

    // Link
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)
    Q_PROPERTY(bool heartbeatAlive READ heartbeatAlive NOTIFY heartbeatAliveChanged)
    Q_PROPERTY(bool armed READ isArmed NOTIFY armedChanged)
    Q_PROPERTY(bool armedByPilot READ isArmedByPilot NOTIFY armedChanged)
    Q_PROPERTY(int vehicleType READ vehicleType NOTIFY vehicleTypeChanged)
    Q_PROPERTY(QString vehicleTypeName READ vehicleTypeName NOTIFY vehicleTypeChanged)
    Q_PROPERTY(uint flightMode READ flightMode NOTIFY flightModeChanged)
    Q_PROPERTY(QString flightModeName READ flightModeName NOTIFY flightModeChanged)
    Q_PROPERTY(QString flightModeColor READ flightModeColor NOTIFY flightModeChanged)
    Q_PROPERTY(QString flightModeIcon READ flightModeIcon NOTIFY flightModeChanged)
    Q_PROPERTY(int targetSystemId READ targetSystemId CONSTANT)
    Q_PROPERTY(int targetComponentId READ targetComponentId CONSTANT)

    // Position / attitude
    Q_PROPERTY(double latitude READ latitude NOTIFY positionChanged)
    Q_PROPERTY(double longitude READ longitude NOTIFY positionChanged)
    Q_PROPERTY(float altitude READ altitude NOTIFY positionChanged)
    Q_PROPERTY(float relativeAltitude READ relativeAltitude NOTIFY positionChanged)
    Q_PROPERTY(float heading READ heading NOTIFY positionChanged)
    Q_PROPERTY(float roll READ roll NOTIFY attitudeChanged)
    Q_PROPERTY(float pitch READ pitch NOTIFY attitudeChanged)
    Q_PROPERTY(float yaw READ yaw NOTIFY attitudeChanged)

    // GPS
    Q_PROPERTY(int gpsFixType READ gpsFixType NOTIFY gpsChanged)
    Q_PROPERTY(int gpsSatellites READ gpsSatellites NOTIFY gpsChanged)
    Q_PROPERTY(float gpsHdop READ gpsHdop NOTIFY gpsChanged)
    Q_PROPERTY(QVariantMap gpsRaw READ gpsRaw NOTIFY gpsChanged)
    Q_PROPERTY(uint sensorsPresent READ sensorsPresent NOTIFY sysStatusChanged)
    Q_PROPERTY(uint sensorsEnabled READ sensorsEnabled NOTIFY sysStatusChanged)
    Q_PROPERTY(uint sensorsHealth READ sensorsHealth NOTIFY sysStatusChanged)
    Q_PROPERTY(bool sysStatusReceived READ sysStatusReceived NOTIFY sysStatusChanged)

    // HUD
    Q_PROPERTY(float groundSpeed READ groundSpeed NOTIFY hudChanged)
    Q_PROPERTY(float climbRate READ climbRate NOTIFY hudChanged)
    Q_PROPERTY(float pressure READ pressure NOTIFY hudChanged)
    Q_PROPERTY(float temperature READ temperature NOTIFY hudChanged)
    Q_PROPERTY(float displayAltitude READ displayAltitude NOTIFY hudChanged)
    Q_PROPERTY(float displaySpeed READ displaySpeed NOTIFY hudChanged)
    Q_PROPERTY(bool usingGpsSource READ usingGpsSource NOTIFY hudChanged)

    // Battery
    Q_PROPERTY(float batteryVoltage READ batteryVoltage NOTIFY batteryChanged)
    Q_PROPERTY(float batteryCurrent READ batteryCurrent NOTIFY batteryChanged)
    Q_PROPERTY(int batteryRemaining READ batteryRemaining NOTIFY batteryChanged)

    // Servos (16 entries, index 0 = channel 1)
    Q_PROPERTY(QVariantList servoValues READ servoValues NOTIFY servosChanged)

    // Parameters
    Q_PROPERTY(ParameterModel *parameters READ parameters CONSTANT)
    Q_PROPERTY(int paramTotalCount READ paramTotalCount NOTIFY paramStateChanged)
    Q_PROPERTY(bool paramDownloading READ paramDownloading NOTIFY paramStateChanged)
    Q_PROPERTY(bool restoreInProgress READ restoreInProgress NOTIFY restoreChanged)
    Q_PROPERTY(int restoreProgress READ restoreProgress NOTIFY restoreChanged)
    Q_PROPERTY(int restoreTotal READ restoreTotal NOTIFY restoreChanged)
    Q_PROPERTY(int defaultParameterCount READ defaultParameterCount CONSTANT)

    // Messages / EKF
    Q_PROPERTY(MessagesModel *messages READ messages CONSTANT)
    Q_PROPERTY(int ekfFlags READ ekfFlags NOTIFY ekfChanged)
    Q_PROPERTY(float ekfVelocityVariance READ ekfVelocityVariance NOTIFY ekfChanged)
    Q_PROPERTY(float ekfPosHorizVariance READ ekfPosHorizVariance NOTIFY ekfChanged)
    Q_PROPERTY(float ekfCompassVariance READ ekfCompassVariance NOTIFY ekfChanged)
    Q_PROPERTY(bool ekfReportReceived READ ekfReportReceived NOTIFY ekfChanged)

    // Motor test
    Q_PROPERTY(QString motorTestAckText READ motorTestAckText NOTIFY motorTestChanged)
    Q_PROPERTY(int motorTestAckAccepted READ motorTestAckAccepted NOTIFY motorTestChanged) // -1 none, 0 no, 1 yes
    Q_PROPERTY(bool motorTestActive READ motorTestActive NOTIFY motorTestChanged)

    // Calibration
    Q_PROPERTY(QVariantList magCalProgress READ magCalProgress NOTIFY magCalChanged)
    Q_PROPERTY(QVariantList magCalReports READ magCalReports NOTIFY magCalChanged)
    Q_PROPERTY(bool magCalRunning READ magCalRunning NOTIFY magCalChanged)
    Q_PROPERTY(QString magCalStartAck READ magCalStartAck NOTIFY magCalChanged)
    Q_PROPERTY(QString magCalAcceptAck READ magCalAcceptAck NOTIFY magCalChanged)
    Q_PROPERTY(bool magCalSaved READ magCalSaved NOTIFY magCalChanged)
    Q_PROPERTY(QVariantMap gyroCalState READ gyroCalState NOTIFY simpleCalChanged)
    Q_PROPERTY(QVariantMap baroCalState READ baroCalState NOTIFY simpleCalChanged)

    Q_PROPERTY(QVariantList availableModes READ availableModes CONSTANT)

public:
    explicit MavlinkManager(QObject *parent = nullptr);
    ~MavlinkManager() override;

    // --- getters ---
    bool isConnected() const { return m_connected; }
    bool heartbeatAlive() const { return m_heartbeatAlive; }
    bool isArmed() const { return m_armed; }
    bool isArmedByPilot() const { return m_armed && !m_motorTestActive; }
    int vehicleType() const { return m_vehicleType; }
    QString vehicleTypeName() const;
    uint flightMode() const { return m_flightMode; }
    QString flightModeName() const;
    QString flightModeColor() const;
    QString flightModeIcon() const;
    int targetSystemId() const { return m_targetSystemId; }
    int targetComponentId() const { return m_targetComponentId; }

    double latitude() const { return m_latitude; }
    double longitude() const { return m_longitude; }
    float altitude() const { return m_altitude; }
    float relativeAltitude() const { return m_relativeAltitude; }
    float heading() const { return m_heading; }
    float roll() const { return m_roll; }
    float pitch() const { return m_pitch; }
    float yaw() const { return m_yaw; }

    int gpsFixType() const { return m_gpsFixType; }
    int gpsSatellites() const { return m_gpsSatellites; }
    float gpsHdop() const { return m_gpsHdop; }
    QVariantMap gpsRaw() const { return m_gpsRaw; }
    uint sensorsPresent() const { return m_sensorsPresent; }
    uint sensorsEnabled() const { return m_sensorsEnabled; }
    uint sensorsHealth() const { return m_sensorsHealth; }
    bool sysStatusReceived() const { return m_sysStatusReceived; }

    float groundSpeed() const { return m_groundSpeed; }
    float climbRate() const { return m_climbRate; }
    float pressure() const { return m_pressure; }
    float temperature() const { return m_temperature; }
    float displayAltitude() const { return m_displayAltitude; }
    float displaySpeed() const { return m_displaySpeed; }
    bool usingGpsSource() const { return m_usingGpsSource; }

    float batteryVoltage() const { return m_batteryVoltage; }
    float batteryCurrent() const { return m_batteryCurrent; }
    int batteryRemaining() const { return m_batteryRemaining; }

    QVariantList servoValues() const { return m_servoValues; }

    ParameterModel *parameters() { return &m_parameters; }
    int paramTotalCount() const { return m_paramTotalCount; }
    bool paramDownloading() const { return m_paramDownloading; }
    bool restoreInProgress() const { return m_restoreInProgress; }
    int restoreProgress() const { return m_restoreProgress; }
    int restoreTotal() const { return m_restoreTotal; }
    int defaultParameterCount() const;

    MessagesModel *messages() { return &m_messages; }
    int ekfFlags() const { return m_ekfFlags; }
    float ekfVelocityVariance() const { return m_ekfVelocityVariance; }
    float ekfPosHorizVariance() const { return m_ekfPosHorizVariance; }
    float ekfCompassVariance() const { return m_ekfCompassVariance; }
    bool ekfReportReceived() const { return m_ekfReportReceived; }

    QString motorTestAckText() const { return m_motorTestAckText; }
    int motorTestAckAccepted() const { return m_motorTestAckAccepted; }
    bool motorTestActive() const { return m_motorTestActive; }

    QVariantList magCalProgress() const;
    QVariantList magCalReports() const;
    bool magCalRunning() const { return m_magCalRunning; }
    QString magCalStartAck() const { return m_magCalStartAck; }
    QString magCalAcceptAck() const { return m_magCalAcceptAck; }
    bool magCalSaved() const { return m_magCalSaved; }
    QVariantMap gyroCalState() const { return m_gyroCalState; }
    QVariantMap baroCalState() const { return m_baroCalState; }

    QVariantList availableModes() const;
    Q_INVOKABLE QVariantMap modeInfo(uint customMode) const;

    // --- link ---
    Q_INVOKABLE void setEndpoint(const QString &host, int port, int localPort = 14550);
    Q_INVOKABLE void connectVehicle();
    Q_INVOKABLE void disconnectVehicle();

    // --- commands ---
    Q_INVOKABLE void armVehicle(bool force = false);
    Q_INVOKABLE void disarmVehicle(bool force = false);
    Q_INVOKABLE void setFlightMode(uint customMode);
    Q_INVOKABLE void sendManualControl(int x, int y, int z, int r, int buttons = 0);
    Q_INVOKABLE void setServo(int channel, int pwm);
    Q_INVOKABLE void motorTest(int motorSeq, int pwm, float timeoutSec);
    Q_INVOKABLE void stopMotorTest(int motorSeq = 1);

    Q_INVOKABLE void startCompassCalibration(bool retryOnFailure = true, bool autoSave = false, bool autoAccept = true);
    Q_INVOKABLE void cancelCompassCalibration();
    Q_INVOKABLE void acceptCompassCalibration();
    Q_INVOKABLE void calibrateGyro();
    Q_INVOKABLE void calibrateBarometer();
    Q_INVOKABLE void rebootFlightController();

    Q_INVOKABLE void requestAllParameters();
    Q_INVOKABLE void requestParameter(const QString &name);
    Q_INVOKABLE void setParameter(const QString &name, float value);
    Q_INVOKABLE void restoreDefaultParameters();
    Q_INVOKABLE void cancelRestore();

    static QString resultToString(quint8 result);

public slots:
    void arm() { armVehicle(true); }      // gamepad START
    void disarm() { disarmVehicle(true); } // gamepad BACK

signals:
    void connectedChanged();
    void heartbeatAliveChanged();
    void armedChanged();
    void vehicleTypeChanged();
    void flightModeChanged();
    void positionChanged();
    void attitudeChanged();
    void gpsChanged();
    void sysStatusChanged();
    void hudChanged();
    void batteryChanged();
    void servosChanged();
    void paramStateChanged();
    void restoreChanged();
    void ekfChanged();
    void motorTestChanged();
    void magCalChanged();
    void simpleCalChanged();
    void commandAck(int command, int result, const QString &resultText);

private:
    // parsing
    void parseData(const QByteArray &data);
    void processMessage(const mavlink_message_t &msg);
    void sendMessage(const mavlink_message_t &msg);
    void sendHeartbeat();
    void requestTelemetryMessages();
    void setMessageInterval(quint32 messageId, qint32 intervalUs);
    void sendCommandLong(quint16 command, float p1 = 0, float p2 = 0, float p3 = 0, float p4 = 0,
                         float p5 = 0, float p6 = 0, float p7 = 0);
    void startPreflightCalTimeout(const QString &which);
    static QVariantMap calState(const QString &state, const QString &text);

    // handlers
    void handleHeartbeat(const mavlink_heartbeat_t &m);
    void handleSysStatus(const mavlink_sys_status_t &m);
    void handleGlobalPositionInt(const mavlink_global_position_int_t &m);
    void handleGpsRawInt(const mavlink_gps_raw_int_t &m);
    void handleAttitude(const mavlink_attitude_t &m);
    void handleServoOutputRaw(const mavlink_servo_output_raw_t &m);
    void handleVfrHud(const mavlink_vfr_hud_t &m);
    void handleScaledPressure(const mavlink_scaled_pressure_t &m);
    void handleScaledImu(const mavlink_scaled_imu_t &m);
    void handleParamValue(const mavlink_param_value_t &m);
    void handleEkfStatusReport(const mavlink_ekf_status_report_t &m);
    void handleMagCalProgress(const mavlink_mag_cal_progress_t &m);
    void handleMagCalReport(const mavlink_mag_cal_report_t &m);
    void handleCommandAck(const mavlink_command_ack_t &m);
    void handleStatusText(const mavlink_statustext_t &m);

    UdpConnection m_udp;
    mavlink_status_t m_status{};
    mavlink_message_t m_message{};
    QSet<quint32> m_seenMessageIds;

    const quint8 m_systemId = 255;
    const quint8 m_componentId = 190;
    quint8 m_targetSystemId = 1;
    quint8 m_targetComponentId = 1;

    QTimer m_heartbeatTimer;
    QTimer m_watchdogTimer;
    QElapsedTimer m_lastHeartbeat;
    bool m_heartbeatEver = false;
    bool m_heartbeatAlive = false;

    bool m_connected = false;
    bool m_armed = false;
    bool m_lastArmedState = false;
    int m_vehicleType = 0;
    uint m_flightMode = 0;

    double m_latitude = 0, m_longitude = 0;
    float m_altitude = 0, m_relativeAltitude = 0, m_heading = 0;
    float m_roll = 0, m_pitch = 0, m_yaw = 0;

    int m_gpsFixType = 0, m_gpsSatellites = 0;
    float m_gpsHdop = 99.99f;
    QVariantMap m_gpsRaw;
    int m_gpsMessageCount = 0;
    QList<qint64> m_gpsRawTimestamps;
    uint m_sensorsPresent = 0, m_sensorsEnabled = 0, m_sensorsHealth = 0;
    bool m_sysStatusReceived = false;

    float m_groundSpeed = 0, m_climbRate = 0, m_pressure = 0, m_temperature = 0;
    float m_displayAltitude = 0, m_displaySpeed = 0;
    bool m_usingGpsSource = false;

    // source-selected telemetry internals
    quint8 m_currentFixType = 0;
    float m_gpsAltitudeMsl = 0;
    bool m_hasGpsAltRef = false;
    float m_gpsAltRef = 0;
    float m_baroAltitude = 0;
    bool m_hasBaroAltRef = false;
    float m_baroAltRef = 0;
    float m_imuVx = 0, m_imuVy = 0;
    bool m_hasLastImuTime = false;
    quint32 m_lastImuTimeMs = 0;
    float m_attRollRad = 0, m_attPitchRad = 0, m_attYawRad = 0;

    float m_batteryVoltage = 0, m_batteryCurrent = 0;
    int m_batteryRemaining = 0;

    QVariantList m_servoValues;

    ParameterModel m_parameters;
    int m_paramTotalCount = 0;
    bool m_paramDownloading = false;
    bool m_restoreInProgress = false;
    int m_restoreProgress = 0, m_restoreTotal = 0;
    int m_restoreIndex = 0;
    QTimer m_restoreTimer;

    MessagesModel m_messages;
    int m_ekfFlags = 0;
    float m_ekfVelocityVariance = 0, m_ekfPosHorizVariance = 0, m_ekfCompassVariance = 0;
    bool m_ekfReportReceived = false;

    QString m_motorTestAckText;
    int m_motorTestAckAccepted = -1;
    bool m_motorTestActive = false;
    QTimer m_motorTestClearTimer;

    QMap<int, QVariantMap> m_magCalProgress;
    QMap<int, QVariantMap> m_magCalReports;
    bool m_magCalRunning = false;
    QString m_magCalStartAck, m_magCalAcceptAck;
    bool m_magCalSaved = false;
    bool m_magCalAcceptSent = false;
    bool m_magCalAutoAccept = true;

    QVariantMap m_gyroCalState, m_baroCalState;
    QString m_pendingPreflightCal;
};
