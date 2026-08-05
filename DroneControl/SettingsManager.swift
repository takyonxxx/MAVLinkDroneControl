//
//  SettingsManager.swift
//  DroneControl
//
//  Manages app settings with UserDefaults persistence
//

import Foundation

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
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
    
    // Gamepad ayarları
    @Published var gamepadDeadzone: Float {
        didSet {
            UserDefaults.standard.set(gamepadDeadzone, forKey: "gamepadDeadzone")
        }
    }
    
    @Published var gamepadHoldThrottle: Bool {
        didSet {
            UserDefaults.standard.set(gamepadHoldThrottle, forKey: "gamepadHoldThrottle")
        }
    }
    
    // Throttle artış/azalış hızı (0.01 - 0.10 arası)
    @Published var throttleSpeed: Float {
        didSet {
            UserDefaults.standard.set(throttleSpeed, forKey: "throttleSpeed")
        }
    }
    
    private init() {
        let savedDeadzone = UserDefaults.standard.float(forKey: "gamepadDeadzone")
        let savedHoldThrottle = UserDefaults.standard.object(forKey: "gamepadHoldThrottle") as? Bool
        let savedThrottleSpeed = UserDefaults.standard.float(forKey: "throttleSpeed")
        
        self.connectionHost = UserDefaults.standard.string(forKey: "connectionHost") ?? "192.168.4.1"
        self.connectionPort = UserDefaults.standard.string(forKey: "connectionPort") ?? "14550"
        self.gamepadDeadzone = savedDeadzone > 0 ? savedDeadzone : 0.1
        self.gamepadHoldThrottle = savedHoldThrottle ?? true
        self.throttleSpeed = savedThrottleSpeed > 0 ? savedThrottleSpeed : 0.010
    }
    
    func resetToDefaults() {
        connectionHost = "192.168.4.1"
        connectionPort = "14550"
        gamepadDeadzone = 0.1
        gamepadHoldThrottle = true
        throttleSpeed = 0.010
    }
    
    func clearAllSettings() {
        UserDefaults.standard.removeObject(forKey: "connectionHost")
        UserDefaults.standard.removeObject(forKey: "connectionPort")
        UserDefaults.standard.removeObject(forKey: "gamepadDeadzone")
        UserDefaults.standard.removeObject(forKey: "gamepadHoldThrottle")
        UserDefaults.standard.removeObject(forKey: "throttleSpeed")
        resetToDefaults()
    }
}
