//
//  SettingsManager.swift
//  DroneControl
//
//  Manages app settings with UserDefaults persistence
//

import Foundation

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    // Published properties that auto-save on change
    @Published var rtspURL: String {
        didSet {
            UserDefaults.standard.set(rtspURL, forKey: "rtspURL")
        }
    }
    
    @Published var connectionHost: String {
        didSet {
            UserDefaults.standard.set(connectionHost, forKey: "connectionHost")
        }
    }
    
    @Published var connectionPort: String {
        didSet {
            UserDefaults.standard.set(connectionPort, forKey: "connectionPort")
        }
    }
    
    private init() {
        // Load saved values or use defaults
        self.rtspURL = UserDefaults.standard.string(forKey: "rtspURL") ?? "rtsp://192.168.4.1:554/stream"
        self.connectionHost = UserDefaults.standard.string(forKey: "connectionHost") ?? "192.168.4.1"
        self.connectionPort = UserDefaults.standard.string(forKey: "connectionPort") ?? "14550"
    }
    
    // Reset to defaults
    func resetToDefaults() {
        rtspURL = "rtsp://192.168.4.1:554/stream"
        connectionHost = "192.168.4.1"
        connectionPort = "14550"
    }
}
