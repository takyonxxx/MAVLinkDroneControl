//
//  MapModels.swift
//  DroneControl
//
//  Shared models and components for map views
//

import SwiftUI
import MapKit

// MARK: - Drone Location Model
struct DroneLocation: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let heading: Double
}

// MARK: - Telemetry Panel Component
struct TelemetryPanel: View {
    @ObservedObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        VStack(spacing: 6) {
            TelemetryDataRow(
                icon: "location.fill",
                title: "GPS",
                value: String(format: "%.5f,%.5f", mavlinkManager.latitude, mavlinkManager.longitude),
                color: .cyan
            )
            
            HStack(spacing: 6) {
                TelemetryDataRow(
                    icon: "arrow.up.circle.fill",
                    title: "Alt",
                    value: String(format: "%.0fm", mavlinkManager.altitude),
                    color: .green
                )
                
                TelemetryDataRow(
                    icon: "speedometer",
                    title: "Spd",
                    value: String(format: "%.1f", mavlinkManager.groundSpeed),
                    color: .orange
                )
            }
            
            HStack(spacing: 6) {
                TelemetryDataRow(
                    icon: "safari.fill",
                    title: "Hdg",
                    value: String(format: "%.0f°", mavlinkManager.heading),
                    color: .purple
                )
                
                TelemetryDataRow(
                    icon: "bolt.fill",
                    title: "Bat",
                    value: String(format: "%.1fV", mavlinkManager.batteryVoltage),
                    color: batteryColor
                )
            }
            
            TelemetryDataRow(
                icon: "antenna.radiowaves.left.and.right",
                title: "SAT",
                value: "\(mavlinkManager.gpsSatellites)",
                color: gpsColor
            )
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.25))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .frame(width: 220)
    }
    
    private var batteryColor: Color {
        if mavlinkManager.batteryVoltage < 10.5 {
            return .red
        } else if mavlinkManager.batteryVoltage < 11.1 {
            return .orange
        } else {
            return .green
        }
    }
    
    private var gpsColor: Color {
        if mavlinkManager.gpsSatellites >= 8 {
            return .green
        } else if mavlinkManager.gpsSatellites >= 5 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Telemetry Data Row Component
struct TelemetryDataRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 14)
            
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 28, alignment: .leading)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .monospacedDigit()
        }
    }
}
