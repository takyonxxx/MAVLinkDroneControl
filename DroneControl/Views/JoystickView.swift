//
//  JoystickView.swift
//  DroneControl
//

import SwiftUI

struct JoystickView: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    @State private var leftJoystickPosition: CGPoint = .zero
    @State private var rightJoystickPosition: CGPoint = .zero
    
    private let updateTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 600
            let joystickSize: CGFloat = isCompact ? 140 : 180
            
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.1)
                    .ignoresSafeArea()
                
                VStack(spacing: isCompact ? 12 : 20) {
                    StatusBar()
                        .padding(.horizontal)
                    
                    Spacer()
                    
                    // Values display
                    HStack(spacing: isCompact ? 16 : 40) {
                        ValueDisplay(
                            label: "Throttle",
                            value: Int((leftJoystickPosition.y + 1.0) * 500),
                            isCompact: isCompact
                        )
                        ValueDisplay(
                            label: "Yaw",
                            value: Int(leftJoystickPosition.x * 1000),
                            isCompact: isCompact
                        )
                        ValueDisplay(
                            label: "Pitch",
                            value: Int(rightJoystickPosition.y * 1000),
                            isCompact: isCompact
                        )
                        ValueDisplay(
                            label: "Roll",
                            value: Int(rightJoystickPosition.x * 1000),
                            isCompact: isCompact
                        )
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Joysticks
                    HStack(spacing: isCompact ? 20 : 60) {
                        // Left Joystick (Throttle/Yaw)
                        VStack(spacing: 8) {
                            JoystickControl(
                                position: $leftJoystickPosition,
                                size: joystickSize,
                                returnToCenter: false
                            )
                            Text("Throttle / Yaw")
                                .font(.system(size: isCompact ? 15 : 15, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        
                        // Right Joystick (Pitch/Roll)
                        VStack(spacing: 8) {
                            JoystickControl(
                                position: $rightJoystickPosition,
                                size: joystickSize,
                                returnToCenter: true
                            )
                            Text("Pitch / Roll")
                                .font(.system(size: isCompact ? 15 : 15, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // Reset Button
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            leftJoystickPosition = .zero
                            rightJoystickPosition = .zero
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Reset Joysticks")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.2, green: 0.4, blue: 0.8),
                                    Color(red: 0.3, green: 0.5, blue: 0.9)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, y: 4)
                    }
                    .padding(.vertical, 30)  // ✅ Üst ve alt padding eklendi
                    
                    Spacer()
                }
            }
        }
        .onReceive(updateTimer) { _ in
            sendManualControl()
        }
    }
    
    private func sendManualControl() {
        let x = Int16(rightJoystickPosition.y * 1000)
        let y = Int16(rightJoystickPosition.x * 1000)
        let z = Int16((leftJoystickPosition.y + 1.0) * 500)
        let r = Int16(leftJoystickPosition.x * 1000)
        
        mavlinkManager.sendManualControl(x: x, y: y, z: z, r: r)
    }
}

// MARK: - Joystick Control
struct JoystickControl: View {
    @Binding var position: CGPoint
    let size: CGFloat
    let returnToCenter: Bool
    
    @State private var isDragging = false
    
    var body: some View {
        ZStack {
            // Background
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.1, green: 0.1, blue: 0.15),
                            Color(red: 0.15, green: 0.15, blue: 0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            
            // Center mark
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                .frame(width: size * 0.3, height: size * 0.3)
            
            // Crosshair
            Path { path in
                path.move(to: CGPoint(x: size/2, y: 0))
                path.addLine(to: CGPoint(x: size/2, y: size))
                path.move(to: CGPoint(x: 0, y: size/2))
                path.addLine(to: CGPoint(x: size, y: size/2))
            }
            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            .frame(width: size, height: size)
            
            // Stick
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.3, green: 0.5, blue: 0.9),
                            Color(red: 0.2, green: 0.4, blue: 0.8)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.15
                    )
                )
                .frame(width: size * 0.3, height: size * 0.3)
                .shadow(color: Color.black.opacity(0.3), radius: 5, y: 3)
                .offset(
                    x: position.x * (size * 0.35),
                    y: -position.y * (size * 0.35)
                )
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    updatePosition(value.location)
                }
                .onEnded { _ in
                    isDragging = false
                    if returnToCenter {
                        withAnimation(.spring(response: 0.3)) {
                            position = .zero
                        }
                    }
                }
        )
    }
    
    private func updatePosition(_ location: CGPoint) {
        // Convert touch location to joystick coordinates
        // Center of joystick is at (size/2, size/2)
        let center = size / 2
        let dx = (location.x - center) / (size * 0.35)
        let dy = -(location.y - center) / (size * 0.35)
        
        let distance = sqrt(dx * dx + dy * dy)
        
        if distance <= 1.0 {
            position = CGPoint(x: dx, y: dy)
        } else {
            let angle = atan2(dy, dx)
            position = CGPoint(x: cos(angle), y: sin(angle))
        }
    }
}

// MARK: - Value Display
struct ValueDisplay: View {
    let label: String
    let value: Int
    let isCompact: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: isCompact ? 15 : 15))
                .foregroundColor(.gray)
            
            Text("\(value)")
                .font(.system(size: isCompact ? 20 : 20, weight: .bold, design: .monospaced))
                .foregroundColor(valueColor)
                .frame(minWidth: isCompact ? 50 : 75)
        }
    }
    
    private var valueColor: Color {
        if abs(value) < 100 { return .green }
        if abs(value) < 500 { return .orange }
        return .red
    }
}

#Preview {
    JoystickView()
        .environmentObject(MAVLinkManager.shared)
}
