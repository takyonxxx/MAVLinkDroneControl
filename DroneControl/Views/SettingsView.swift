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
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Connection Settings
                    ConnectionCard(
                        host: $settings.connectionHost,
                        port: $settings.connectionPort
                    )
                    
                    // Video Stream Settings
                    VideoStreamCard(rtspURL: $settings.rtspURL)
                    
                    // Telemetry Status
                    TelemetryStatusCard()
                    
                    // System Info
                    SystemInfoCard()
                    
                    // Parameters
                    ParametersCard(showParameters: $showParameters)
                }
                .padding()
            }
            .background(Color(red: 0.05, green: 0.05, blue: 0.1))
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
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

// MARK: - Video Stream Card
struct VideoStreamCard: View {
    @Binding var rtspURL: String
    @State private var tempURL: String = ""
    @State private var isEditing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Video Stream", systemImage: "video.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Edit/Save button
                Button(action: {
                    if isEditing {
                        // Save the new URL
                        rtspURL = tempURL
                        isEditing = false
                    } else {
                        // Start editing
                        tempURL = rtspURL
                        isEditing = true
                    }
                }) {
                    Text(isEditing ? "Kaydet" : "Düzenle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.cyan.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            
            VStack(spacing: 12) {
                // Current URL Display or Edit Field
                if isEditing {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RTSP URL")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                        
                        TextField("rtsp://192.168.4.1:554/stream", text: $tempURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.system(size: 13, design: .monospaced))
                            #if os(iOS)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            #endif
                        
                        // Common presets
                        Text("Hazır Şablonlar:")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .padding(.top, 4)
                        
                        VStack(spacing: 6) {
                            URLPresetButton(
                                title: "ESP32 (WiFi)",
                                url: "rtsp://192.168.4.1:554/stream"
                            ) {
                                tempURL = "rtsp://192.168.4.1:554/stream"
                            }
                            
                            URLPresetButton(
                                title: "Stream0",
                                url: "rtsp://192.168.1.249:554/stream0"
                            ) {
                                tempURL = "rtsp://192.168.1.249:554/stream0"
                            }
                            
                            URLPresetButton(
                                title: "Stream1",
                                url: "rtsp://192.168.1.249:554/stream1"
                            ) {
                                tempURL = "rtsp://192.168.1.249:554/stream1"
                            }
                        }
                    }
                } else {
                    // Display current URL
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aktif URL")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                        
                        Text(rtspURL)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.cyan)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(red: 0.15, green: 0.15, blue: 0.2))
                            .cornerRadius(8)
                    }
                }
                
                // Info text
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    
                    Text("URL değişikliği video akışını otomatik olarak yeniden başlatır")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
        .cornerRadius(12)
    }
}

// MARK: - URL Preset Button
struct URLPresetButton: View {
    let title: String
    let url: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                    Text(url)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(.cyan)
            }
            .padding(10)
            .background(Color(red: 0.15, green: 0.15, blue: 0.2))
            .cornerRadius(8)
        }
    }
}

// MARK: - Telemetry Status Card
struct TelemetryStatusCard: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Telemetry", systemImage: "antenna.radiowaves.left.and.right")
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
                    value: mavlinkManager.isArmed ? "Yes" : "No",
                    color: mavlinkManager.isArmed ? .orange : .gray
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
