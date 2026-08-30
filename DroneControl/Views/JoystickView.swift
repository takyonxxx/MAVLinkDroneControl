//
//  JoystickView.swift
//  DroneControl
//
//  Touch joystick (iOS) + Gamepad support (macOS)
//

import SwiftUI
import GameController

struct JoystickView: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    @ObservedObject var gamepadManager = GamepadManager.shared
    
    // Touch joystick pozisyonları
    @State private var leftJoystickPosition: CGPoint = CGPoint(x: 0, y: -1)  // Throttle minimum'da başlar
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
                    
                    // Gamepad Status (both platforms)
                    GamepadStatusView()
                        .padding(.horizontal)
                    
                    // Battery info (same as dashboard: Voltage / Current / Charge)
                    BatteryBar()
                        .padding(.horizontal)
                    
                    // Flight telemetry: Heading / Alt AGL / Speed
                    FlightTelemetryBar(isCompact: isCompact)
                        .padding(.horizontal)
                    
                    // GPS info: Fix / Satellites / HDOP
                    GPSInfoBar(isCompact: isCompact)
                        .padding(.horizontal)
                    
                    Spacer()
                    
                    // Values display
                    HStack(spacing: isCompact ? 16 : 40) {
                        ValueDisplay(
                            label: "Throttle",
                            value: throttleValue,
                            isCompact: isCompact
                        )
                        ValueDisplay(
                            label: "Yaw",
                            value: yawValue,
                            isCompact: isCompact
                        )
                        ValueDisplay(
                            label: "Pitch",
                            value: pitchValue,
                            isCompact: isCompact
                        )
                        ValueDisplay(
                            label: "Roll",
                            value: rollValue,
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
                                returnToCenterX: true,   // yaw birakinca ortalanir
                                returnToCenterY: false   // throttle son degerde kalir
                            )
                            Text("Throttle / Yaw")
                                .font(.system(size: isCompact ? 13 : 14, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        
                        // Right Joystick (Pitch/Roll)
                        VStack(spacing: 8) {
                            JoystickControl(
                                position: $rightJoystickPosition,
                                size: joystickSize,
                                returnToCenterX: true,
                                returnToCenterY: true
                            )
                            Text("Pitch / Roll")
                                .font(.system(size: isCompact ? 13 : 14, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // Control Buttons
                    HStack(spacing: 20) {
                        // Reset Button
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                leftJoystickPosition = CGPoint(x: 0, y: -1)
                                rightJoystickPosition = .zero
                                gamepadManager.resetAll()
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Reset")
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
                        #if os(macOS)
                        .buttonStyle(.plain)
                        #endif
                        
                        // Arm/Disarm Toggle Button
                        Button(action: {
                            if mavlinkManager.isArmed {
                                mavlinkManager.disarmVehicle(force: false)
                            } else {
                                mavlinkManager.armVehicle(force: false)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: mavlinkManager.isArmed ? "power.circle.fill" : "power")
                                    .font(.system(size: 16, weight: .semibold))
                                Text(mavlinkManager.isArmed ? "DISARM" : "ARM")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: mavlinkManager.isArmed ? [
                                        Color(red: 0.8, green: 0.2, blue: 0.2),
                                        Color(red: 0.9, green: 0.3, blue: 0.3)
                                    ] : [
                                        Color(red: 0.2, green: 0.7, blue: 0.3),
                                        Color(red: 0.3, green: 0.8, blue: 0.4)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                            .shadow(color: mavlinkManager.isArmed ? Color.red.opacity(0.3) : Color.green.opacity(0.3), radius: 8, y: 4)
                        }
                        #if os(macOS)
                        .buttonStyle(.plain)
                        #endif
                    }
                    .padding(.vertical, 30)
                    
                    Spacer()
                }
            }
        }
        .onReceive(updateTimer) { _ in
            syncGamepadValues()
            sendManualControl()
        }
    }
    
    // Gamepad değerlerini touch joystick ile senkronize et
    private func syncGamepadValues() {
        if gamepadManager.isControllerConnected {
            // Gamepad bağlıysa, gamepad değerlerini kullan
            leftJoystickPosition = CGPoint(
                x: CGFloat(gamepadManager.leftStickX),
                y: CGFloat(gamepadManager.leftStickY)
            )
            rightJoystickPosition = CGPoint(
                x: CGFloat(gamepadManager.rightStickX),
                y: CGFloat(gamepadManager.rightStickY)
            )
        }
    }
    
    // Hesaplanan değerler
    private var throttleValue: Int {
        if gamepadManager.isControllerConnected {
            return Int((gamepadManager.leftStickY + 1.0) * 500)
        }
        return Int((leftJoystickPosition.y + 1.0) * 500)
    }
    
    private var yawValue: Int {
        if gamepadManager.isControllerConnected {
            return Int(gamepadManager.leftStickX * 1000)
        }
        return Int(leftJoystickPosition.x * 1000)
    }
    
    private var pitchValue: Int {
        if gamepadManager.isControllerConnected {
            return Int(gamepadManager.rightStickY * 1000)
        }
        return Int(rightJoystickPosition.y * 1000)
    }
    
    private var rollValue: Int {
        if gamepadManager.isControllerConnected {
            return Int(gamepadManager.rightStickX * 1000)
        }
        return Int(rightJoystickPosition.x * 1000)
    }
    
    private func sendManualControl() {
        let x: Int16
        let y: Int16
        let z: Int16
        let r: Int16
        
        if gamepadManager.isControllerConnected {
            let values = gamepadManager.getManualControlValues()
            x = values.x
            y = values.y
            z = values.z
            r = values.r
        } else {
            x = Int16(rightJoystickPosition.y * 1000)
            y = Int16(rightJoystickPosition.x * 1000)
            z = Int16((leftJoystickPosition.y + 1.0) * 500)
            r = Int16(leftJoystickPosition.x * 1000)
        }
        
        mavlinkManager.sendManualControl(x: x, y: y, z: z, r: r)
    }
}

// MARK: - GPS Info Bar (Fix / Satellites / HDOP)
struct GPSInfoBar: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    let isCompact: Bool
    
    private var fixName: String {
        let names = ["No GPS", "No Fix", "2D Fix", "3D Fix", "DGPS", "RTK Float", "RTK Fixed"]
        let t = Int(mavlinkManager.gpsFixType)
        return t < names.count ? names[t] : "Unknown"
    }
    
    private var fixColor: Color {
        if mavlinkManager.gpsFixType >= 3 { return .green }
        if mavlinkManager.gpsSatellites > 0 { return .yellow }
        return .red
    }
    
    private var hdopColor: Color {
        let h = mavlinkManager.gpsHdop
        if h < 1.5 { return .green }
        if h < 3.0 { return .yellow }
        return .red
    }
    
    private var hdopText: String {
        mavlinkManager.gpsHdop >= 99 ? "--" : String(format: "%.2f", mavlinkManager.gpsHdop)
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Fix type
            BatteryInfoItem(
                icon: mavlinkManager.gpsFixType >= 3 ? "location.fill" : "location.slash",
                label: "GPS Fix",
                value: fixName,
                color: fixColor
            )
            
            Divider()
                .frame(height: 28)
                .background(Color.gray.opacity(0.3))
            
            // Satellite count
            BatteryInfoItem(
                icon: "antenna.radiowaves.left.and.right",
                label: "Satellites",
                value: "\(mavlinkManager.gpsSatellites)",
                color: fixColor
            )
            
            Divider()
                .frame(height: 28)
                .background(Color.gray.opacity(0.3))
            
            // HDOP
            BatteryInfoItem(
                icon: "scope",
                label: "HDOP",
                value: hdopText,
                color: hdopColor
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
}

// MARK: - Flight Telemetry Bar (Heading / Alt AGL / Speed)
struct FlightTelemetryBar: View {
    @EnvironmentObject var mavlinkManager: MAVLinkManager
    let isCompact: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            // Heading
            BatteryInfoItem(
                icon: "safari.fill",
                label: "Heading",
                value: String(format: "%.0f°", mavlinkManager.heading),
                color: .cyan
            )
            
            Divider()
                .frame(height: 28)
                .background(Color.gray.opacity(0.3))
            
            // Altitude AGL (yerden yukseklik) - GPS fix varsa GPS, yoksa barometre
            BatteryInfoItem(
                icon: "arrow.up.to.line",
                label: mavlinkManager.isUsingGPSSource ? "Alt AGL (GPS)" : "Alt AGL (Baro)",
                value: String(format: "%.1fm", mavlinkManager.displayAltitude),
                color: .green
            )
            
            Divider()
                .frame(height: 28)
                .background(Color.gray.opacity(0.3))
            
            // Speed (km/h) - GPS fix varsa GPS, yoksa IMU olu-hesap
            BatteryInfoItem(
                icon: "speedometer",
                label: mavlinkManager.isUsingGPSSource ? "Speed (GPS)" : "Speed (IMU)",
                value: String(format: "%.1f km/h", mavlinkManager.displaySpeed * 3.6),
                color: .orange
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
}

// MARK: - Gamepad Status View
struct GamepadStatusView: View {
    @ObservedObject var gamepadManager = GamepadManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: gamepadManager.isControllerConnected ? "gamecontroller.fill" : "gamecontroller")
                    .font(.system(size: 20))
                    .foregroundColor(gamepadManager.isControllerConnected ? .green : .gray)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(gamepadManager.isControllerConnected ? "Gamepad Connected" : "No Gamepad")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(gamepadManager.controllerName)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            
            if gamepadManager.isControllerConnected {
                // Axis values
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("L-X")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Text(String(format: "%.2f", gamepadManager.leftStickX))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(abs(gamepadManager.leftStickX) > 0.1 ? .orange : .white)
                    }
                    VStack(spacing: 2) {
                        Text("L-Y")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Text(String(format: "%.2f", gamepadManager.leftStickY))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(abs(gamepadManager.leftStickY) > 0.1 ? .orange : .white)
                    }
                    VStack(spacing: 2) {
                        Text("R-X")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Text(String(format: "%.2f", gamepadManager.rightStickX))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(abs(gamepadManager.rightStickX) > 0.1 ? .orange : .white)
                    }
                    VStack(spacing: 2) {
                        Text("R-Y")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Text(String(format: "%.2f", gamepadManager.rightStickY))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(abs(gamepadManager.rightStickY) > 0.1 ? .orange : .white)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
        .cornerRadius(10)
    }
}

// MARK: - Joystick Control
struct JoystickControl: View {
    @Binding var position: CGPoint
    let size: CGFloat
    let returnToCenterX: Bool   // birakinca X ekseni ortalansin mi
    let returnToCenterY: Bool   // birakinca Y ekseni ortalansin mi
    
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
                    if returnToCenterX || returnToCenterY {
                        withAnimation(.spring(response: 0.3)) {
                            position = CGPoint(
                                x: returnToCenterX ? 0 : position.x,
                                y: returnToCenterY ? 0 : position.y
                            )
                        }
                    }
                }
        )
    }
    
    private func updatePosition(_ location: CGPoint) {
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
                .font(.system(size: isCompact ? 12 : 14))
                .foregroundColor(.gray)
            
            Text("\(value)")
                .font(.system(size: isCompact ? 18 : 22, weight: .bold, design: .monospaced))
                .foregroundColor(valueColor)
                .frame(minWidth: isCompact ? 50 : 70)
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
