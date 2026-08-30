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
            
            // Flight Modes
            FlightModeView()
                .tabItem {
                    Label("Modes", systemImage: "airplane")
                }
                .tag(2)
            
            // Map View
            EnhancedMapView(mavlinkManager: MAVLinkManager.shared)
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(3)
            
            // Servo Monitor
            ServoMonitorView()
                .tabItem {
                    Label("Servos", systemImage: "slider.horizontal.3")
                }
                .tag(4)
            
            // Parameters
            ParametersView()
                .tabItem {
                    Label("Params", systemImage: "list.bullet.rectangle")
                }
                .tag(5)
            
            // Messages (STATUSTEXT + EKF health)
            MessagesView()
                .tabItem {
                    Label("Messages", systemImage: "text.bubble")
                }
                .tag(6)
            
            // Settings
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(7)
        }
        .accentColor(.cyan)
    }
}

#Preview {
    ContentView()
        .environmentObject(MAVLinkManager.shared)
}
