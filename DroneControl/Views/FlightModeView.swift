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
        ScrollView {
            VStack(spacing: 16) {
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
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(availableModes, id: \.self) { mode in
                        FlightModeButton(mode: mode)
                    }
                }
                
                // ARMING_CHECK toggle (device-synced)
                ArmingCheckToggleButton()
                    .padding(.bottom, 24)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            VStack(spacing: 6) {
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
            .padding(.vertical, 12)
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

// MARK: - ARMING_CHECK Toggle Button
// Cihazdaki ARMING_CHECK degerini gosterir ve basinca toggle eder.
// Gosterilen deger her zaman cihazin geri yayinladigi (echo) degerdir;
// yazma sonrasi buton ancak FC yeni degeri onaylayinca degisir.
struct ArmingCheckToggleButton: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    private let paramName = "ARMING_CHECK"
    @State private var writePending = false
    private let refreshTimer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()
    
    private var deviceValue: Float? {
        mavlinkManager.parameters[paramName]
    }
    
    private var isEnabled: Bool? {
        guard let v = deviceValue else { return nil }
        return v != 0
    }
    
    private var title: String {
        switch isEnabled {
        case .some(true):
            let v = deviceValue ?? 1
            let detail = v == 1 ? "" : String(format: " (mask: %.0f)", v)
            return "Arming Checks: ENABLED" + detail
        case .some(false):
            return "Arming Checks: DISABLED"
        case .none:
            return mavlinkManager.isConnected ? "Arming Checks: reading..." : "Arming Checks: not connected"
        }
    }
    
    private var subtitle: String {
        switch isEnabled {
        case .some(true): return "Tap to disable all pre-arm checks"
        case .some(false): return "Unsafe! Tap to re-enable pre-arm checks"
        case .none: return "Waiting for device value"
        }
    }
    
    private var colors: [Color] {
        switch isEnabled {
        case .some(true):
            return [Color(red: 0.2, green: 0.7, blue: 0.3), Color(red: 0.3, green: 0.8, blue: 0.4)]
        case .some(false):
            return [Color(red: 0.8, green: 0.2, blue: 0.2), Color(red: 0.9, green: 0.3, blue: 0.3)]
        case .none:
            return [Color.gray.opacity(0.5), Color.gray.opacity(0.4)]
        }
    }
    
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: isEnabled == false ? "shield.slash.fill" : "shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .opacity(0.85)
                }
                
                Spacer()
                
                if writePending {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                        .opacity(0.8)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == nil)
        .onAppear {
            mavlinkManager.requestParameter(name: paramName)
        }
        .onReceive(refreshTimer) { _ in
            // Cihazla senkron kal: MP gibi baska bir GCS degistirse de goruruz
            if mavlinkManager.isConnected {
                mavlinkManager.requestParameter(name: paramName)
            }
        }
        .onChange(of: deviceValue) { _ in
            writePending = false     // FC yeni degeri yayinladi, yazma onaylandi
        }
    }
    
    private func toggle() {
        guard let enabled = isEnabled else { return }
        writePending = true
        mavlinkManager.setParameter(name: paramName, value: enabled ? 0 : 1)
        // Echo gelmezse birkac saniye icinde tekrar sorgula (timer zaten yapiyor)
    }
}

#Preview {
    FlightModeView()
        .environmentObject(MAVLinkManager.shared)
        .preferredColorScheme(.dark)
}
