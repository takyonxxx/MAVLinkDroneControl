//
//  MainDashboardView.swift
//  DroneControl
//

import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 600
            
            VStack(spacing: 0) {
                // Status bar - always visible
                VStack(spacing: 8) {
                    StatusBar()
                    
                    // Battery bar - always visible
                    BatteryBar()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(red: 0.08, green: 0.08, blue: 0.12))
                
                // Scrollable content
                ScrollView {
                    VStack(spacing: 12) {
                        if isCompact {
                            CompactLayout()
                        } else {
                            WideLayout()
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
            }
            .background(Color(red: 0.05, green: 0.05, blue: 0.1))
        }
    }
}

// MARK: - Battery Bar (Always Visible)
struct BatteryBar: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        HStack(spacing: 10) {
            // Voltage
            BatteryInfoItem(
                icon: "bolt.fill",
                label: "Voltage",
                value: String(format: "%.2fV", mavlinkManager.batteryVoltage),
                color: voltageColor(mavlinkManager.batteryVoltage)
            )
            
            Divider()
                .frame(height: 28)
                .background(Color.gray.opacity(0.3))
            
            // Current
            BatteryInfoItem(
                icon: "arrow.up.arrow.down",
                label: "Current",
                value: String(format: "%.2fA", mavlinkManager.batteryCurrent),
                color: .cyan
            )
            
            Divider()
                .frame(height: 28)
                .background(Color.gray.opacity(0.3))
            
            // Remaining
            BatteryInfoItem(
                icon: "battery.100",
                label: "Charge",
                value: "\(mavlinkManager.batteryRemaining)%",
                color: batteryColor(mavlinkManager.batteryRemaining)
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.12, blue: 0.18),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(10)
    }
    
    private func voltageColor(_ voltage: Float) -> Color {
        if voltage > 11.5 { return .green }
        if voltage > 10.5 { return .orange }
        return .red
    }
    
    private func batteryColor(_ percent: Int) -> Color {
        if percent > 50 { return .green }
        if percent > 20 { return .orange }
        return .red
    }
}

struct BatteryInfoItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Compact Layout (iPhone)
struct CompactLayout: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        VStack(spacing: 12) {
            // Attitude Indicator - optimized for iPhone 16 Pro
            AttitudeIndicator(
                roll: mavlinkManager.roll,
                pitch: mavlinkManager.pitch,
                heading: mavlinkManager.heading
            )
            .frame(height: 240)
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 15)
            
            // Servo outputs - right under indicator
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13))
                        .foregroundColor(.cyan)
                    Text("Motor Outputs")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 6) {
                    ForEach(1...4, id: \.self) { channel in
                        CompactServoBar(
                            channel: channel,
                            pwm: mavlinkManager.servoValues[channel] ?? 0
                        )
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.15))
            )
            .padding(.horizontal, 16)
            
            // Attitude values - compact
            HStack(spacing: 16) {
                AttitudeValue(label: "Roll", value: mavlinkManager.roll, unit: "°")
                Divider()
                    .frame(height: 20)
                    .background(Color.gray.opacity(0.3))
                AttitudeValue(label: "Pitch", value: mavlinkManager.pitch, unit: "°")
                Divider()
                    .frame(height: 20)
                    .background(Color.gray.opacity(0.3))
                AttitudeValue(label: "Yaw", value: mavlinkManager.yaw, unit: "°")
            }
            .padding(.horizontal, 16)
            
            // Telemetry grid - compact 2x2
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MiniTelemetryCard(
                    icon: "location.fill",
                    title: "GPS",
                    value: gpsFixName(Int(mavlinkManager.gpsFixType)),
                    color: gpsColor(Int(mavlinkManager.gpsFixType))
                )
                
                MiniTelemetryCard(
                    icon: "arrow.up",
                    title: "Altitude",
                    value: String(format: "%.1fm", mavlinkManager.altitude),
                    color: .cyan
                )
                
                MiniTelemetryCard(
                    icon: "speedometer",
                    title: "Speed",
                    value: String(format: "%.1fm/s", mavlinkManager.groundSpeed),
                    color: .green
                )
                
                MiniTelemetryCard(
                    icon: "gauge.high",
                    title: "Climb",
                    value: String(format: "%.1fm/s", mavlinkManager.climbRate),
                    color: .orange
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
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

// MARK: - Wide Layout (iPad/Mac)
struct WideLayout: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        HStack(spacing: 16) {
            // Left - Telemetry
            VStack(alignment: .leading, spacing: 12) {
                TelemetryCard(
                    icon: "battery.100",
                    title: "Battery",
                    value: String(format: "%.1fV", mavlinkManager.batteryVoltage),
                    subtitle: "\(mavlinkManager.batteryRemaining)%",
                    color: batteryColor(mavlinkManager.batteryRemaining)
                )
                
                TelemetryCard(
                    icon: "location.fill",
                    title: "GPS",
                    value: gpsFixName(Int(mavlinkManager.gpsFixType)),
                    subtitle: "\(mavlinkManager.gpsSatellites) sats",
                    color: gpsColor(Int(mavlinkManager.gpsFixType))
                )
                
                TelemetryCard(
                    icon: "arrow.up",
                    title: "Altitude",
                    value: String(format: "%.1fm", mavlinkManager.altitude),
                    subtitle: String(format: "%.1fm/s", mavlinkManager.climbRate),
                    color: .cyan
                )
                
                TelemetryCard(
                    icon: "speedometer",
                    title: "Speed",
                    value: String(format: "%.1fm/s", mavlinkManager.groundSpeed),
                    subtitle: String(format: "%.1fkm/h", mavlinkManager.groundSpeed * 3.6),
                    color: .green
                )
                
                Spacer()
            }
            .frame(maxWidth: 200)
            
            // Center - Attitude
            VStack(spacing: 12) {
                AttitudeIndicator(
                    roll: mavlinkManager.roll,
                    pitch: mavlinkManager.pitch,
                    heading: mavlinkManager.heading
                )
                .frame(width: 280, height: 280)
                
                HStack(spacing: 24) {
                    AttitudeValue(label: "Roll", value: mavlinkManager.roll, unit: "°")
                    AttitudeValue(label: "Pitch", value: mavlinkManager.pitch, unit: "°")
                    AttitudeValue(label: "Yaw", value: mavlinkManager.yaw, unit: "°")
                }
            }
            
            // Right - Servos
            VStack(alignment: .leading, spacing: 10) {
                Text("Servo Outputs")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                
                VStack(spacing: 6) {
                    ForEach(1...8, id: \.self) { channel in
                        ServoBar(
                            channel: channel,
                            pwm: mavlinkManager.servoValues[channel] ?? 0
                        )
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: 180)
        }
        .padding()
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

// MARK: - Compact Telemetry Card (iPhone)
struct CompactTelemetryCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.gray)
            
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            Text(subtitle)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
        .cornerRadius(10)
    }
}

// MARK: - Mini Telemetry Card (Extra Compact)
struct MiniTelemetryCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
        .cornerRadius(10)
    }
}

// MARK: - Telemetry Card (iPad/Mac)
struct TelemetryCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
        .padding(10)
        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
        .cornerRadius(10)
    }
}

// MARK: - Attitude Value
struct AttitudeValue: View {
    let label: String
    let value: Float
    let unit: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.gray)
            
            Text(String(format: "%.1f%@", value, unit))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Compact Servo Bar (iPhone)
struct CompactServoBar: View {
    let channel: Int
    let pwm: UInt16
    
    var body: some View {
        HStack(spacing: 8) {
            Text("M\(channel)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 28, alignment: .leading)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
                    
                    if pwm > 0 {
                        Rectangle()
                            .fill(servoColor(pwm))
                            .frame(width: servoProportion(pwm) * geometry.size.width)
                    }
                }
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                )
            }
            .frame(height: 18)
            
            Text("\(pwm)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(pwm > 0 ? servoColor(pwm) : .gray)
                .frame(width: 46, alignment: .trailing)
        }
    }
    
    private func servoProportion(_ pwm: UInt16) -> CGFloat {
        let clamped = max(1000, min(2000, pwm))
        return CGFloat(clamped - 1000) / 1000.0
    }
    
    private func servoColor(_ pwm: UInt16) -> Color {
        if pwm < 1100 { return .blue }
        if pwm > 1900 { return .red }
        if abs(Int(pwm) - 1500) < 50 { return .green }
        return .cyan
    }
}

// MARK: - Servo Bar (iPad/Mac)
struct ServoBar: View {
    let channel: Int
    let pwm: UInt16
    
    var body: some View {
        HStack(spacing: 6) {
            Text("CH\(channel)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 30, alignment: .leading)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(red: 0.2, green: 0.2, blue: 0.25))
                    
                    if pwm > 0 {
                        Rectangle()
                            .fill(servoColor(pwm))
                            .frame(width: servoProportion(pwm) * geometry.size.width)
                    }
                }
                .cornerRadius(2)
            }
            .frame(height: 16)
            
            Text("\(pwm)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(pwm > 0 ? .white : .gray)
                .frame(width: 36, alignment: .trailing)
        }
    }
    
    private func servoProportion(_ pwm: UInt16) -> CGFloat {
        let clamped = max(1000, min(2000, pwm))
        return CGFloat(clamped - 1000) / 1000.0
    }
    
    private func servoColor(_ pwm: UInt16) -> Color {
        if pwm < 1100 { return .blue }
        if pwm > 1900 { return .red }
        if abs(Int(pwm) - 1500) < 50 { return .green }
        return .orange
    }
}

#Preview {
    MainDashboardView()
        .environmentObject(MAVLinkManager.shared)
}
