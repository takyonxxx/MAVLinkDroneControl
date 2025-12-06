//
//  ControlPanelView.swift
//  DroneControl
//
//  Main control panel with ARM/DISARM and mode controls
//

import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    @State private var showingArmAlert = false
    @State private var showingDisarmAlert = false
    @State private var selectedMode: CopterFlightMode = .stabilize
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Connection Status
                ConnectionStatusCard()
                
                // ARM/DISARM Controls
                ArmDisarmCard(
                    showingArmAlert: $showingArmAlert,
                    showingDisarmAlert: $showingDisarmAlert
                )
                
                // Flight Mode Selector
                FlightModeCard(selectedMode: $selectedMode)
                
                // Quick Actions
                QuickActionsCard()
                
                // Telemetry Summary
                TelemetrySummaryCard()
            }
            .padding()
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.18),
                    Color(red: 0.09, green: 0.13, blue: 0.24)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - Connection Status Card
struct ConnectionStatusCard: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "wifi")
                    .foregroundColor(mavlinkManager.isConnected ? .green : .red)
                Text(mavlinkManager.isConnected ? "Connected" : "Disconnected")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            if !mavlinkManager.isConnected {
                Button(action: {
                    mavlinkManager.connect()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Connect")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }
}

// MARK: - ARM/DISARM Card
struct ArmDisarmCard: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    @Binding var showingArmAlert: Bool
    @Binding var showingDisarmAlert: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Vehicle Control")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                // ARM Button
                Button(action: {
                    showingArmAlert = true
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.open.fill")
                            .font(.title)
                        Text("ARM")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(mavlinkManager.isArmed ? Color.gray : Color.green)
                    .cornerRadius(12)
                }
                .disabled(mavlinkManager.isArmed || !mavlinkManager.isConnected)
                .alert("ARM Vehicle", isPresented: $showingArmAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("ARM", role: .destructive) {
                        mavlinkManager.armVehicle(force: true)
                    }
                } message: {
                    Text("This will arm the vehicle. Make sure the area is clear!")
                }
                
                // DISARM Button
                Button(action: {
                    showingDisarmAlert = true
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.title)
                        Text("DISARM")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(mavlinkManager.isArmed ? Color.orange : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(!mavlinkManager.isArmed || !mavlinkManager.isConnected)
                .alert("DISARM Vehicle", isPresented: $showingDisarmAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("DISARM") {
                        mavlinkManager.disarmVehicle(force: true)
                    }
                } message: {
                    Text("This will disarm the vehicle.")
                }
            }
            
            // Current Status
            HStack {
                Text("Status:")
                    .foregroundColor(.gray)
                Text(mavlinkManager.isArmed ? "ARMED" : "DISARMED")
                    .fontWeight(.bold)
                    .foregroundColor(mavlinkManager.isArmed ? .orange : .gray)
            }
            .font(.caption)
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }
}

// MARK: - Flight Mode Card
struct FlightModeCard: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    @Binding var selectedMode: CopterFlightMode
    
    let quickModes: [CopterFlightMode] = [.stabilize, .altHold, .loiter, .rtl, .land]
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Flight Mode")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Current mode
                HStack(spacing: 8) {
                    Image(systemName: mavlinkManager.droneState.flightMode.icon)
                        .foregroundColor(mavlinkManager.droneState.flightMode.color)
                    Text(mavlinkManager.droneState.flightMode.name)
                        .foregroundColor(.white)
                }
                .font(.subheadline)
            }
            
            // Quick mode buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(quickModes, id: \.self) { mode in
                        ModeButton(mode: mode, selectedMode: $selectedMode)
                    }
                }
            }
            
            // Set mode button
            if selectedMode != mavlinkManager.droneState.flightMode {
                Button(action: {
                    mavlinkManager.setFlightMode(selectedMode)
                }) {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Set Mode: \(selectedMode.name)")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .disabled(!mavlinkManager.isConnected)
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }
}

// MARK: - Mode Button
struct ModeButton: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    let mode: CopterFlightMode
    @Binding var selectedMode: CopterFlightMode
    
    var isCurrentMode: Bool {
        mavlinkManager.droneState.flightMode == mode
    }
    
    var body: some View {
        Button(action: {
            selectedMode = mode
        }) {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.title3)
                    .foregroundColor(isCurrentMode ? .white : mode.color)
                
                Text(mode.name)
                    .font(.caption)
                    .foregroundColor(isCurrentMode ? .white : .gray)
            }
            .frame(width: 80)
            .padding(.vertical, 12)
            .background(
                isCurrentMode ? mode.color : (selectedMode == mode ? Color.blue.opacity(0.3) : Color.clear)
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        selectedMode == mode ? Color.blue : Color.clear,
                        lineWidth: 2
                    )
            )
        }
    }
}

// MARK: - Quick Actions Card
struct QuickActionsCard: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundColor(.white)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                QuickActionButton(
                    icon: "location.fill",
                    title: "Hold Position",
                    action: {
                        mavlinkManager.setFlightMode(.posHold)
                    }
                )
                
                QuickActionButton(
                    icon: "house.fill",
                    title: "Return Home",
                    action: {
                        mavlinkManager.setFlightMode(.rtl)
                    }
                )
                
                QuickActionButton(
                    icon: "arrow.down.circle.fill",
                    title: "Land",
                    action: {
                        mavlinkManager.setFlightMode(.land)
                    }
                )
                
                QuickActionButton(
                    icon: "arrow.up.and.down",
                    title: "Hold Altitude",
                    action: {
                        mavlinkManager.setFlightMode(.altHold)
                    }
                )
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }
}

// MARK: - Quick Action Button
struct QuickActionButton: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue.opacity(0.3))
            .cornerRadius(8)
        }
        .disabled(!mavlinkManager.isConnected)
    }
}

// MARK: - Telemetry Summary Card
struct TelemetrySummaryCard: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Telemetry")
                .font(.headline)
                .foregroundColor(.white)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                TelemetryItem(
                    icon: "battery.100",
                    label: "Battery",
                    value: "\(mavlinkManager.batteryRemaining)%",
                    color: batteryColor
                )
                
                TelemetryItem(
                    icon: "location.fill",
                    label: "GPS",
                    value: "\(mavlinkManager.gpsSatellites) sats",
                    color: gpsColor
                )
                
                TelemetryItem(
                    icon: "arrow.up.and.down",
                    label: "Altitude",
                    value: String(format: "%.1f m", mavlinkManager.altitude),
                    color: .cyan
                )
                
                TelemetryItem(
                    icon: "speedometer",
                    label: "Speed",
                    value: String(format: "%.1f m/s", mavlinkManager.groundSpeed),
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

// MARK: - Telemetry Item
struct TelemetryItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
            
            Text(value)
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.black.opacity(0.2))
        .cornerRadius(8)
    }
}

#Preview {
    ControlPanelView()
        .environmentObject(MAVLinkManager.shared)
        .preferredColorScheme(.dark)
}
