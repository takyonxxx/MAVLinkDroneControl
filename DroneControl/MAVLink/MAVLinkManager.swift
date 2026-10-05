//
//  MAVLinkManager.swift
//  DroneControl
//

import Foundation
import Combine

// MARK: - VehicleMessage (STATUSTEXT kaydi)
struct VehicleMessage: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let severity: UInt8      // MAV_SEVERITY: 0=Emergency ... 7=Debug
    let text: String
    
    var severityName: String {
        switch severity {
        case 0: return "EMERGENCY"
        case 1: return "ALERT"
        case 2: return "CRITICAL"
        case 3: return "ERROR"
        case 4: return "WARNING"
        case 5: return "NOTICE"
        case 6: return "INFO"
        default: return "DEBUG"
        }
    }
}

// MARK: - GPSRawData (GPS_RAW_INT ham verisi + alis istatistigi)
struct GPSRawData {
    var received: Bool = false
    var messageCount: Int = 0
    var lastReceived: Date? = nil
    var rateHz: Float = 0            // olculen mesaj frekansi
    
    var timeUsec: UInt64 = 0         // GPS zamani (us, epoch) - 0 = yok
    var fixType: UInt8 = 0
    var lat: Int32 = 0               // degE7
    var lon: Int32 = 0               // degE7
    var alt: Int32 = 0               // mm MSL
    var eph: UInt16 = UInt16.max     // HDOP*100
    var epv: UInt16 = UInt16.max     // VDOP*100
    var vel: UInt16 = UInt16.max     // cm/s
    var cog: UInt16 = UInt16.max     // cdeg
    var satellitesVisible: UInt8 = 255
    var altEllipsoid: Int32 = 0      // mm
    var hAcc: UInt32 = 0             // mm
    var vAcc: UInt32 = 0             // mm
    var velAcc: UInt32 = 0           // mm/s
    var hdgAcc: UInt32 = 0           // degE5
    var yaw: UInt16 = 0              // cdeg, 0 = yok
    
    var fixName: String {
        switch fixType {
        case 0: return "NO GPS"
        case 1: return "NO FIX"
        case 2: return "2D FIX"
        case 3: return "3D FIX"
        case 4: return "DGPS"
        case 5: return "RTK FLOAT"
        case 6: return "RTK FIXED"
        case 7: return "STATIC"
        case 8: return "PPP"
        default: return "UNKNOWN (\(fixType))"
        }
    }
}

// MARK: - Kalibrasyon veri yapilari
struct MagCalProgressData: Equatable {
    let compassId: UInt8
    let calMask: UInt8
    let status: UInt8            // MAG_CAL_STATUS
    let attempt: UInt8
    let completionPct: UInt8
    let completionMask: [UInt8]  // 10 byte = 80 geodesic bolum biti
    let directionX: Float
    let directionY: Float
    let directionZ: Float
    let received: Date
    
    var statusName: String { MagCalStatusName.name(status) }
    /// completion_mask icinde set edilmis bolum sayisi (0-80)
    var sectionsDone: Int { completionMask.reduce(0) { $0 + $1.nonzeroBitCount } }
}

struct MagCalReportData: Equatable {
    let compassId: UInt8
    let calMask: UInt8
    let status: UInt8
    let autosaved: Bool
    let fitness: Float           // RMS mgauss residual - dusuk = iyi
    let ofsX: Float, ofsY: Float, ofsZ: Float
    let diagX: Float, diagY: Float, diagZ: Float
    let offdiagX: Float, offdiagY: Float, offdiagZ: Float
    let orientationConfidence: Float
    let oldOrientation: UInt8
    let newOrientation: UInt8
    let scaleFactor: Float
    let received: Date
    
    var statusName: String { MagCalStatusName.name(status) }
    var success: Bool { status == 4 }   // MAG_CAL_SUCCESS
    /// Mission Planner ile ayni esik mantigi: fitness kucuk = iyi
    var qualityText: String {
        switch fitness {
        case ..<5:  return "Excellent"
        case ..<10: return "Good"
        case ..<20: return "Acceptable"
        case ..<40: return "Poor"
        default:    return "Bad"
        }
    }
}

enum MagCalStatusName {
    static func name(_ s: UInt8) -> String {
        switch s {
        case 0: return "NOT STARTED"
        case 1: return "WAITING TO START"
        case 2: return "RUNNING (step 1)"
        case 3: return "RUNNING (step 2)"
        case 4: return "SUCCESS"
        case 5: return "FAILED"
        case 6: return "BAD ORIENTATION"
        case 7: return "BAD RADIUS"
        default: return "UNKNOWN (\(s))"
        }
    }
}

/// Gyro / baro gibi tek adimlik kalibrasyonlarin durumu
enum SimpleCalState: Equatable {
    case idle
    case inProgress(Date)
    case success(String)
    case failed(String)
}

// MARK: - CopterFlightMode
enum CopterFlightMode: UInt32 {
    case stabilize = 0
    case acro = 1
    case altHold = 2
    case auto = 3
    case guided = 4
    case loiter = 5
    case rtl = 6
    case circle = 7
    case land = 9
    case drift = 11
    case sport = 13
    case flip = 14
    case autotune = 15
    case posHold = 16
    case brake = 17
    case throw_ = 18
    case avoidADSB = 19
    case guidedNoGPS = 20
    case smartRTL = 21
    case flowHold = 22
    case follow = 23
    case zigzag = 24
    case systemID = 25
    case autorotate = 26
    case autoRTL = 27
    
    var name: String {
        switch self {
        case .stabilize: return "Stabilize"
        case .acro: return "Acro"
        case .altHold: return "Alt Hold"
        case .auto: return "Auto"
        case .guided: return "Guided"
        case .loiter: return "Loiter"
        case .rtl: return "RTL"
        case .circle: return "Circle"
        case .land: return "Land"
        case .drift: return "Drift"
        case .sport: return "Sport"
        case .flip: return "Flip"
        case .autotune: return "Autotune"
        case .posHold: return "Pos Hold"
        case .brake: return "Brake"
        case .throw_: return "Throw"
        case .avoidADSB: return "Avoid ADSB"
        case .guidedNoGPS: return "Guided NoGPS"
        case .smartRTL: return "Smart RTL"
        case .flowHold: return "Flow Hold"
        case .follow: return "Follow"
        case .zigzag: return "ZigZag"
        case .systemID: return "System ID"
        case .autorotate: return "Autorotate"
        case .autoRTL: return "Auto RTL"
        }
    }
    
    var icon: String {
        switch self {
        case .stabilize: return "level"
        case .acro: return "gyroscope"
        case .altHold: return "arrow.up.and.down"
        case .auto: return "arrow.triangle.2.circlepath"
        case .guided: return "location.circle"
        case .loiter: return "circle.dashed"
        case .rtl: return "house.fill"
        case .circle: return "circle"
        case .land: return "arrow.down.circle.fill"
        case .drift: return "wind"
        case .sport: return "figure.run"
        case .flip: return "arrow.triangle.swap"
        case .autotune: return "slider.horizontal.3"
        case .posHold: return "location.fill"
        case .brake: return "exclamationmark.octagon.fill"
        case .throw_: return "arrow.up.forward"
        case .avoidADSB: return "exclamationmark.triangle.fill"
        case .guidedNoGPS: return "location.slash"
        case .smartRTL: return "house.circle"
        case .flowHold: return "wind.circle"
        case .follow: return "person.fill"
        case .zigzag: return "triangle.fill"
        case .systemID: return "square.grid.2x2"
        case .autorotate: return "arrow.triangle.2.circlepath.circle"
        case .autoRTL: return "house.and.flag"
        }
    }
    
    var color: Color {
        switch self {
        case .stabilize: return .green
        case .acro: return .orange
        case .altHold: return .blue
        case .auto: return .purple
        case .guided: return .cyan
        case .loiter: return .indigo
        case .rtl: return .red
        case .circle: return .teal
        case .land: return .brown
        case .drift: return .mint
        case .sport: return .yellow
        case .flip: return .pink
        case .autotune: return .orange
        case .posHold: return .green
        case .brake: return .red
        case .throw_: return .orange
        case .avoidADSB: return .yellow
        case .guidedNoGPS: return .gray
        case .smartRTL: return .purple
        case .flowHold: return .cyan
        case .follow: return .blue
        case .zigzag: return .indigo
        case .systemID: return .gray
        case .autorotate: return .orange
        case .autoRTL: return .red
        }
    }
}

// MARK: - DroneState
struct DroneState {
    var isConnected: Bool = false
    var isArmed: Bool = false
    var flightMode: CopterFlightMode = .stabilize
    var roll: Float = 0.0
    var pitch: Float = 0.0
    var yaw: Float = 0.0
    var heading: Float = 0.0
    var latitude: Double = 0.0
    var longitude: Double = 0.0
    var altitude: Float = 0.0
    var relativeAltitude: Float = 0.0
    var batteryVoltage: Float = 0.0
    var batteryCurrent: Float = 0.0
    var batteryRemaining: Int = 0
    var gpsFixType: Int = 0
    var gpsSatellites: Int = 0
}

// MARK: - Color Extension
import SwiftUI
extension Color {
    init(red: Double, green: Double, blue: Double) {
        self.init(red: red, green: green, blue: blue, opacity: 1.0)
    }
}

// MARK: - MAVLinkManager
class MAVLinkManager: ObservableObject, MAVLinkMessageHandler {
    
    static let shared = MAVLinkManager()
    
    @Published var isConnected: Bool = false
    @Published var isArmed: Bool = false
    @Published var vehicleType: UInt8 = 0
    @Published var droneState = DroneState()
    
    @Published var latitude: Double = 0.0
    @Published var longitude: Double = 0.0
    @Published var altitude: Float = 0.0          // MSL (deniz seviyesinden)
    @Published var relativeAltitude: Float = 0.0  // AGL (yerden / home'a gore)
    @Published var heading: Float = 0.0
    @Published var roll: Float = 0.0
    @Published var pitch: Float = 0.0
    @Published var yaw: Float = 0.0
    
    @Published var gpsFixType: UInt8 = 0
    @Published var gpsSatellites: UInt8 = 0
    @Published var gpsHdop: Float = 99.99          // GPS_RAW_INT.eph / 100 (99.99 = gecersiz)
    @Published var gpsRaw = GPSRawData()           // GPS sekmesi icin ham GPS_RAW_INT
    private var gpsRawTimestamps: [Date] = []      // frekans olcumu icin son mesaj zamanlari
    
    // SYS_STATUS sensor bitleri (MAV_SYS_STATUS_SENSOR_*) - GPS fiziksel olarak var mi?
    @Published var sensorsPresent: UInt32 = 0
    @Published var sensorsEnabled: UInt32 = 0
    @Published var sensorsHealth: UInt32 = 0
    @Published var sysStatusReceived: Bool = false
    
    @Published var groundSpeed: Float = 0.0
    @Published var climbRate: Float = 0.0
    @Published var pressure: Float = 0.0
    @Published var temperature: Float = 0.0
    
    @Published var servoValues: [Int: UInt16] = [:]
    
    @Published var parameters: [String: Float] = [:]
    @Published var paramTotalCount: Int = 0        // FC'nin bildirdigi toplam parametre sayisi
    @Published var paramDownloading: Bool = false
    
    // Vehicle messages (STATUSTEXT) + EKF status
    @Published var statusMessages: [VehicleMessage] = []
    @Published var ekfFlags: UInt16 = 0
    @Published var ekfVelocityVariance: Float = 0
    @Published var ekfPosHorizVariance: Float = 0
    @Published var ekfCompassVariance: Float = 0
    @Published var ekfReportReceived: Bool = false
    
    @Published var batteryVoltage: Float = 0.0
    @Published var batteryCurrent: Float = 0.0
    @Published var batteryRemaining: Int = 0
    
    // Source-selected telemetry (GPS fix -> GPS; no fix -> baro altitude + IMU speed)
    @Published var displayAltitude: Float = 0.0   // AGL, m
    @Published var displaySpeed: Float = 0.0      // m/s
    @Published var isUsingGPSSource: Bool = false
    
    // GPS-derived values (GPS_RAW_INT)
    private var currentFixType: UInt8 = 0         // sync copy for handler-thread decisions
    private var gpsAltitudeMSL: Float = 0.0
    private var gpsAltRef: Float? = nil           // ground reference (MSL) for GPS AGL
    
    // Barometric altitude (SCALED_PRESSURE)
    private var baroAltitude: Float = 0.0         // ISA altitude from press_abs
    private var baroAltRef: Float? = nil          // ground reference for baro AGL
    
    // IMU dead-reckoning velocity (SCALED_IMU, earth-frame horizontal)
    private var imuVx: Float = 0.0
    private var imuVy: Float = 0.0
    private var lastImuTimeMs: UInt32? = nil
    private var attitudeRollRad: Float = 0.0
    private var attitudePitchRad: Float = 0.0
    private var attitudeYawRad: Float = 0.0
    private var lastArmedState: Bool = false
    
    private let udpConnection: UDPConnection
    private let mavlinkProtocol: MAVLinkProtocol
    
    private let systemID: UInt8 = 255
    private let componentID: UInt8 = 190
    var targetSystemID: UInt8 = 1
    var targetComponentID: UInt8 = 1
    
    private var heartbeatTimer: Timer?
    private var lastHeartbeatTime: Date?
    private let heartbeatInterval: TimeInterval = 0.5
    
    private var connectionWatchdogTimer: Timer?
    private let connectionTimeout: TimeInterval = 5.0
    
    // Voltaja dayali sarj senkronu. BATT_MONITOR=4 iken ArduPilot boot'tan beri
    // harcanan mAh'i sayar ve pili dolu varsayar. Her baglantida bir kez, disarmed
    // ve yuksuzken dinlenme voltajindan % tahmin edilip MAV_CMD_BATTERY_RESET ile
    // FC'ye yazilir; boylece hem % hem de mAh failsafe'leri dogru baslar.
    // (Yalnizca main thread'de kullanilir.)
    private var socSyncDone = false
    private var socSyncSamples = 0
    private var socSyncVoltSum: Float = 0
    private var socSyncWaitStart: Date?
    
    init(host: String = "192.168.4.1", port: UInt16 = 14550, localPort: UInt16 = 14550) {
        self.udpConnection = UDPConnection(host: host, port: port, localPort: localPort)
        self.mavlinkProtocol = MAVLinkProtocol()
        
        mavlinkProtocol.messageHandler = self
        mavlinkProtocol.onMessageReceived = { [weak self] msgId in
            self?.noteStreamMessage(msgId)
        }
        
        udpConnection.onDataReceived = { [weak self] data in
            self?.mavlinkProtocol.parseData(data)
        }
        
        udpConnection.onConnectionStatusChanged = { [weak self] connected in
            DispatchQueue.main.async {
                self?.isConnected = connected
                self?.droneState.isConnected = connected
                if !connected { self?.resetBatterySocSync() }
            }
        }
    }
    
    func connect() {
        udpConnection.connect()
        startHeartbeat()
        startConnectionWatchdog()
        
        // Request specific messages after connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.requestTelemetryMessages()
        }
    }
    
    // Message ID -> Rate in microseconds (1000000 = 1Hz, 250000 = 4Hz, 100000 = 10Hz)
    private static let telemetryStreams: [(UInt32, Int32)] = [
        (1, 500000),    // SYS_STATUS at 2Hz
        (24, 200000),   // GPS_RAW_INT at 5Hz
        (30, 100000),   // ATTITUDE at 10Hz
        (33, 200000),   // GLOBAL_POSITION_INT at 5Hz
        (36, 100000),   // SERVO_OUTPUT_RAW at 10Hz - ÖNEMLİ!
        (74, 200000),   // VFR_HUD at 5Hz
        (29, 500000),   // SCALED_PRESSURE at 2Hz
        (26, 100000),   // SCALED_IMU at 10Hz (IMU dead-reckoning speed)
        (193, 500000),  // EKF_STATUS_REPORT at 2Hz (Messages sekmesi icin)
    ]
    
    private func requestTelemetryMessages() {
        print("📡 Requesting telemetry messages...")
        let now = Date()
        streamLock.lock()
        for (msgId, _) in Self.telemetryStreams { streamLastRequest[msgId] = now }
        streamLock.unlock()
        for (msgId, intervalUs) in Self.telemetryStreams {
            setMessageInterval(messageId: msgId, intervalUs: intervalUs)
        }
    }
    
    // MARK: - Telemetry stream keeper
    //
    // SET_MESSAGE_INTERVAL istekleri FC'de RAM'de tutulur: FC reboot olursa (pil takip-cikarma,
    // parametre sonrasi reboot, brown-out) veya istek UDP'de kaybolursa akis durur ve bir daha
    // istenmezdi. FC heartbeat gonderirken istenen bir mesaj susarsa istek yeniden gonderilir.
    
    private let streamLock = NSLock()
    private var streamLastRx: [UInt32: Date] = [:]
    private var streamLastRequest: [UInt32: Date] = [:]
    private var streamAttempts: [UInt32: Int] = [:]          // veri gelmeden ust uste deneme
    @Published var streamRerequestCount: [UInt32: Int] = [:]  // tanilama (GPS sekmesi)
    @Published var lastHeartbeatDate: Date? = nil             // tanilama: FC hayatta mi
    
    /// MAVLinkProtocol alici thread'inden cagrilir.
    private func noteStreamMessage(_ msgId: UInt32) {
        streamLock.lock()
        streamLastRx[msgId] = Date()
        streamAttempts[msgId] = 0
        streamLock.unlock()
    }
    
    /// Watchdog'dan (main, 1 Hz) cagrilir.
    private func checkTelemetryStreams() {
        // FC hayatta degilse istemenin anlami yok (link kopuk / FC kapali)
        guard let hb = lastHeartbeatTime, Date().timeIntervalSince(hb) < 3.0 else { return }
        let now = Date()
        var resend: [(UInt32, Int32)] = []
        streamLock.lock()
        for (msgId, intervalUs) in Self.telemetryStreams {
            let silentLimit = max(3.0, 4.0 * Double(intervalUs) / 1_000_000)
            let silent = streamLastRx[msgId].map { now.timeIntervalSince($0) > silentLimit } ?? true
            guard silent else { continue }
            // Desteklenmeyen mesajlar icin sonsuz spam yapma: 5 denemeden sonra 15 s'de bir
            let attempts = streamAttempts[msgId] ?? 0
            let retryAfter: TimeInterval = attempts < 5 ? 3.0 : 15.0
            if now.timeIntervalSince(streamLastRequest[msgId] ?? .distantPast) > retryAfter {
                streamLastRequest[msgId] = now
                streamAttempts[msgId] = attempts + 1
                resend.append((msgId, intervalUs))
            }
        }
        streamLock.unlock()
        
        for (msgId, intervalUs) in resend {
            print("[STREAM] \(MAVLinkProtocol.messageIDToName(msgId)) silent - re-requesting \(1_000_000 / Int(intervalUs)) Hz")
            setMessageInterval(messageId: msgId, intervalUs: intervalUs)
            streamRerequestCount[msgId, default: 0] += 1
        }
    }
    
    private func setMessageInterval(messageId: UInt32, intervalUs: Int32) {
        var msg = mavlink_message_t()
        var cmd = mavlink_command_long_t()
        
        cmd.target_system = targetSystemID
        cmd.target_component = targetComponentID
        cmd.command = UInt16(MAV_CMD_SET_MESSAGE_INTERVAL.rawValue)
        cmd.confirmation = 0
        cmd.param1 = Float(messageId)
        cmd.param2 = Float(intervalUs)
        cmd.param3 = 0
        cmd.param4 = 0
        cmd.param5 = 0
        cmd.param6 = 0
        cmd.param7 = 0
        
        mavlink_msg_command_long_encode(systemID, componentID, &msg, &cmd)
        sendMessage(msg)
    }
    
    func disconnect() {
        stopHeartbeat()
        stopConnectionWatchdog()
        udpConnection.disconnect()
    }
    
    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
        print("💓 Heartbeat timer started (\(heartbeatInterval * 1000)ms)")
    }
    
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    private func startConnectionWatchdog() {
        connectionWatchdogTimer?.invalidate()
        connectionWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.checkTelemetryStreams()
            if self.lastHeartbeatDate != self.lastHeartbeatTime {
                self.lastHeartbeatDate = self.lastHeartbeatTime
            }
            if let lastTime = self.lastHeartbeatTime {
                let elapsed = Date().timeIntervalSince(lastTime)
                if elapsed > self.connectionTimeout {
                    print("⚠️ Connection timeout - no heartbeat for \(elapsed)s")
                    // Muhtemel pil degisimi / FC reboot: sonraki pilde tekrar kontrol et
                    self.resetBatterySocSync()
                }
            }
        }
    }
    
    private func stopConnectionWatchdog() {
        connectionWatchdogTimer?.invalidate()
        connectionWatchdogTimer = nil
    }
    
    private func sendHeartbeat() {
        var msg = mavlink_message_t()
        
        mavlink_msg_heartbeat_pack(
            systemID,
            componentID,
            &msg,
            UInt8(MAV_TYPE_GCS.rawValue),
            UInt8(MAV_AUTOPILOT_INVALID.rawValue),
            0, 0, 0
        )
        
        sendMessage(msg)
    }
    
    private func sendMessage(_ message: mavlink_message_t) {
        var msg = message
        var buffer = [UInt8](repeating: 0, count: 280)
        
        let len = mavlink_msg_to_send_buffer(&buffer, &msg)
        let data = Data(bytes: buffer, count: Int(len))
        
        udpConnection.send(data)
    }
    
    // MARK: - Commands
    
    func armVehicle(force: Bool = false) {
        print("🔓 Arming vehicle...")
        var msg = mavlink_message_t()
        var cmd = mavlink_command_long_t()
        
        cmd.target_system = targetSystemID
        cmd.target_component = targetComponentID
        cmd.command = UInt16(MAV_CMD_COMPONENT_ARM_DISARM.rawValue)
        cmd.confirmation = 0
        cmd.param1 = 1.0
        cmd.param2 = force ? 21196.0 : 0.0
        cmd.param3 = 0
        cmd.param4 = 0
        cmd.param5 = 0
        cmd.param6 = 0
        cmd.param7 = 0
        
        mavlink_msg_command_long_encode(systemID, componentID, &msg, &cmd)
        sendMessage(msg)
    }
    
    func disarmVehicle(force: Bool = false) {
        print("🔒 Disarming vehicle...")
        var msg = mavlink_message_t()
        var cmd = mavlink_command_long_t()
        
        cmd.target_system = targetSystemID
        cmd.target_component = targetComponentID
        cmd.command = UInt16(MAV_CMD_COMPONENT_ARM_DISARM.rawValue)
        cmd.confirmation = 0
        cmd.param1 = 0.0
        cmd.param2 = force ? 21196.0 : 0.0
        cmd.param3 = 0
        cmd.param4 = 0
        cmd.param5 = 0
        cmd.param6 = 0
        cmd.param7 = 0
        
        mavlink_msg_command_long_encode(systemID, componentID, &msg, &cmd)
        sendMessage(msg)
    }
    
    // Convenience methods for gamepad
    func arm() {
        armVehicle(force: true)
    }
    
    func disarm() {
        disarmVehicle(force: true)
    }
    
    func setMode(customMode: UInt32) {
        print("✈️ Setting mode: \(customMode)")
        var msg = mavlink_message_t()
        var setMode = mavlink_set_mode_t()
        
        setMode.target_system = targetSystemID
        setMode.base_mode = UInt8(MAV_MODE_FLAG_CUSTOM_MODE_ENABLED.rawValue)
        setMode.custom_mode = customMode
        
        mavlink_msg_set_mode_encode(systemID, componentID, &msg, &setMode)
        sendMessage(msg)
    }
    
    func setFlightMode(_ mode: CopterFlightMode) {
        setMode(customMode: mode.rawValue)
    }
    
    func setFlightMode(_ customMode: UInt32) {
        setMode(customMode: customMode)
    }
    
    func sendManualControl(x: Int16, y: Int16, z: Int16, r: Int16,
                          buttons: UInt16 = 0, buttons2: UInt16 = 0,
                          enabledExtensions: UInt8 = 0,
                          s: Int16 = 0, t: Int16 = 0,
                          aux1: Int16 = 0, aux2: Int16 = 0, aux3: Int16 = 0,
                          aux4: Int16 = 0, aux5: Int16 = 0, aux6: Int16 = 0) {
        var msg = mavlink_message_t()
        var manualControl = mavlink_manual_control_t()
        
        manualControl.target = targetSystemID
        manualControl.x = x
        manualControl.y = y
        manualControl.z = z
        manualControl.r = r
        manualControl.buttons = buttons
        manualControl.buttons2 = buttons2
        manualControl.enabled_extensions = enabledExtensions
        manualControl.s = s
        manualControl.t = t
        manualControl.aux1 = aux1
        manualControl.aux2 = aux2
        manualControl.aux3 = aux3
        manualControl.aux4 = aux4
        manualControl.aux5 = aux5
        manualControl.aux6 = aux6
        
        mavlink_msg_manual_control_encode(systemID, componentID, &msg, &manualControl)
        sendMessage(msg)
    }
    
    func setServo(channel: UInt8, pwm: UInt16) {
        print("🔧 Setting servo \(channel) to \(pwm)")
        var msg = mavlink_message_t()
        var cmd = mavlink_command_long_t()
        
        cmd.target_system = targetSystemID
        cmd.target_component = targetComponentID
        cmd.command = UInt16(MAV_CMD_DO_SET_SERVO.rawValue)
        cmd.confirmation = 0
        cmd.param1 = Float(channel)
        cmd.param2 = Float(pwm)
        cmd.param3 = 0
        cmd.param4 = 0
        cmd.param5 = 0
        cmd.param6 = 0
        cmd.param7 = 0
        
        mavlink_msg_command_long_encode(systemID, componentID, &msg, &cmd)
        sendMessage(msg)
    }
    
    // MARK: - Motor Test (MAV_CMD_DO_MOTOR_TEST)
    
    /// Son motor test komutunun ACK sonucu (UI icin)
    @Published var motorTestAckText: String = ""
    @Published var motorTestAckAccepted: Bool? = nil
    /// Motor testi bizim tarafimizdan baslatildi mi. ArduCopter motor testi sirasinda
    /// motorlari kendi icinde ARM eder ve HEARTBEAT'te SAFETY_ARMED bayragini kaldirir;
    /// bu "gercek" bir arm degildir, UI bunu ayirt etmek icin bu bayragi kullanir.
    @Published var motorTestActive: Bool = false
    private var motorTestClearWork: DispatchWorkItem? = nil
    
    /// Pilot tarafindan yapilmis gercek arm (motor testi sirasindaki ic arm haric)
    var isArmedByPilot: Bool { isArmed && !motorTestActive }
    
    // MARK: - Kalibrasyon durumu
    @Published var magCalProgress: [UInt8: MagCalProgressData] = [:]   // compass_id -> ilerleme
    @Published var magCalReports: [UInt8: MagCalReportData] = [:]      // compass_id -> sonuc
    @Published var magCalRunning: Bool = false
    @Published var magCalStartAck: String? = nil       // DO_START_MAG_CAL ACK
    @Published var magCalAcceptAck: String? = nil      // DO_ACCEPT_MAG_CAL ACK (= parametrelere yazildi)
    @Published var magCalSaved: Bool = false
    private var magCalAcceptSent: Bool = false
    private var magCalAutoAccept: Bool = true
    
    @Published var gyroCalState: SimpleCalState = .idle
    @Published var baroCalState: SimpleCalState = .idle
    private var pendingPreflightCal: String? = nil     // "gyro" | "baro" - ACK eslestirmesi icin
    
    /// ArduCopter motor testi. motorSeq = ArduPilot test sirasi (A=1, B=2, C=3, D=4;
    /// on sagdan baslayip saat yonunde), MOTOR_x cikis numarasi DEGIL.
    /// Quad X: M1 on sag -> seq 1, M4 arka sag -> seq 2, M2 arka sol -> seq 3, M3 on sol -> seq 4.
    /// Throttle tipi PWM (MOTOR_TEST_THROTTLE_PWM), timeout saniye. timeout 0 = hemen durdur.
    func motorTest(motorSeq: UInt8, pwm: UInt16, timeoutSec: Float) {
        print("[MOTOR TEST] seq=\(motorSeq) pwm=\(pwm) timeout=\(timeoutSec)s")
        var msg = mavlink_message_t()
        var cmd = mavlink_command_long_t()
        
        cmd.target_system = targetSystemID
        cmd.target_component = targetComponentID
        cmd.command = UInt16(MAV_CMD_DO_MOTOR_TEST.rawValue)
        cmd.confirmation = 0
        cmd.param1 = Float(motorSeq)                                   // motor instance (test sirasi)
        cmd.param2 = Float(MOTOR_TEST_THROTTLE_PWM.rawValue)          // throttle type = PWM
        cmd.param3 = Float(pwm)                                        // PWM (1000-2000)
        cmd.param4 = timeoutSec                                        // timeout (s)
        cmd.param5 = 0                                                 // motor count (0/1 = tek motor)
        cmd.param6 = Float(MOTOR_TEST_ORDER_DEFAULT.rawValue)         // ArduCopter param6'yi yok sayar
        cmd.param7 = 0
        
        mavlink_msg_command_long_encode(systemID, componentID, &msg, &cmd)
        sendMessage(msg)
        
        if timeoutSec > 0 {
            motorTestClearWork?.cancel()
            motorTestClearWork = nil
            DispatchQueue.main.async { self.motorTestActive = true }
        }
    }
    
    /// Calisan motor testini durdurur (min PWM, timeout 0).
    /// FC birkac heartbeat daha "armed" raporlayabilir; bayrak 2 s sonra temizlenir.
    func stopMotorTest(motorSeq: UInt8 = 1) {
        motorTest(motorSeq: motorSeq, pwm: 1000, timeoutSec: 0)
        motorTestClearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.motorTestActive = false }
        motorTestClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
    
    // MARK: - Kalibrasyon komutlari
    
    /// Pusula kalibrasyonu baslat (tum pusulalar). autoSave=false: SUCCESS sonrasi
    /// MAG_CAL_REPORT gelir, fitness gosterilir ve DO_ACCEPT_MAG_CAL ile yazilir.
    func startCompassCalibration(retryOnFailure: Bool = true, autoSave: Bool = false, autoAccept: Bool = true) {
        print("[CAL] Starting compass calibration (retry=\(retryOnFailure) autosave=\(autoSave))")
        DispatchQueue.main.async {
            self.magCalProgress = [:]
            self.magCalReports = [:]
            self.magCalRunning = true
            self.magCalStartAck = nil
            self.magCalAcceptAck = nil
            self.magCalSaved = false
        }
        magCalAcceptSent = false
        magCalAutoAccept = autoAccept
        sendCommandLong(MAV_CMD_DO_START_MAG_CAL,
                        p1: 0,                          // bitmask 0 = tum pusulalar
                        p2: retryOnFailure ? 1 : 0,     // hata durumunda tekrar dene
                        p3: autoSave ? 1 : 0,           // 0 = ACCEPT bekle
                        p4: 0,                          // gecikme (s)
                        p5: 0)                          // autoreboot
    }
    
    func cancelCompassCalibration() {
        print("[CAL] Cancel compass calibration")
        sendCommandLong(MAV_CMD_DO_CANCEL_MAG_CAL, p1: 0)
        DispatchQueue.main.async { self.magCalRunning = false }
    }
    
    /// Kalibrasyon sonucunu kabul et -> COMPASS_OFS_x vb. parametrelere yazilir
    func acceptCompassCalibration() {
        print("[CAL] Accept compass calibration (write to params)")
        magCalAcceptSent = true
        sendCommandLong(MAV_CMD_DO_ACCEPT_MAG_CAL, p1: 0)
    }
    
    /// Gyro kalibrasyonu (arac sabit durmali). ArduPilot ACK'i kalibrasyon bitince doner.
    func calibrateGyro() {
        print("[CAL] Gyro calibration")
        pendingPreflightCal = "gyro"
        DispatchQueue.main.async { self.gyroCalState = .inProgress(Date()) }
        sendCommandLong(MAV_CMD_PREFLIGHT_CALIBRATION, p1: 1)
        startPreflightCalTimeout(for: "gyro")
    }
    
    /// Barometre yer basinci kalibrasyonu (param3 = 1)
    func calibrateBarometer() {
        print("[CAL] Barometer ground pressure calibration")
        pendingPreflightCal = "baro"
        DispatchQueue.main.async { self.baroCalState = .inProgress(Date()) }
        sendCommandLong(MAV_CMD_PREFLIGHT_CALIBRATION, p3: 1)
        startPreflightCalTimeout(for: "baro")
    }
    
    /// Ucus kontrolcusunu yeniden baslat (pusula kalibrasyonu sonrasi onerilir)
    func rebootFlightController() {
        print("[CAL] Reboot flight controller")
        sendCommandLong(MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN, p1: 1)
    }
    
    private func startPreflightCalTimeout(for which: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
            guard let self = self else { return }
            if which == "gyro", case .inProgress = self.gyroCalState {
                self.gyroCalState = .failed("No ACK within 15 s")
            }
            if which == "baro", case .inProgress = self.baroCalState {
                self.baroCalState = .failed("No ACK within 15 s")
            }
        }
    }
    
    private func sendCommandLong(_ command: MAV_CMD, p1: Float = 0, p2: Float = 0, p3: Float = 0,
                                 p4: Float = 0, p5: Float = 0, p6: Float = 0, p7: Float = 0) {
        var msg = mavlink_message_t()
        var cmd = mavlink_command_long_t()
        cmd.target_system = targetSystemID
        cmd.target_component = targetComponentID
        cmd.command = UInt16(command.rawValue)
        cmd.confirmation = 0
        cmd.param1 = p1; cmd.param2 = p2; cmd.param3 = p3; cmd.param4 = p4
        cmd.param5 = p5; cmd.param6 = p6; cmd.param7 = p7
        mavlink_msg_command_long_encode(systemID, componentID, &msg, &cmd)
        sendMessage(msg)
    }
    
    // MARK: - Kalibrasyon mesajlari
    
    func handleMagCalProgress(_ m: mavlink_mag_cal_progress_t) {
        var mask = m.completion_mask
        let maskBytes: [UInt8] = withUnsafeBytes(of: &mask) { Array($0.prefix(10)) }
        let data = MagCalProgressData(
            compassId: m.compass_id, calMask: m.cal_mask, status: m.cal_status,
            attempt: m.attempt, completionPct: m.completion_pct, completionMask: maskBytes,
            directionX: m.direction_x, directionY: m.direction_y, directionZ: m.direction_z,
            received: Date())
        DispatchQueue.main.async {
            self.magCalProgress[m.compass_id] = data
            self.magCalRunning = true
        }
    }
    
    func handleMagCalReport(_ m: mavlink_mag_cal_report_t) {
        let data = MagCalReportData(
            compassId: m.compass_id, calMask: m.cal_mask, status: m.cal_status,
            autosaved: m.autosaved != 0, fitness: m.fitness,
            ofsX: m.ofs_x, ofsY: m.ofs_y, ofsZ: m.ofs_z,
            diagX: m.diag_x, diagY: m.diag_y, diagZ: m.diag_z,
            offdiagX: m.offdiag_x, offdiagY: m.offdiag_y, offdiagZ: m.offdiag_z,
            orientationConfidence: m.orientation_confidence,
            oldOrientation: m.old_orientation, newOrientation: m.new_orientation,
            scaleFactor: m.scale_factor, received: Date())
        print("[CAL] MAG_CAL_REPORT compass=\(m.compass_id) status=\(data.statusName) fitness=\(m.fitness) autosaved=\(m.autosaved)")
        
        DispatchQueue.main.async {
            self.magCalReports[m.compass_id] = data
            
            // Kalibre edilen tum pusulalar icin rapor geldi mi?
            let expected = self.magCalProgress.keys
            let allReported = expected.isEmpty || expected.allSatisfy { self.magCalReports[$0] != nil }
            let allSuccess = self.magCalReports.values.allSatisfy { $0.success }
            
            if allReported {
                self.magCalRunning = false
                if data.autosaved {
                    self.magCalSaved = true
                } else if allSuccess && self.magCalAutoAccept && !self.magCalAcceptSent {
                    // Puan goruldu, degerleri cihaza yaz
                    self.acceptCompassCalibration()
                }
            }
        }
    }
    
    func requestAllParameters() {
        print("📋 Requesting all parameters...")
        DispatchQueue.main.async {
            self.paramDownloading = true
        }
        var msg = mavlink_message_t()
        var paramRequest = mavlink_param_request_list_t()
        
        paramRequest.target_system = targetSystemID
        paramRequest.target_component = targetComponentID
        
        mavlink_msg_param_request_list_encode(systemID, componentID, &msg, &paramRequest)
        sendMessage(msg)
    }
    
    // MARK: - Bulk parameter write (Restore Defaults / Load from File)
    //
    // Sends every item ~25 ms apart (the ESP bridge must not be flooded), waits for the
    // PARAM_VALUE echo ArduPilot returns for each PARAM_SET and resends the unconfirmed
    // ones (3 passes max). Runs entirely on the main thread.
    
    struct ParamWriteFailure: Identifiable {
        let name: String
        let value: Float
        let reason: String
        var id: String { name }
    }
    
    struct ParamWriteResult {
        let source: String          // "defaults" | "file"
        let total: Int
        let ok: Int
        let failed: [ParamWriteFailure]
        let cancelled: Bool
        let error: String?
    }
    
    @Published var paramWriteInProgress: Bool = false
    @Published var paramWriteSent: Int = 0           // pass 1: gonderilen adet
    @Published var paramWriteConfirmed: Int = 0      // PARAM_VALUE ile dogrulanan adet
    @Published var paramWriteTotal: Int = 0
    @Published var paramWritePass: Int = 0
    @Published var paramWriteResult: ParamWriteResult? = nil
    
    private var writeItems: [(String, Float)] = []
    private var writeSendList: [(String, Float)] = []
    private var writePending: [String: Float] = [:]   // dogrulanmamis: isim -> beklenen deger
    private var writeEcho: [String: Float] = [:]      // beklenenden farkli gelen son deger
    private var writeIndex = 0
    private var writeSource = ""
    private var writeCancelled = false
    private var writeWaitStart = Date()
    private var writeTimer: Timer?
    
    func restoreDefaultParameters() {
        writeParameters(DefaultParameters.values, source: "defaults")
    }
    
    /// Main thread'den cagrilmali.
    func writeParameters(_ items: [(String, Float)], source: String) {
        guard !paramWriteInProgress, !items.isEmpty else { return }
        if isArmed {
            paramWriteResult = ParamWriteResult(source: source, total: items.count, ok: 0, failed: [],
                                                cancelled: false,
                                                error: "Vehicle is armed - disarm before writing parameters")
            return
        }
        writeSource = source
        writeItems = items
        writeSendList = items
        writePending = Dictionary(items, uniquingKeysWith: { _, last in last })
        writeEcho = [:]
        writeIndex = 0
        writeCancelled = false
        paramWriteSent = 0
        paramWriteConfirmed = 0
        paramWriteTotal = items.count
        paramWritePass = 1
        paramWriteResult = nil
        paramWriteInProgress = true
        print("[PARAM] Bulk write started: \(items.count) params from \(source)")
        
        writeTimer?.invalidate()
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            self?.paramWriteTick()
        }
        RunLoop.main.add(timer, forMode: .common)   // keep running while a list is scrolled
        writeTimer = timer
    }
    
    private func paramWriteTick() {
        if !isConnected {
            finishParamWrite(error: "Connection lost")
            return
        }
        if isArmed {
            finishParamWrite(error: "Vehicle was armed - write stopped")
            return
        }
        
        if writeIndex < writeSendList.count {
            let item = writeSendList[writeIndex]
            writeIndex += 1
            if writePending[item.0] != nil {             // bu arada dogrulanmis olabilir
                setParameter(name: item.0, value: item.1)
            }
            if paramWritePass == 1 { paramWriteSent = writeIndex }
            if writeIndex == writeSendList.count { writeWaitStart = Date() }
            return
        }
        
        if writePending.isEmpty {
            finishParamWrite(error: nil)
            return
        }
        if Date().timeIntervalSince(writeWaitStart) < 1.5 { return }   // son yanitlari bekle
        if paramWritePass >= 3 {
            finishParamWrite(error: nil)
            return
        }
        
        // Sonraki tur: sadece dogrulanmayanlari, orijinal sirayla tekrar gonder
        paramWritePass += 1
        writeSendList = writeItems.filter { writePending[$0.0] != nil }
        writeIndex = 0
        print("[PARAM] Pass \(paramWritePass) - resending \(writeSendList.count) unconfirmed params")
    }
    
    /// PARAM_VALUE geldiginde (main thread) cagrilir.
    private func confirmParamWrite(name: String, value: Float) {
        guard paramWriteInProgress, let expected = writePending[name] else { return }
        if ParameterFile.valuesEqual(expected, value) {
            writePending.removeValue(forKey: name)
            writeEcho.removeValue(forKey: name)
            paramWriteConfirmed += 1
        } else {
            writeEcho[name] = value
        }
    }
    
    private func finishParamWrite(error: String?) {
        writeTimer?.invalidate()
        writeTimer = nil
        paramWriteInProgress = false
        
        var failed: [ParamWriteFailure] = []
        var seen = Set<String>()
        for (name, value) in writeItems where writePending[name] != nil && !seen.contains(name) {
            seen.insert(name)
            let reason: String
            if writeCancelled || error != nil {
                reason = "not confirmed"
            } else if let echo = writeEcho[name] {
                reason = "vehicle keeps " + String(format: "%g", echo)
            } else {
                reason = "no response (unknown on this firmware or needs reboot)"
            }
            failed.append(ParamWriteFailure(name: name, value: value, reason: reason))
        }
        paramWriteResult = ParamWriteResult(source: writeSource, total: paramWriteTotal,
                                            ok: paramWriteConfirmed, failed: failed,
                                            cancelled: writeCancelled, error: error)
        print("[PARAM] Bulk write finished: \(paramWriteConfirmed)/\(paramWriteTotal) confirmed, \(failed.count) failed\(error.map { " - " + $0 } ?? "")\(writeCancelled ? " (cancelled)" : "")")
    }
    
    func cancelParamWrite() {
        guard paramWriteInProgress else { return }
        writeCancelled = true
        finishParamWrite(error: nil)
    }
    
    func clearParamWriteResult() {
        paramWriteResult = nil
    }
    
    func requestParameter(name: String) {
        guard name.count <= 16 else { return }
        
        var msg = mavlink_message_t()
        var paramRead = mavlink_param_request_read_t()
        
        paramRead.target_system = targetSystemID
        paramRead.target_component = targetComponentID
        paramRead.param_index = -1          // -1: isimle sorgula
        
        var paramID: (Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        let bytes = Array(name.utf8.prefix(16))
        withUnsafeMutableBytes(of: &paramID) { buffer in
            for (index, byte) in bytes.enumerated() {
                buffer[index] = byte
            }
        }
        paramRead.param_id = paramID
        
        mavlink_msg_param_request_read_encode(systemID, componentID, &msg, &paramRead)
        sendMessage(msg)
    }
    
    func setParameter(name: String, value: Float) {
        guard name.count <= 16 else { return }
        
        var msg = mavlink_message_t()
        var paramSet = mavlink_param_set_t()
        
        paramSet.target_system = targetSystemID
        paramSet.target_component = targetComponentID
        paramSet.param_value = value
        paramSet.param_type = UInt8(MAV_PARAM_TYPE_REAL32.rawValue)
        
        var paramID: (Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        
        let bytes = Array(name.utf8.prefix(16))
        withUnsafeMutableBytes(of: &paramID) { buffer in
            for (index, byte) in bytes.enumerated() {
                buffer[index] = byte
            }
        }
        paramSet.param_id = paramID
        
        mavlink_msg_param_set_encode(systemID, componentID, &msg, &paramSet)
        sendMessage(msg)
    }
    
    // MARK: - Message Handlers
    
    func handleHeartbeat(_ message: mavlink_heartbeat_t) {
        lastHeartbeatTime = Date()
        
        let armed = (message.base_mode & UInt8(MAV_MODE_FLAG_SAFETY_ARMED.rawValue)) != 0
        let customMode = message.custom_mode
        let type = message.type
        
        // Arm oldugu anda yer referanslarini yakala (AGL sifir noktasi) ve IMU hizini sifirla
        if armed && !lastArmedState {
            gpsAltRef = currentFixType >= 3 ? gpsAltitudeMSL : nil
            baroAltRef = baroAltitude != 0 ? baroAltitude : nil
            imuVx = 0.0
            imuVy = 0.0
            print("Ground reference captured (arm): gpsRef=\(gpsAltRef.map { String(format: "%.1f", $0) } ?? "nil") baroRef=\(baroAltRef.map { String(format: "%.1f", $0) } ?? "nil")")
        }
        lastArmedState = armed
        
        DispatchQueue.main.async {
            if self.isArmed != armed {
                print("💓 Armed state changed: \(armed)")
            }
            self.isArmed = armed
            self.vehicleType = type
            
            self.droneState.isArmed = armed
            
            if let mode = CopterFlightMode(rawValue: customMode) {
                self.droneState.flightMode = mode
            }
        }
    }
    
    func handleSysStatus(_ message: mavlink_sys_status_t) {
        let voltage = Float(message.voltage_battery) / 1000.0
        let current = Float(message.current_battery) / 100.0
        let remaining = Int(message.battery_remaining)
        
        let isFirstUpdate = self.batteryVoltage == 0
        let voltageChanged = abs(voltage - self.batteryVoltage) > 0.5
        let remainingChanged = abs(remaining - self.batteryRemaining) > 10
        
        let present = message.onboard_control_sensors_present
        let enabled = message.onboard_control_sensors_enabled
        let health = message.onboard_control_sensors_health
        
        DispatchQueue.main.async {
            self.sensorsPresent = present
            self.sensorsEnabled = enabled
            self.sensorsHealth = health
            self.sysStatusReceived = true
            
            self.batteryVoltage = voltage
            self.batteryCurrent = current
            self.batteryRemaining = remaining
            
            self.droneState.batteryVoltage = voltage
            self.droneState.batteryCurrent = current
            self.droneState.batteryRemaining = remaining
            
            self.checkBatterySocSync(voltage: voltage, current: current, remaining: remaining)
        }
        
        if isFirstUpdate || voltageChanged || remainingChanged {
            print("🔋 Battery: \(String(format: "%.2f", voltage))V, \(String(format: "%.2f", current))A, \(remaining)%")
        }
    }
    
    // MARK: - Battery SoC sync
    
    /// Yuksuz (dinlenme) LiPo hucre voltaji -> yaklasik % sarj
    private static func lipoRestingPercent(_ v: Float) -> Int {
        let table: [(Float, Float)] = [
            (3.30, 0),  (3.69, 10), (3.73, 20), (3.77, 30), (3.80, 40), (3.84, 50),
            (3.87, 60), (3.95, 70), (4.02, 80), (4.11, 90), (4.20, 100),
        ]
        if v <= table[0].0 { return 0 }
        if v >= table[table.count - 1].0 { return 100 }
        for i in 1..<table.count where v <= table[i].0 {
            let (v0, p0) = table[i - 1]
            let (v1, p1) = table[i]
            return Int((p0 + (v - v0) / (v1 - v0) * (p1 - p0)).rounded())
        }
        return 100
    }
    
    private func resetBatterySocSync() {
        socSyncDone = false
        socSyncSamples = 0
        socSyncVoltSum = 0
        socSyncWaitStart = nil
    }
    
    /// Main thread'de cagrilir (isArmed / parameters main'de guncellenir).
    private func checkBatterySocSync(voltage: Float, current: Float, remaining: Int) {
        if socSyncDone { return }
        
        // Yalnizca dinlenen, yuksuz pil anlamli voltaj verir
        if isArmed || voltage < 5.0 || abs(current) > 1.5 {
            socSyncSamples = 0
            socSyncVoltSum = 0
            return
        }
        
        socSyncVoltSum += voltage
        socSyncSamples += 1
        if socSyncSamples < 6 { return }      // SYS_STATUS @ 2 Hz -> ~3 s ortalama
        
        // Hucre sayisi: MOT_BAT_VOLT_MAX'ten (12.6 -> 3S). Parametre inmesi icin
        // 10 s bekle, gelmezse voltajdan tahmin et.
        let cells: Int
        if let vMax = parameters["MOT_BAT_VOLT_MAX"], vMax > 1.0 {
            cells = Int((vMax / 4.2).rounded())
        } else {
            if socSyncWaitStart == nil { socSyncWaitStart = Date() }
            if Date().timeIntervalSince(socSyncWaitStart!) < 10 {
                socSyncSamples = 0
                socSyncVoltSum = 0
                return
            }
            cells = Int((voltage / 4.25).rounded(.up))
        }
        guard (1...14).contains(cells) else {
            socSyncDone = true
            return
        }
        
        let avgV = socSyncVoltSum / Float(socSyncSamples)
        let estimate = Self.lipoRestingPercent(avgV / Float(cells))
        socSyncDone = true
        
        print("🔋 SoC check: \(String(format: "%.2f", avgV))V, \(cells)S, \(String(format: "%.3f", avgV / Float(cells)))V/cell -> ~\(estimate)% (FC: \(remaining)%)")
        
        if remaining >= 0 && abs(remaining - estimate) <= 10 { return }   // FC zaten yakin
        
        print("🔋 Sending BATTERY_RESET -> \(estimate)%")
        sendCommandLong(MAV_CMD_BATTERY_RESET, p1: 1 /* battery 1 */, p2: Float(estimate))
    }
    
    func handleGlobalPositionInt(_ message: mavlink_global_position_int_t) {
        let lat = Double(message.lat) / 1e7
        let lon = Double(message.lon) / 1e7
        let alt = Float(message.alt) / 1000.0
        let relAlt = Float(message.relative_alt) / 1000.0
        let hdg = Float(message.hdg) / 100.0
        
        DispatchQueue.main.async {
            self.latitude = lat
            self.longitude = lon
            self.altitude = alt
            self.relativeAltitude = relAlt
            self.heading = hdg
            
            self.droneState.latitude = lat
            self.droneState.longitude = lon
            self.droneState.altitude = alt
            self.droneState.relativeAltitude = relAlt
            self.droneState.heading = hdg
        }
        
        // Only log if we have valid GPS coordinates (not 0,0)
        // Silent update for invalid GPS
    }
    
    func handleGPSRawInt(_ message: mavlink_gps_raw_int_t) {
        let fixType = message.fix_type
        let satellites = message.satellites_visible
        
        let isFirstUpdate = self.gpsFixType == 0
        let fixChanged = fixType != self.gpsFixType
        let satCountChanged = abs(Int(satellites) - Int(self.gpsSatellites)) > 2
        
        currentFixType = fixType
        
        var gpsSpeed: Float? = nil
        var gpsAgl: Float? = nil
        
        if fixType >= 3 {
            // GPS hizi (cm/s, UINT16_MAX = gecersiz)
            if message.vel != UInt16.max {
                gpsSpeed = Float(message.vel) / 100.0
            }
            
            // GPS MSL yuksekligi (mm) ve yer referansina gore AGL
            gpsAltitudeMSL = Float(message.alt) / 1000.0
            if gpsAltRef == nil {
                gpsAltRef = gpsAltitudeMSL   // ilk 3D fix'te yer referansi
            }
            if let ref = gpsAltRef {
                gpsAgl = gpsAltitudeMSL - ref
            }
            
            // IMU olu-hesap hizini GPS ile senkronla: fix kaybolursa son bilinen hizdan devam eder
            if let speed = gpsSpeed {
                if message.cog != UInt16.max {
                    let cogRad = Float(message.cog) / 100.0 * .pi / 180.0
                    imuVx = speed * cos(cogRad)
                    imuVy = speed * sin(cogRad)
                } else {
                    let mag = sqrt(imuVx * imuVx + imuVy * imuVy)
                    if mag > 0.01 {
                        imuVx = imuVx / mag * speed
                        imuVy = imuVy / mag * speed
                    }
                }
            }
        } else {
            // Fix kaybedildi: bir sonraki fix'te yer referansi yeniden alinmasin,
            // mevcut referans korunur (ayni ucusta tutarlilik)
        }
        
        // HDOP (eph = HDOP*100, UINT16_MAX = gecersiz)
        let hdop: Float = message.eph != UInt16.max ? Float(message.eph) / 100.0 : 99.99
        
        // Ham veri + alis frekansi (son 2 s penceresi)
        let now = Date()
        gpsRawTimestamps.append(now)
        gpsRawTimestamps.removeAll { now.timeIntervalSince($0) > 2.0 }
        let rate: Float = gpsRawTimestamps.count > 1
            ? Float(gpsRawTimestamps.count - 1) / Float(now.timeIntervalSince(gpsRawTimestamps.first!))
            : 0
        
        var raw = GPSRawData()
        raw.received = true
        raw.messageCount = gpsRaw.messageCount + 1
        raw.lastReceived = now
        raw.rateHz = rate
        raw.timeUsec = message.time_usec
        raw.fixType = fixType
        raw.lat = message.lat
        raw.lon = message.lon
        raw.alt = message.alt
        raw.eph = message.eph
        raw.epv = message.epv
        raw.vel = message.vel
        raw.cog = message.cog
        raw.satellitesVisible = satellites
        raw.altEllipsoid = message.alt_ellipsoid
        raw.hAcc = message.h_acc
        raw.vAcc = message.v_acc
        raw.velAcc = message.vel_acc
        raw.hdgAcc = message.hdg_acc
        raw.yaw = message.yaw
        
        DispatchQueue.main.async {
            self.gpsRaw = raw
            self.gpsFixType = fixType
            self.gpsSatellites = satellites
            self.gpsHdop = hdop
            
            self.droneState.gpsFixType = Int(fixType)
            self.droneState.gpsSatellites = Int(satellites)
            
            self.isUsingGPSSource = fixType >= 3
            if fixType >= 3 {
                if let speed = gpsSpeed { self.displaySpeed = speed }
                if let agl = gpsAgl { self.displayAltitude = agl }
            }
        }
        
        // Only log when we have GPS fix (not "No GPS" spam)
        if fixType >= 2 && (isFirstUpdate || fixChanged || satCountChanged) {
            let fixName = ["No GPS", "No Fix", "2D", "3D", "DGPS", "RTK Float", "RTK Fixed"]
            let fixStr = Int(fixType) < fixName.count ? fixName[Int(fixType)] : "Unknown"
            print("🛰️  GPS: \(fixStr), \(satellites) sats")
        }
    }
    
    func handleAttitude(_ message: mavlink_attitude_t) {
        // IMU olu-hesap icin radyan degerleri sakla (govde -> yer donusumu)
        attitudeRollRad = message.roll
        attitudePitchRad = message.pitch
        attitudeYawRad = message.yaw
        
        let roll = message.roll * (180.0 / Float.pi)
        let pitch = message.pitch * (180.0 / Float.pi)
        let yaw = message.yaw * (180.0 / Float.pi)
        
        let isFirstUpdate = self.roll == 0 && self.pitch == 0
        
        DispatchQueue.main.async {
            self.roll = roll
            self.pitch = pitch
            self.yaw = yaw
            
            self.droneState.roll = roll
            self.droneState.pitch = pitch
            self.droneState.yaw = yaw
        }
        
        if isFirstUpdate {
            print("🎯 Attitude: Roll=\(String(format: "%.1f", roll))° Pitch=\(String(format: "%.1f", pitch))° Yaw=\(String(format: "%.1f", yaw))°")
        }
    }
    
    func handleServoOutputRaw(_ message: mavlink_servo_output_raw_t) {
        var servos: [Int: UInt16] = [:]
        servos[1] = message.servo1_raw
        servos[2] = message.servo2_raw
        servos[3] = message.servo3_raw
        servos[4] = message.servo4_raw
        servos[5] = message.servo5_raw
        servos[6] = message.servo6_raw
        servos[7] = message.servo7_raw
        servos[8] = message.servo8_raw
        servos[9] = message.servo9_raw
        servos[10] = message.servo10_raw
        servos[11] = message.servo11_raw
        servos[12] = message.servo12_raw
        servos[13] = message.servo13_raw
        servos[14] = message.servo14_raw
        servos[15] = message.servo15_raw
        servos[16] = message.servo16_raw
        
        let isFirstUpdate = self.servoValues.isEmpty
        
        DispatchQueue.main.async {
            self.servoValues = servos
        }
        
        if isFirstUpdate {
            print("🔧 Servo Output (PWM):")
            for i in 1...8 {
                if let pwm = servos[i], pwm > 0 {
                    print("   CH\(i): \(pwm)μs")
                }
            }
        }
    }
    
    func handleVFRHUD(_ message: mavlink_vfr_hud_t) {
        let speed = message.groundspeed
        let climb = message.climb
        let alt = message.alt
        let hdg = message.heading
        
        let isFirstUpdate = self.groundSpeed == 0 && self.altitude == 0
        
        DispatchQueue.main.async {
            self.groundSpeed = speed
            self.climbRate = climb
            self.altitude = alt
            self.heading = Float(hdg)
        }
        
        if isFirstUpdate {
            print("📊 VFR_HUD: Speed=\(String(format: "%.1f", speed))m/s Climb=\(String(format: "%.1f", climb))m/s Alt=\(String(format: "%.1f", alt))m Hdg=\(hdg)°")
        }
    }
    
    func handleScaledPressure(_ message: mavlink_scaled_pressure_t) {
        let press = message.press_abs
        let temp = Float(message.temperature) / 100.0
        
        // Barometrik yukseklik (ISA): h = 44330 * (1 - (P/P0)^0.190295)
        if press > 0 {
            baroAltitude = 44330.0 * (1.0 - pow(press / 1013.25, 0.190295))
            if baroAltRef == nil {
                baroAltRef = baroAltitude   // ilk ornekte yer referansi
            }
        }
        
        let noFix = currentFixType < 3
        let baroAgl: Float? = baroAltRef.map { baroAltitude - $0 }
        
        DispatchQueue.main.async {
            self.pressure = press
            self.temperature = temp
            
            // GPS fix yokken yukseklik barometreden
            if noFix, let agl = baroAgl {
                self.isUsingGPSSource = false
                self.displayAltitude = agl
            }
        }
    }
    
    func handleScaledPressure2(_ message: mavlink_scaled_pressure2_t) {
        // Optional: handle second pressure sensor
    }
    
    func handleScaledIMU(_ message: mavlink_scaled_imu_t) {
        // GPS fix yokken hiz: govde ivmesini yer eksenine cevirip yatay bilesenleri integre et.
        // Not: olu-hesap (dead-reckoning) zamanla kayar; GPS geldiginde handleGPSRawInt senkronlar.
        defer { lastImuTimeMs = message.time_boot_ms }
        
        guard let lastMs = lastImuTimeMs, message.time_boot_ms > lastMs else { return }
        let dt = Float(message.time_boot_ms - lastMs) / 1000.0
        guard dt > 0, dt < 0.5 else { return }   // kopuk/duraklamis akista integre etme
        
        // mG -> m/s^2 (govde cercevesi, ozgul kuvvet)
        let g: Float = 9.80665
        let ax = Float(message.xacc) * g / 1000.0
        let ay = Float(message.yacc) * g / 1000.0
        let az = Float(message.zacc) * g / 1000.0
        
        // Govde -> yer (NED) donusumu, sadece yatay satirlar (Rz(psi)*Ry(theta)*Rx(phi)).
        // Yercekiminin yatay bileseni yoktur; yatay ozgul kuvvet = yatay lineer ivme.
        let cr = cos(attitudeRollRad),  sr = sin(attitudeRollRad)
        let cp = cos(attitudePitchRad), sp = sin(attitudePitchRad)
        let cy = cos(attitudeYawRad),   sy = sin(attitudeYawRad)
        
        let aN = cy * cp * ax + (cy * sp * sr - sy * cr) * ay + (cy * sp * cr + sy * sr) * az
        let aE = sy * cp * ax + (sy * sp * sr + cy * cr) * ay + (sy * sp * cr - cy * sr) * az
        
        // Duragan tespiti (ZUPT): toplam ivme ~1g ve yatay ivme kucukse hizi hizla sondur
        let totalMag = sqrt(ax * ax + ay * ay + az * az)
        let horizMag = sqrt(aN * aN + aE * aE)
        let isStationary = abs(totalMag - g) < 0.3 && horizMag < 0.25
        
        if isStationary {
            imuVx *= 0.80
            imuVy *= 0.80
            if abs(imuVx) < 0.05 { imuVx = 0 }
            if abs(imuVy) < 0.05 { imuVy = 0 }
        } else {
            imuVx += aN * dt
            imuVy += aE * dt
            // Sizinti (leaky) integrasyon: bias kaynakli sinirsiz kaymayi engelle
            let leak = Float(1.0 - 0.02 * Double(dt) / 0.1)
            imuVx *= leak
            imuVy *= leak
        }
        
        // GPS fix yokken hiz IMU'dan
        if currentFixType < 3 {
            let speed = sqrt(imuVx * imuVx + imuVy * imuVy)
            DispatchQueue.main.async {
                self.isUsingGPSSource = false
                self.displaySpeed = speed
            }
        }
    }
    
    func handleParamValue(_ message: mavlink_param_value_t) {
        let paramName = withUnsafeBytes(of: message.param_id) { rawBuffer -> String in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var length = 0
            for i in 0..<16 {
                if bytes[i] == 0 { break }
                length += 1
            }
            let validBytes = Array(bytes.prefix(length))
            return String(bytes: validBytes, encoding: .utf8) ?? ""
        }
        
        let value = message.param_value
        let index = Int(message.param_index)
        let count = Int(message.param_count)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.parameters[paramName] = value
            self.confirmParamWrite(name: paramName, value: value)
            if count > 0 { self.paramTotalCount = count }
            // Son parametre geldiginde veya tum liste dolunca indirmeyi bitti say
            if index >= count - 1 || (count > 0 && self.parameters.count >= count) {
                self.paramDownloading = false
            }
        }
        
        if index < count {
            print("📋 Param [\(index + 1)/\(count)]: \(paramName) = \(value)")
        }
    }
    
    func handleCommandAck(_ message: mavlink_command_ack_t) {
        let command = message.command
        let result = message.result
        
        let resultStr = MAVLinkProtocol.resultToString(result)
        print("✅ Command \(command) ACK: \(resultStr)")
        
        if command == UInt16(MAV_CMD_DO_START_MAG_CAL.rawValue) {
            let accepted = result == UInt8(MAV_RESULT_ACCEPTED.rawValue)
            DispatchQueue.main.async {
                self.magCalStartAck = resultStr
                if !accepted { self.magCalRunning = false }
            }
        }
        
        if command == UInt16(MAV_CMD_DO_ACCEPT_MAG_CAL.rawValue) {
            let accepted = result == UInt8(MAV_RESULT_ACCEPTED.rawValue)
            DispatchQueue.main.async {
                self.magCalAcceptAck = resultStr
                self.magCalSaved = accepted
            }
        }
        
        if command == UInt16(MAV_CMD_PREFLIGHT_CALIBRATION.rawValue) {
            let accepted = result == UInt8(MAV_RESULT_ACCEPTED.rawValue)
            let inProgress = result == UInt8(MAV_RESULT_IN_PROGRESS.rawValue)
            let which = pendingPreflightCal
            if !inProgress { pendingPreflightCal = nil }
            DispatchQueue.main.async {
                let state: SimpleCalState = inProgress
                    ? .inProgress(Date())
                    : (accepted ? .success("ACK: " + resultStr) : .failed("ACK: " + resultStr))
                if which == "gyro" { self.gyroCalState = state }
                if which == "baro" { self.baroCalState = state }
            }
        }
        
        if command == UInt16(MAV_CMD_DO_MOTOR_TEST.rawValue) {
            let accepted = result == UInt8(MAV_RESULT_ACCEPTED.rawValue)
            DispatchQueue.main.async {
                self.motorTestAckAccepted = accepted
                self.motorTestAckText = resultStr
            }
        }
        
        if command == UInt16(MAV_CMD_COMPONENT_ARM_DISARM.rawValue) {
            if result == UInt8(MAV_RESULT_ACCEPTED.rawValue) {
                print("✅ ARM/DISARM command accepted")
            } else {
                print("❌ ARM/DISARM command failed: \(resultStr)")
            }
        }
    }
    
    func handleStatusText(_ message: mavlink_statustext_t) {
        let text = withUnsafeBytes(of: message.text) { rawBuffer -> String in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var length = 0
            for i in 0..<50 {
                if bytes[i] == 0 { break }
                length += 1
            }
            let validBytes = Array(bytes.prefix(length))
            return String(bytes: validBytes, encoding: .utf8) ?? ""
        }
        
        let severity = message.severity
        let severityString = MAVLinkProtocol.severityToString(severity)
        
        print("📢 [\(severityString)] \(text)")
        
        let entry = VehicleMessage(date: Date(), severity: severity, text: text)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statusMessages.append(entry)
            if self.statusMessages.count > 300 {
                self.statusMessages.removeFirst(self.statusMessages.count - 300)
            }
        }
    }
    
    func handleEkfStatusReport(_ message: mavlink_ekf_status_report_t) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.ekfFlags = message.flags
            self.ekfVelocityVariance = message.velocity_variance
            self.ekfPosHorizVariance = message.pos_horiz_variance
            self.ekfCompassVariance = message.compass_variance
            self.ekfReportReceived = true
        }
    }
    
    func handleMissionCount(_ message: mavlink_mission_count_t) {
        print("📝 Mission count: \(message.count)")
    }
    
    func handleMissionItemInt(_ message: mavlink_mission_item_int_t) {
        print("📝 Mission item: \(message.seq)")
    }
    
    func handleMissionCurrent(_ message: mavlink_mission_current_t) {
        print("📝 Current mission item: \(message.seq)")
    }
    
    func handleMissionAck(_ message: mavlink_mission_ack_t) {
        print("📝 Mission ack: \(message.type)")
    }
    
    func handleMissionRequest(_ message: mavlink_mission_request_t) {
        print("📝 Mission request: \(message.seq)")
    }
    
    func handleMissionRequestInt(_ message: mavlink_mission_request_int_t) {
        print("📝 Mission request int: \(message.seq)")
    }
    
    func handleMissionItemReached(_ message: mavlink_mission_item_reached_t) {
        print("📝 Mission item reached: \(message.seq)")
    }
    
    func handleNamedValueFloat(_ message: mavlink_named_value_float_t) {
        let name = withUnsafeBytes(of: message.name) { rawBuffer -> String in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var length = 0
            for i in 0..<10 {
                if bytes[i] == 0 { break }
                length += 1
            }
            let validBytes = Array(bytes.prefix(length))
            return String(bytes: validBytes, encoding: .utf8) ?? ""
        }
        
        let value = message.value
        print("📊 \(name): \(value)")
    }
}

// MARK: - Mode Constants
extension MAVLinkManager {
    static let SUB_MODE_STABILIZE: UInt32 = 0
    static let SUB_MODE_ACRO: UInt32 = 1
    static let SUB_MODE_ALT_HOLD: UInt32 = 2
    static let SUB_MODE_AUTO: UInt32 = 3
    static let SUB_MODE_GUIDED: UInt32 = 4
    static let SUB_MODE_CIRCLE: UInt32 = 7
    static let SUB_MODE_SURFACE: UInt32 = 9
    static let SUB_MODE_POSHOLD: UInt32 = 16
    static let SUB_MODE_MANUAL: UInt32 = 19
    
    static let ROVER_MODE_MANUAL: UInt32 = 0
    static let ROVER_MODE_ACRO: UInt32 = 1
    static let ROVER_MODE_STEERING: UInt32 = 3
    static let ROVER_MODE_HOLD: UInt32 = 4
    static let ROVER_MODE_LOITER: UInt32 = 5
    static let ROVER_MODE_AUTO: UInt32 = 10
    static let ROVER_MODE_RTL: UInt32 = 11
    static let ROVER_MODE_SMART_RTL: UInt32 = 12
    static let ROVER_MODE_GUIDED: UInt32 = 15
    
    static let COPTER_MODE_STABILIZE: UInt32 = 0
    static let COPTER_MODE_ACRO: UInt32 = 1
    static let COPTER_MODE_ALT_HOLD: UInt32 = 2
    static let COPTER_MODE_AUTO: UInt32 = 3
    static let COPTER_MODE_GUIDED: UInt32 = 4
    static let COPTER_MODE_LOITER: UInt32 = 5
    static let COPTER_MODE_RTL: UInt32 = 6
    static let COPTER_MODE_CIRCLE: UInt32 = 7
    static let COPTER_MODE_LAND: UInt32 = 9
    static let COPTER_MODE_POSHOLD: UInt32 = 16
}
