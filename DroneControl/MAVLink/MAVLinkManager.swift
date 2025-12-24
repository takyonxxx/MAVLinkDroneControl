//
//  MAVLinkManager.swift
//  DroneControl
//

import Foundation
import Combine

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
    @Published var altitude: Float = 0.0
    @Published var heading: Float = 0.0
    @Published var roll: Float = 0.0
    @Published var pitch: Float = 0.0
    @Published var yaw: Float = 0.0
    
    @Published var gpsFixType: UInt8 = 0
    @Published var gpsSatellites: UInt8 = 0
    
    @Published var groundSpeed: Float = 0.0
    @Published var climbRate: Float = 0.0
    @Published var pressure: Float = 0.0
    @Published var temperature: Float = 0.0
    
    @Published var servoValues: [Int: UInt16] = [:]
    
    @Published var parameters: [String: Float] = [:]
    
    @Published var batteryVoltage: Float = 0.0
    @Published var batteryCurrent: Float = 0.0
    @Published var batteryRemaining: Int = 0
    
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
    
    init(host: String = "192.168.4.1", port: UInt16 = 14550, localPort: UInt16 = 14550) {
        self.udpConnection = UDPConnection(host: host, port: port, localPort: localPort)
        self.mavlinkProtocol = MAVLinkProtocol()
        
        mavlinkProtocol.messageHandler = self
        
        udpConnection.onDataReceived = { [weak self] data in
            self?.mavlinkProtocol.parseData(data)
        }
        
        udpConnection.onConnectionStatusChanged = { [weak self] connected in
            DispatchQueue.main.async {
                self?.isConnected = connected
                self?.droneState.isConnected = connected
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
    
    private func requestTelemetryMessages() {
        print("📡 Requesting telemetry messages...")
        
        // Message ID -> Rate in microseconds (1000000 = 1Hz, 250000 = 4Hz, 100000 = 10Hz)
        let messages: [(UInt32, Int32)] = [
            (1, 500000),    // SYS_STATUS at 2Hz
            (24, 200000),   // GPS_RAW_INT at 5Hz
            (30, 100000),   // ATTITUDE at 10Hz
            (33, 200000),   // GLOBAL_POSITION_INT at 5Hz
            (36, 100000),   // SERVO_OUTPUT_RAW at 10Hz - ÖNEMLİ!
            (74, 200000),   // VFR_HUD at 5Hz
            (29, 500000),   // SCALED_PRESSURE at 2Hz
        ]
        
        for (msgId, intervalUs) in messages {
            setMessageInterval(messageId: msgId, intervalUs: intervalUs)
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
            if let lastTime = self.lastHeartbeatTime {
                let elapsed = Date().timeIntervalSince(lastTime)
                if elapsed > self.connectionTimeout {
                    print("⚠️ Connection timeout - no heartbeat for \(elapsed)s")
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
    
    func requestAllParameters() {
        print("📋 Requesting all parameters...")
        var msg = mavlink_message_t()
        var paramRequest = mavlink_param_request_list_t()
        
        paramRequest.target_system = targetSystemID
        paramRequest.target_component = targetComponentID
        
        mavlink_msg_param_request_list_encode(systemID, componentID, &msg, &paramRequest)
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
        
        DispatchQueue.main.async {
            self.batteryVoltage = voltage
            self.batteryCurrent = current
            self.batteryRemaining = remaining
            
            self.droneState.batteryVoltage = voltage
            self.droneState.batteryCurrent = current
            self.droneState.batteryRemaining = remaining
        }
        
        if isFirstUpdate || voltageChanged || remainingChanged {
            print("🔋 Battery: \(String(format: "%.2f", voltage))V, \(String(format: "%.2f", current))A, \(remaining)%")
        }
    }
    
    func handleGlobalPositionInt(_ message: mavlink_global_position_int_t) {
        let lat = Double(message.lat) / 1e7
        let lon = Double(message.lon) / 1e7
        let alt = Float(message.alt) / 1000.0
        let hdg = Float(message.hdg) / 100.0
        
        DispatchQueue.main.async {
            self.latitude = lat
            self.longitude = lon
            self.altitude = alt
            self.heading = hdg
            
            self.droneState.latitude = lat
            self.droneState.longitude = lon
            self.droneState.altitude = alt
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
        
        DispatchQueue.main.async {
            self.gpsFixType = fixType
            self.gpsSatellites = satellites
            
            self.droneState.gpsFixType = Int(fixType)
            self.droneState.gpsSatellites = Int(satellites)
        }
        
        // Only log when we have GPS fix (not "No GPS" spam)
        if fixType >= 2 && (isFirstUpdate || fixChanged || satCountChanged) {
            let fixName = ["No GPS", "No Fix", "2D", "3D", "DGPS", "RTK Float", "RTK Fixed"]
            let fixStr = Int(fixType) < fixName.count ? fixName[Int(fixType)] : "Unknown"
            print("🛰️  GPS: \(fixStr), \(satellites) sats")
        }
    }
    
    func handleAttitude(_ message: mavlink_attitude_t) {
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
        
        DispatchQueue.main.async {
            self.pressure = press
            self.temperature = temp
        }
    }
    
    func handleScaledPressure2(_ message: mavlink_scaled_pressure2_t) {
        // Optional: handle second pressure sensor
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
            self?.parameters[paramName] = value
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
