//
//  ContentView.swift
//  DroneControl
//
//  Cross-platform iOS/macOS - VLC/RTSP removed
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // --- Ana sekmeler (iOS'ta ilk 4 tab bar'da gorunur) ---
            
            // Dashboard
            MainDashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "gauge")
                }
                .tag(0)
            
            // Control (joystick + arm)
            JoystickView()
                .tabItem {
                    Label("Control", systemImage: "gamecontroller")
                }
                .tag(1)
            
            // Motor Test (MAV_CMD_DO_MOTOR_TEST)
            MotorTestView()
                .tabItem {
                    Label("Motors", systemImage: "fanblades")
                }
                .tag(2)
            
            // Flight Modes
            FlightModeView()
                .tabItem {
                    Label("Modes", systemImage: "airplane")
                }
                .tag(3)
            
            // --- "More" altindakiler ---
            
            // Map View
            EnhancedMapView(mavlinkManager: MAVLinkManager.shared)
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(4)
            
            // Servo Monitor
            ServoMonitorView()
                .tabItem {
                    Label("Servos", systemImage: "slider.horizontal.3")
                }
                .tag(5)
            
            // Parameters
            ParametersView()
                .tabItem {
                    Label("Params", systemImage: "list.bullet.rectangle")
                }
                .tag(6)
            
            // Messages (STATUSTEXT + EKF health)
            MessagesView()
                .tabItem {
                    Label("Messages", systemImage: "text.bubble")
                }
                .tag(7)
            
            // Sensor calibration (compass / gyro / baro)
            CalibrationView()
                .tabItem {
                    Label("Calibrate", systemImage: "scope")
                }
                .tag(10)
            
            // Settings
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(8)
            
            // GPS raw data / diagnostics
            GPSView()
                .tabItem {
                    Label("GPS", systemImage: "location.north.circle")
                }
                .tag(9)
        }
        .accentColor(.cyan)
    }
}

#Preview {
    ContentView()
        .environmentObject(MAVLinkManager.shared)
}
