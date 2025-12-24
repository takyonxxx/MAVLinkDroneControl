//
//  ConnectionStatusView.swift
//  DroneControl
//
//  Connection status indicator view
//

import SwiftUI

struct ConnectionStatusView: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        HStack(spacing: 16) {
            // Connection indicator
            VStack(spacing: 4) {
                Circle()
                    .fill(mavlinkManager.isConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    )
                
                Text(mavlinkManager.isConnected ? "Connected" : "Disconnected")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Divider()
                .frame(height: 40)
            
            // ARM status
            VStack(spacing: 4) {
                Circle()
                    .fill(mavlinkManager.isArmed ? Color.orange : Color.gray)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    )
                
                Text(mavlinkManager.isArmed ? "ARMED" : "DISARMED")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Divider()
                .frame(height: 40)
            
            // Flight mode
            VStack(spacing: 4) {
                Image(systemName: mavlinkManager.droneState.flightMode.icon)
                    .font(.system(size: 12))
                    .foregroundColor(mavlinkManager.droneState.flightMode.color)
                
                Text(mavlinkManager.droneState.flightMode.name)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Divider()
                .frame(height: 40)
            
            // Battery
            VStack(spacing: 4) {
                Image(systemName: batteryIcon)
                    .font(.system(size: 12))
                    .foregroundColor(batteryColor)
                
                Text("\(mavlinkManager.batteryRemaining)%")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Divider()
                .frame(height: 40)
            
            // GPS
            VStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 12))
                    .foregroundColor(gpsColor)
                
                Text("\(mavlinkManager.gpsSatellites) sats")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }
    
    // MARK: - Computed Properties
    
    private var batteryIcon: String {
        let remaining = mavlinkManager.batteryRemaining
        if remaining > 75 {
            return "battery.100"
        } else if remaining > 50 {
            return "battery.75"
        } else if remaining > 25 {
            return "battery.25"
        } else {
            return "battery.0"
        }
    }
    
    private var batteryColor: Color {
        let remaining = mavlinkManager.batteryRemaining
        if remaining > 50 {
            return .green
        } else if remaining > 20 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var gpsColor: Color {
        if mavlinkManager.gpsFixType >= 3 {
            return .green
        } else if mavlinkManager.gpsFixType >= 2 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Compact Version
struct CompactConnectionStatus: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Connection
            Circle()
                .fill(mavlinkManager.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            // ARM
            Circle()
                .fill(mavlinkManager.isArmed ? Color.orange : Color.gray)
                .frame(width: 8, height: 8)
            
            // Battery
            HStack(spacing: 4) {
                Image(systemName: "battery.100")
                    .font(.caption2)
                    .foregroundColor(batteryColor)
                Text("\(mavlinkManager.batteryRemaining)%")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            // GPS
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.caption2)
                    .foregroundColor(gpsColor)
                Text("\(mavlinkManager.gpsSatellites)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
    }
    
    private var batteryColor: Color {
        let remaining = mavlinkManager.batteryRemaining
        if remaining > 50 {
            return .green
        } else if remaining > 20 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var gpsColor: Color {
        mavlinkManager.gpsFixType >= 3 ? .green : .red
    }
}

// MARK: - Detailed Status Card
struct DetailedConnectionStatus: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        VStack(spacing: 12) {
            // Top row: Connection & ARM
            HStack {
                StatusItem(
                    icon: "wifi",
                    title: "Connection",
                    value: mavlinkManager.isConnected ? "Connected" : "Disconnected",
                    color: mavlinkManager.isConnected ? .green : .red
                )
                
                Spacer()
                
                StatusItem(
                    icon: mavlinkManager.isArmed ? "lock.open.fill" : "lock.fill",
                    title: "Status",
                    value: mavlinkManager.isArmed ? "ARMED" : "DISARMED",
                    color: mavlinkManager.isArmed ? .orange : .gray
                )
            }
            
            Divider()
            
            // Second row: Mode & Battery
            HStack {
                StatusItem(
                    icon: mavlinkManager.droneState.flightMode.icon,
                    title: "Mode",
                    value: mavlinkManager.droneState.flightMode.name,
                    color: mavlinkManager.droneState.flightMode.color
                )
                
                Spacer()
                
                StatusItem(
                    icon: "battery.100",
                    title: "Battery",
                    value: "\(mavlinkManager.batteryRemaining)%",
                    color: batteryColor
                )
            }
            
            Divider()
            
            // Third row: GPS & Altitude
            HStack {
                StatusItem(
                    icon: "location.fill",
                    title: "GPS",
                    value: "\(mavlinkManager.gpsSatellites) sats",
                    color: gpsColor
                )
                
                Spacer()
                
                StatusItem(
                    icon: "arrow.up.and.down",
                    title: "Altitude",
                    value: String(format: "%.1f m", mavlinkManager.altitude),
                    color: .cyan
                )
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }
    
    private var batteryColor: Color {
        let remaining = mavlinkManager.batteryRemaining
        if remaining > 50 {
            return .green
        } else if remaining > 20 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var gpsColor: Color {
        mavlinkManager.gpsFixType >= 3 ? .green : .red
    }
}

// MARK: - Status Item Helper
struct StatusItem: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
        }
    }
}

#Preview("Normal") {
    ConnectionStatusView()
        .environmentObject(MAVLinkManager.shared)
        .preferredColorScheme(.dark)
        .padding()
        .background(Color.black)
}

#Preview("Compact") {
    CompactConnectionStatus()
        .environmentObject(MAVLinkManager.shared)
        .preferredColorScheme(.dark)
        .padding()
        .background(Color.black)
}

#Preview("Detailed") {
    DetailedConnectionStatus()
        .environmentObject(MAVLinkManager.shared)
        .preferredColorScheme(.dark)
        .padding()
        .background(Color.black)
}
