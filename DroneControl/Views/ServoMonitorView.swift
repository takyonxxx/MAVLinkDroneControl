//
//  ServoMonitorView.swift
//  DroneControl
//
//  Servo output monitoring and control
//

import SwiftUI

struct ServoMonitorView: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Servo grid
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(1...16, id: \.self) { channel in
                            ServoCard(
                                channel: channel,
                                value: mavlinkManager.servoValues[channel] ?? 0
                            )
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
            .navigationTitle("Servo Monitor")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

// MARK: - Servo Card
struct ServoCard: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    let channel: Int
    let value: UInt16
    
    @State private var showingControl = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Channel header
            HStack {
                Text("CH \(channel)")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Control button
                Button(action: {
                    showingControl.toggle()
                }) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.cyan)
                }
            }
            
            // PWM value display
            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(pwmColor)
                
                Text("μs")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            // Visual bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                    
                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(pwmColor)
                        .frame(width: geometry.size.width * normalizedValue)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
        .sheet(isPresented: $showingControl) {
            ServoControlSheet(channel: channel, currentValue: value)
                .environmentObject(mavlinkManager)
        }
    }
    
    private var normalizedValue: CGFloat {
        // PWM typically 1000-2000μs, normalize to 0-1
        let minPWM: CGFloat = 1000
        let maxPWM: CGFloat = 2000
        let normalized = (CGFloat(value) - minPWM) / (maxPWM - minPWM)
        return max(0, min(1, normalized))
    }
    
    private var pwmColor: Color {
        if value == 0 {
            return .gray
        } else if value < 1100 {
            return .red
        } else if value > 1900 {
            return .orange
        } else {
            return .green
        }
    }
}

// MARK: - Servo Control Sheet
struct ServoControlSheet: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    @Environment(\.dismiss) var dismiss
    
    let channel: Int
    let currentValue: UInt16
    
    @State private var pwmValue: Double
    
    init(channel: Int, currentValue: UInt16) {
        self.channel = channel
        self.currentValue = currentValue
        _pwmValue = State(initialValue: Double(currentValue > 0 ? currentValue : 1500))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Current value
                VStack(spacing: 8) {
                    Text("Channel \(channel)")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("\(Int(pwmValue)) μs")
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                }
                .padding(.top, 40)
                
                // Slider
                VStack(spacing: 16) {
                    HStack {
                        Text("1000 μs")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        Text("2000 μs")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Slider(value: $pwmValue, in: 1000...2000, step: 10)
                        .accentColor(.cyan)
                    
                    // Preset buttons
                    HStack(spacing: 12) {
                        PresetButton(title: "Min", value: 1000, pwmValue: $pwmValue)
                        PresetButton(title: "Center", value: 1500, pwmValue: $pwmValue)
                        PresetButton(title: "Max", value: 2000, pwmValue: $pwmValue)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        mavlinkManager.setServo(channel: UInt8(channel), pwm: UInt16(pwmValue))
                        dismiss()
                    }) {
                        Text("Set PWM")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.cyan)
                            .cornerRadius(12)
                    }
                    
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray)
                            .cornerRadius(12)
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
            .navigationTitle("Servo Control")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            #endif
        }
    }
}

// MARK: - Preset Button
struct PresetButton: View {
    let title: String
    let value: Double
    @Binding var pwmValue: Double
    
    var body: some View {
        Button(action: {
            pwmValue = value
        }) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.cyan.opacity(0.3))
                .cornerRadius(8)
        }
    }
}

// MARK: - Compact Servo Monitor
struct CompactServoMonitor: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    let channels: [Int]
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Servos")
                .font(.headline)
                .foregroundColor(.white)
            
            ForEach(channels, id: \.self) { channel in
                HStack {
                    Text("CH\(channel)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(width: 40, alignment: .leading)
                    
                    let value = mavlinkManager.servoValues[channel] ?? 0
                    
                    // Bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.2))
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(value > 0 ? Color.green : Color.gray)
                                .frame(width: geometry.size.width * normalizedValue(value))
                        }
                    }
                    .frame(height: 4)
                    
                    Text("\(value)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }
    
    private func normalizedValue(_ value: UInt16) -> CGFloat {
        let minPWM: CGFloat = 1000
        let maxPWM: CGFloat = 2000
        let normalized = (CGFloat(value) - minPWM) / (maxPWM - minPWM)
        return max(0, min(1, normalized))
    }
}

#Preview {
    ServoMonitorView()
        .environmentObject(MAVLinkManager.shared)
        .preferredColorScheme(.dark)
}
