//
//  MAVLinkProtocol.swift
//  DroneControl
//
//  MAVLink protocol parsing and message handling
//  Based on C++ MAVLinkCom implementation
//

import Foundation

// MAVLink message handler protocol
protocol MAVLinkMessageHandler: AnyObject {
    func handleHeartbeat(_ message: mavlink_heartbeat_t)
    func handleSysStatus(_ message: mavlink_sys_status_t)
    func handleGlobalPositionInt(_ message: mavlink_global_position_int_t)
    func handleGPSRawInt(_ message: mavlink_gps_raw_int_t)
    func handleAttitude(_ message: mavlink_attitude_t)
    func handleServoOutputRaw(_ message: mavlink_servo_output_raw_t)
    func handleVFRHUD(_ message: mavlink_vfr_hud_t)
    func handleScaledPressure(_ message: mavlink_scaled_pressure_t)
    func handleScaledPressure2(_ message: mavlink_scaled_pressure2_t)
    func handleParamValue(_ message: mavlink_param_value_t)
    func handleCommandAck(_ message: mavlink_command_ack_t)
    func handleStatusText(_ message: mavlink_statustext_t)
    func handleMissionCount(_ message: mavlink_mission_count_t)
    func handleMissionItemInt(_ message: mavlink_mission_item_int_t)
    func handleMissionCurrent(_ message: mavlink_mission_current_t)
    func handleMissionAck(_ message: mavlink_mission_ack_t)
    func handleMissionRequest(_ message: mavlink_mission_request_t)
    func handleMissionRequestInt(_ message: mavlink_mission_request_int_t)
    func handleMissionItemReached(_ message: mavlink_mission_item_reached_t)
    func handleNamedValueFloat(_ message: mavlink_named_value_float_t)
}

class MAVLinkProtocol {
    // MAVLink channel for parsing
    private var channel: mavlink_channel_t = MAVLINK_COMM_0
    private var status = mavlink_status_t()
    private var message = mavlink_message_t()
    
    // Message statistics
    private var messagesReceived: UInt64 = 0
    private var messagesDropped: UInt64 = 0
    private var parseErrors: UInt64 = 0
    
    // Handler delegate
    weak var messageHandler: MAVLinkMessageHandler?
    
    // Lock for thread safety
    private let parseLock = NSLock()
    
    init() {
        // Initialize MAVLink channel
        mavlink_reset_channel_status(UInt8(channel.rawValue))
        
        // Configure for MAVLink v1 (like C++ code)
        var channelStatus = mavlink_get_channel_status(UInt8(channel.rawValue))
        channelStatus?.pointee.flags |= UInt8(MAVLINK_STATUS_FLAG_OUT_MAVLINK1)
        
        print("✅ MAVLink protocol initialized on channel \(channel.rawValue)")
    }
    
    deinit {
        mavlink_reset_channel_status(UInt8(channel.rawValue))
    }
    
    // Parse incoming data buffer
    func parseData(_ data: Data) {
        parseLock.lock()
        defer { parseLock.unlock() }
        
        for byte in data {
            if mavlink_parse_char(UInt8(channel.rawValue), byte, &message, &status) != 0 {
                // Complete message received
                messagesReceived += 1
                processMessage(message)
            }
        }
        
        // Track dropped packets
        if status.packet_rx_drop_count > 0 {
            messagesDropped = UInt64(status.packet_rx_drop_count)
        }
    }
    
    // Track received message types
    private var receivedMessageTypes: Set<UInt32> = []
    
    // Process a complete MAVLink message
    private func processMessage(_ msg: mavlink_message_t) {
        // Log first time we see each message type
        if !receivedMessageTypes.contains(msg.msgid) {
            receivedMessageTypes.insert(msg.msgid)
            print("📨 New message type: ID \(msg.msgid) (\(MAVLinkProtocol.messageIDToName(msg.msgid)))")
        }
        
        guard let handler = messageHandler else {
            print("⚠️ No message handler registered")
            return
        }
        
        switch Int(msg.msgid) {
        case Int(MAVLINK_MSG_ID_HEARTBEAT):
            var heartbeat = mavlink_heartbeat_t()
            mavlink_msg_heartbeat_decode(&message, &heartbeat)
            handler.handleHeartbeat(heartbeat)
            
        case Int(MAVLINK_MSG_ID_SYS_STATUS):
            var sysStatus = mavlink_sys_status_t()
            mavlink_msg_sys_status_decode(&message, &sysStatus)
            handler.handleSysStatus(sysStatus)
            
        case Int(MAVLINK_MSG_ID_GLOBAL_POSITION_INT):
            var globalPos = mavlink_global_position_int_t()
            mavlink_msg_global_position_int_decode(&message, &globalPos)
            handler.handleGlobalPositionInt(globalPos)
            
        case Int(MAVLINK_MSG_ID_GPS_RAW_INT):
            var gpsRaw = mavlink_gps_raw_int_t()
            mavlink_msg_gps_raw_int_decode(&message, &gpsRaw)
            handler.handleGPSRawInt(gpsRaw)
            
        case Int(MAVLINK_MSG_ID_ATTITUDE):
            var attitude = mavlink_attitude_t()
            mavlink_msg_attitude_decode(&message, &attitude)
            handler.handleAttitude(attitude)
            
        case Int(MAVLINK_MSG_ID_SERVO_OUTPUT_RAW):
            var servoOutput = mavlink_servo_output_raw_t()
            mavlink_msg_servo_output_raw_decode(&message, &servoOutput)
            handler.handleServoOutputRaw(servoOutput)
            
        case Int(MAVLINK_MSG_ID_VFR_HUD):
            var vfrHud = mavlink_vfr_hud_t()
            mavlink_msg_vfr_hud_decode(&message, &vfrHud)
            handler.handleVFRHUD(vfrHud)
            
        case Int(MAVLINK_MSG_ID_SCALED_PRESSURE):
            var pressure = mavlink_scaled_pressure_t()
            mavlink_msg_scaled_pressure_decode(&message, &pressure)
            handler.handleScaledPressure(pressure)
            
        case Int(MAVLINK_MSG_ID_SCALED_PRESSURE2):
            var pressure2 = mavlink_scaled_pressure2_t()
            mavlink_msg_scaled_pressure2_decode(&message, &pressure2)
            handler.handleScaledPressure2(pressure2)
            
        case Int(MAVLINK_MSG_ID_PARAM_VALUE):
            var paramValue = mavlink_param_value_t()
            mavlink_msg_param_value_decode(&message, &paramValue)
            handler.handleParamValue(paramValue)
            
        case Int(MAVLINK_MSG_ID_COMMAND_ACK):
            var commandAck = mavlink_command_ack_t()
            mavlink_msg_command_ack_decode(&message, &commandAck)
            handler.handleCommandAck(commandAck)
            
        case Int(MAVLINK_MSG_ID_STATUSTEXT):
            var statusText = mavlink_statustext_t()
            mavlink_msg_statustext_decode(&message, &statusText)
            handler.handleStatusText(statusText)
            
        case Int(MAVLINK_MSG_ID_MISSION_COUNT):
            var missionCount = mavlink_mission_count_t()
            mavlink_msg_mission_count_decode(&message, &missionCount)
            handler.handleMissionCount(missionCount)
            
        case Int(MAVLINK_MSG_ID_MISSION_ITEM_INT):
            var missionItem = mavlink_mission_item_int_t()
            mavlink_msg_mission_item_int_decode(&message, &missionItem)
            handler.handleMissionItemInt(missionItem)
            
        case Int(MAVLINK_MSG_ID_MISSION_CURRENT):
            var missionCurrent = mavlink_mission_current_t()
            mavlink_msg_mission_current_decode(&message, &missionCurrent)
            handler.handleMissionCurrent(missionCurrent)
            
        case Int(MAVLINK_MSG_ID_MISSION_ACK):
            var missionAck = mavlink_mission_ack_t()
            mavlink_msg_mission_ack_decode(&message, &missionAck)
            handler.handleMissionAck(missionAck)
            
        case Int(MAVLINK_MSG_ID_MISSION_REQUEST):
            var missionRequest = mavlink_mission_request_t()
            mavlink_msg_mission_request_decode(&message, &missionRequest)
            handler.handleMissionRequest(missionRequest)
            
        case Int(MAVLINK_MSG_ID_MISSION_REQUEST_INT):
            var missionRequestInt = mavlink_mission_request_int_t()
            mavlink_msg_mission_request_int_decode(&message, &missionRequestInt)
            handler.handleMissionRequestInt(missionRequestInt)
            
        case Int(MAVLINK_MSG_ID_MISSION_ITEM_REACHED):
            var missionItemReached = mavlink_mission_item_reached_t()
            mavlink_msg_mission_item_reached_decode(&message, &missionItemReached)
            handler.handleMissionItemReached(missionItemReached)
            
        case Int(MAVLINK_MSG_ID_NAMED_VALUE_FLOAT):
            var namedValueFloat = mavlink_named_value_float_t()
            mavlink_msg_named_value_float_decode(&message, &namedValueFloat)
            handler.handleNamedValueFloat(namedValueFloat)
            
        default:
            // Uncomment for debugging unknown messages
            // print("📨 Unhandled message ID: \(msg.msgid)")
            break
        }
    }
    
    // Get statistics
    func getStatistics() -> (received: UInt64, dropped: UInt64, errors: UInt64) {
        parseLock.lock()
        defer { parseLock.unlock() }
        return (messagesReceived, messagesDropped, parseErrors)
    }
    
    // Reset statistics
    func resetStatistics() {
        parseLock.lock()
        defer { parseLock.unlock() }
        messagesReceived = 0
        messagesDropped = 0
        parseErrors = 0
    }
}

// Helper extension for MAVLink result strings
extension MAVLinkProtocol {
    static func resultToString(_ result: UInt8) -> String {
        switch Int(result) {
        case Int(MAV_RESULT_ACCEPTED.rawValue):
            return "ACCEPTED"
        case Int(MAV_RESULT_TEMPORARILY_REJECTED.rawValue):
            return "TEMPORARILY_REJECTED"
        case Int(MAV_RESULT_DENIED.rawValue):
            return "DENIED"
        case Int(MAV_RESULT_UNSUPPORTED.rawValue):
            return "UNSUPPORTED"
        case Int(MAV_RESULT_FAILED.rawValue):
            return "FAILED"
        case Int(MAV_RESULT_IN_PROGRESS.rawValue):
            return "IN_PROGRESS"
        default:
            return "UNKNOWN(\(result))"
        }
    }
    
    static func severityToString(_ severity: UInt8) -> String {
        switch Int(severity) {
        case Int(MAV_SEVERITY_EMERGENCY.rawValue):
            return "EMERGENCY"
        case Int(MAV_SEVERITY_ALERT.rawValue):
            return "ALERT"
        case Int(MAV_SEVERITY_CRITICAL.rawValue):
            return "CRITICAL"
        case Int(MAV_SEVERITY_ERROR.rawValue):
            return "ERROR"
        case Int(MAV_SEVERITY_WARNING.rawValue):
            return "WARNING"
        case Int(MAV_SEVERITY_NOTICE.rawValue):
            return "NOTICE"
        case Int(MAV_SEVERITY_INFO.rawValue):
            return "INFO"
        case Int(MAV_SEVERITY_DEBUG.rawValue):
            return "DEBUG"
        default:
            return "UNKNOWN(\(severity))"
        }
    }
    
    static func messageIDToName(_ msgid: UInt32) -> String {
        switch Int(msgid) {
        case Int(MAVLINK_MSG_ID_HEARTBEAT): return "HEARTBEAT"
        case Int(MAVLINK_MSG_ID_SYS_STATUS): return "SYS_STATUS"
        case Int(MAVLINK_MSG_ID_GLOBAL_POSITION_INT): return "GLOBAL_POSITION_INT"
        case Int(MAVLINK_MSG_ID_GPS_RAW_INT): return "GPS_RAW_INT"
        case Int(MAVLINK_MSG_ID_ATTITUDE): return "ATTITUDE"
        case Int(MAVLINK_MSG_ID_SERVO_OUTPUT_RAW): return "SERVO_OUTPUT_RAW"
        case Int(MAVLINK_MSG_ID_VFR_HUD): return "VFR_HUD"
        case Int(MAVLINK_MSG_ID_SCALED_PRESSURE): return "SCALED_PRESSURE"
        case Int(MAVLINK_MSG_ID_COMMAND_ACK): return "COMMAND_ACK"
        case Int(MAVLINK_MSG_ID_STATUSTEXT): return "STATUSTEXT"
        case Int(MAVLINK_MSG_ID_PARAM_VALUE): return "PARAM_VALUE"
        default: return "ID_\(msgid)"
        }
    }
}
