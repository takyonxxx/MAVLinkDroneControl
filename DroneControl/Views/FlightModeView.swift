//
//  FlightModeView.swift
//  DroneControl
//
//  Flight mode selection view
//

import SwiftUI

struct FlightModeView: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    let availableModes: [CopterFlightMode] = [
        .stabilize, .altHold, .posHold, .loiter,
        .land, .rtl, .auto, .autotune
    ]
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Current mode card
                    CurrentModeCard()
                    
                    // Warning if armed
                    if mavlinkManager.isArmed {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Vehicle is armed - change modes carefully")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(8)
                    }
                    
                    // Mode grid
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(availableModes, id: \.self) { mode in
                            FlightModeButton(mode: mode)
                        }
                    }
                }
                .padding()
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.18),
                        Color(red: 0.09, green: 0.13, blue: 0.24)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Flight Modes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

// MARK: - Current Mode Card
struct CurrentModeCard: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Current Mode")
                .font(.caption)
                .foregroundColor(.gray)
            
            HStack(spacing: 16) {
                Image(systemName: mavlinkManager.droneState.flightMode.icon)
                    .font(.system(size: 40))
                    .foregroundColor(mavlinkManager.droneState.flightMode.color)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(mavlinkManager.droneState.flightMode.name)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Mode \(mavlinkManager.droneState.flightMode.rawValue)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(mavlinkManager.droneState.flightMode.color.opacity(0.15))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(mavlinkManager.droneState.flightMode.color.opacity(0.5), lineWidth: 2)
        )
    }
}

// MARK: - Flight Mode Button
struct FlightModeButton: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    let mode: CopterFlightMode
    
    var isSelected: Bool {
        mavlinkManager.droneState.flightMode == mode
    }
    
    var body: some View {
        Button(action: {
            mavlinkManager.setFlightMode(mode)
        }) {
            VStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? mode.color : .gray)
                
                Text(mode.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .white : .gray)
                
                Text(modeDescription)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(isSelected ? mode.color.opacity(0.2) : Color.black.opacity(0.3))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? mode.color : Color.clear, lineWidth: 2)
            )
        }
        .disabled(!mavlinkManager.isConnected)
        .opacity(mavlinkManager.isConnected ? 1 : 0.5)
    }
    
    private var modeDescription: String {
        switch mode {
        case .stabilize: return "Manual with leveling"
        case .acro: return "Full manual"
        case .altHold: return "Hold altitude"
        case .auto: return "Follow waypoints"
        case .guided: return "Computer control"
        case .loiter: return "GPS hold"
        case .rtl: return "Return home"
        case .circle: return "Circle point"
        case .land: return "Auto landing"
        case .posHold: return "Hold position"
        case .brake: return "Emergency brake"
        case .smartRTL: return "Smart return"
        default: return ""
        }
    }
}

// MARK: - Compact Mode Selector
struct CompactFlightModeSelector: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    var body: some View {
        HStack(spacing: 8) {
            CompactModeButton(mode: .stabilize)
            CompactModeButton(mode: .altHold)
            CompactModeButton(mode: .posHold)
        }
    }
}

// MARK: - Compact Mode Button
struct CompactModeButton: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    let mode: CopterFlightMode
    
    var isSelected: Bool {
        mavlinkManager.droneState.flightMode == mode
    }
    
    var body: some View {
        Button {
            mavlinkManager.setFlightMode(mode)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.title3)
                Text(mode.name)
                    .font(.caption2)
            }
            .foregroundColor(isSelected ? .cyan : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.cyan.opacity(0.2) : Color.black.opacity(0.3))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 1)
            )
        }
        .disabled(!mavlinkManager.isConnected)
    }
}

#Preview {
    FlightModeView()
        .environmentObject(MAVLinkManager.shared)
        .preferredColorScheme(.dark)
}
