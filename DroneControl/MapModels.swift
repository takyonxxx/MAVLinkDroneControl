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
        VStack(spacing: 12) {
            // GPS Coordinates
            TelemetryDataRow(
                icon: "location.fill",
                title: "GPS",
                value: String(format: "%.6f, %.6f", mavlinkManager.latitude, mavlinkManager.longitude),
                color: .cyan
            )
            
            // Altitude
            TelemetryDataRow(
                icon: "arrow.up.circle.fill",
                title: "Altitude",
                value: String(format: "%.1f m", mavlinkManager.altitude),
                color: .green
            )
            
            // Speed
            TelemetryDataRow(
                icon: "speedometer",
                title: "Speed",
                value: String(format: "%.1f m/s", mavlinkManager.groundSpeed),
                color: .orange
            )
            
            // Heading
            TelemetryDataRow(
                icon: "safari.fill",
                title: "Heading",
                value: String(format: "%.0f°", mavlinkManager.heading),
                color: .purple
            )
            
            // Voltage
            TelemetryDataRow(
                icon: "bolt.fill",
                title: "Voltage",
                value: String(format: "%.2f V", mavlinkManager.batteryVoltage),
                color: batteryColor
            )
            
            // Current
            TelemetryDataRow(
                icon: "bolt.circle.fill",
                title: "Current",
                value: String(format: "%.2f A", mavlinkManager.batteryCurrent),
                color: .yellow
            )
            
            // GPS Status
            TelemetryDataRow(
                icon: "antenna.radiowaves.left.and.right",
                title: "GPS",
                value: "\(mavlinkManager.gpsSatellites) sats",
                color: gpsColor
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 8)
        )
        .frame(width: 280)
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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 70, alignment: .leading)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .monospacedDigit()
        }
    }
}
