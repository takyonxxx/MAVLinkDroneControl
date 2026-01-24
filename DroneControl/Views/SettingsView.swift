//
//  SettingsView.swift
//  DroneControl
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    @StateObject private var settings = SettingsManager.shared
    @State private var showParameters = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Connection Settings
                ConnectionCard(
                    host: $settings.connectionHost,
                    port: $settings.connectionPort
                )
                
                // Gamepad Settings (macOS)
                #if os(macOS)
                GamepadSettingsCard()
                #endif
                
                // Telemetry Status
                TelemetryStatusCard()
                
                // System Info
                SystemInfoCard()
                
                // Parameters
                ParametersCard(showParameters: $showParameters)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.05, green: 0.05, blue: 0.1))
    }
}

// MARK: - Connection Card
struct ConnectionCard: View {
    @Binding var host: String
    @Binding var port: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("MAVLink Connection", systemImage: "network")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            VStack(spacing: 10) {
                HStack {
                    Text("Host")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .frame(width: 80, alignment: .leading)
                    
                    TextField("192.168.4.1", text: $host)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                
                HStack {
                    Text("Port")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .frame(width: 80, alignment: .leading)
                    
                    TextField("14550", text: $port)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
        .cornerRadius(12)
    }
}

// MARK: - Gamepad Settings Card (macOS only)
#if os(macOS)
struct GamepadSettingsCard: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var gamepadManager = GamepadManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Gamepad Settings", systemImage: "gamecontroller.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Connection status
                HStack(spacing: 6) {
                    Circle()
                        .fill(gamepadManager.isControllerConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(gamepadManager.isControllerConnected ? "Connected" : "Disconnected")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            
            // Controller name
            if gamepadManager.isControllerConnected {
                HStack {
                    Text("Controller")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    Spacer()
                    Text(gamepadManager.controllerName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.cyan)
                }
            }
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // Deadzone slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Deadzone")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    Spacer()
                    Text(String(format: "%.2f", settings.gamepadDeadzone))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.cyan)
                }
                
                Slider(value: $settings.gamepadDeadzone, in: 0.0...0.3, step: 0.01)
                    .accentColor(.cyan)
                    .onChange(of: settings.gamepadDeadzone) { newValue in
                        gamepadManager.deadzone = newValue
                    }
            }
            
            // Hold Throttle toggle
            Toggle(isOn: $settings.gamepadHoldThrottle) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hold Throttle Position")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                    Text("Throttle stays at last position instead of returning to center")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .cyan))
            .onChange(of: settings.gamepadHoldThrottle) { newValue in
                gamepadManager.holdThrottle = newValue
            }
            
            // Throttle Speed slider (only when Hold Throttle is ON)
            if settings.gamepadHoldThrottle {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Throttle Speed")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(String(format: "%.3f", settings.throttleSpeed))
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                    
                    Slider(value: $settings.throttleSpeed, in: 0.005...0.05, step: 0.005)
                        .accentColor(.cyan)
                    
                    HStack {
                        Text("Slow")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Spacer()
                        Text("Fast")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
            }
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // Button mapping info
            VStack(alignment: .leading, spacing: 8) {
                Text("Button Mapping")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 4) {
                    ButtonMappingRow(button: "Left Stick", action: "Throttle (Y) / Yaw (X)")
                    ButtonMappingRow(button: "Right Stick", action: "Pitch (Y) / Roll (X)")
                    ButtonMappingRow(button: "Start", action: "ARM")
                    ButtonMappingRow(button: "Back", action: "DISARM")
                    ButtonMappingRow(button: "L3 / R3", action: "Reset All")
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
        .cornerRadius(12)
    }
}

struct ButtonMappingRow: View {
    let button: String
    let action: String
    
    var body: some View {
        HStack {
            Text(button)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.orange)
                .frame(width: 100, alignment: .leading)
            Text("→")
                .foregroundColor(.gray)
            Text(action)
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
    }
}
#endif

// MARK: - Telemetry Status Card
struct TelemetryStatusCard: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Telemetry Status", systemImage: "antenna.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            VStack(spacing: 10) {
                TelemetryRow(
                    label: "Connection",
                    value: mavlinkManager.isConnected ? "Connected" : "Disconnected",
                    color: mavlinkManager.isConnected ? .green : .red
                )
                
                TelemetryRow(
                    label: "Armed",
                    value: mavlinkManager.isArmed ? "ARMED" : "Disarmed",
                    color: mavlinkManager.isArmed ? .red : .green
                )
                
                TelemetryRow(
                    label: "Flight Mode",
                    value: mavlinkManager.droneState.flightMode.name,
                    color: mavlinkManager.droneState.flightMode.color
                )
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                TelemetryRow(
                    label: "Battery",
                    value: String(format: "%.2fV (%d%%)", mavlinkManager.batteryVoltage, mavlinkManager.batteryRemaining),
                    color: batteryColor(mavlinkManager.batteryRemaining)
                )
                
                TelemetryRow(
                    label: "Current",
                    value: String(format: "%.2fA", mavlinkManager.batteryCurrent),
                    color: .cyan
                )
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                TelemetryRow(
                    label: "GPS Fix",
                    value: gpsFixName(Int(mavlinkManager.gpsFixType)),
                    color: gpsColor(Int(mavlinkManager.gpsFixType))
                )
                
                TelemetryRow(
                    label: "Satellites",
                    value: "\(mavlinkManager.gpsSatellites)",
                    color: .cyan
                )
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                TelemetryRow(
                    label: "Altitude",
                    value: String(format: "%.1fm", mavlinkManager.altitude),
                    color: .cyan
                )
                
                TelemetryRow(
                    label: "Speed",
                    value: String(format: "%.1fm/s", mavlinkManager.groundSpeed),
                    color: .green
                )
            }
        }
        .padding(16)
        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
        .cornerRadius(12)
    }
    
    private func batteryColor(_ percent: Int) -> Color {
        if percent > 50 { return .green }
        if percent > 20 { return .orange }
        return .red
    }
    
    private func gpsColor(_ fixType: Int) -> Color {
        switch fixType {
        case 3...7: return .green
        case 2: return .orange
        default: return .red
        }
    }
    
    private func gpsFixName(_ fixType: Int) -> String {
        let names = ["No GPS", "No Fix", "2D", "3D", "DGPS", "RTK Float", "RTK Fixed"]
        return fixType < names.count ? names[fixType] : "Unknown"
    }
}

// MARK: - System Info Card
struct SystemInfoCard: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("System", systemImage: "cpu")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            VStack(spacing: 10) {
                InfoRow(label: "System ID", value: "\(mavlinkManager.targetSystemID)")
                InfoRow(label: "Component ID", value: "\(mavlinkManager.targetComponentID)")
                InfoRow(label: "Vehicle Type", value: vehicleTypeName(mavlinkManager.vehicleType))
                InfoRow(label: "Parameters", value: "\(mavlinkManager.parameters.count)")
            }
        }
        .padding(16)
        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
        .cornerRadius(12)
    }
    
    private func vehicleTypeName(_ type: UInt8) -> String {
        switch type {
        case 1: return "Fixed Wing"
        case 2: return "Quadrotor"
        case 10: return "Ground Rover"
        case 12: return "Submarine"
        default: return "Unknown (\(type))"
        }
    }
}

// MARK: - Parameters Card
struct ParametersCard: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    @Binding var showParameters: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Parameters", systemImage: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(mavlinkManager.parameters.count)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.2))
                    .cornerRadius(8)
            }
            
            Button(action: {
                showParameters.toggle()
            }) {
                HStack {
                    Text(showParameters ? "Hide Parameters" : "Show Parameters")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Image(systemName: showParameters ? "chevron.up" : "chevron.down")
                }
                .foregroundColor(.cyan)
                .padding(12)
                .background(Color.cyan.opacity(0.1))
                .cornerRadius(8)
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #endif
            
            if showParameters {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(mavlinkManager.parameters.keys.sorted()), id: \.self) { key in
                            if let value = mavlinkManager.parameters[key] {
                                HStack {
                                    Text(key)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text(String(format: "%.2f", value))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.cyan)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color(red: 0.15, green: 0.15, blue: 0.2))
                                .cornerRadius(4)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .padding(16)
        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
        .cornerRadius(12)
    }
}

// MARK: - Helper Views
struct TelemetryRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(MAVLinkManager.shared)
}
