//
//  ContentView.swift
//  DroneControl
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
            
            // Control Panel
            ControlPanelView()
                .tabItem {
                    Label("Control", systemImage: "gamecontroller")
                }
                .tag(1)
            
            // Joystick
            JoystickView()
                .tabItem {
                    Label("Joystick", systemImage: "move.3d")
                }
                .tag(2)
            
            // Video Stream (RTSP) - NavigationView REMOVED! ✅
            NavigationView {
                RTSPPlayerView(mavlinkManager: MAVLinkManager.shared)
                }
                .tabItem {
                    Label("Video", systemImage: "video.fill")
                }
                .tag(3)
            
            // Flight Modes
            FlightModeView()
                .tabItem {
                    Label("Modes", systemImage: "airplane")
                }
                .tag(4)
            
            // Map View
            EnhancedMapView(mavlinkManager: MAVLinkManager.shared)
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(5)
            
            // Servo Monitor
            ServoMonitorView()
                .tabItem {
                    Label("Servos", systemImage: "slider.horizontal.3")
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
