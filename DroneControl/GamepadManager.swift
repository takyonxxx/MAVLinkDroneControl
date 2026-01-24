//
//  GamepadManager.swift
//  DroneControl
//
//  DEBUG VERSION - Sadece buton logları
//

import Foundation
import Combine

#if os(macOS)
import IOKit
import IOKit.hid

class GamepadManager: ObservableObject {
    static let shared = GamepadManager()
    
    @Published var leftStickX: Float = 0.0
    @Published var leftStickY: Float = -1.0
    @Published var rightStickX: Float = 0.0
    @Published var rightStickY: Float = 0.0
    
    @Published var button4Pressed: Bool = false
    @Published var button6Pressed: Bool = false
    
    @Published var isControllerConnected: Bool = false
    @Published var controllerName: String = "No Controller"
    
    var deadzone: Float = 0.1
    var holdThrottle: Bool = true
    var throttleSpeed: Float = 0.03
    
    private var hidManager: IOHIDManager?
    private var connectedDevice: IOHIDDevice?
    private var pollingTimer: Timer?
    private var previousValues: [String: Int] = [:]
    private var axisRanges: [Int: (min: Int, max: Int)] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // ============================================
    // BUTON AKSIYONLARI
    // ============================================
    private func handleButtonAction(page: UInt32, usage: UInt32) {
        // Page 9 = Button Page
        if page == 9 {
            switch usage {
            case 10:  // START - ARM
                MAVLinkManager.shared.arm()
                
            case 9:   // BACK - DISARM
                MAVLinkManager.shared.disarm()
                
            case 11, 12:  // L3/R3 - RESET
                resetAll()
                
            default:
                break
            }
        }
    }
    
    private init() {
        // SettingsManager'dan ayarları al
        let settings = SettingsManager.shared
        self.deadzone = settings.gamepadDeadzone
        self.holdThrottle = settings.gamepadHoldThrottle
        self.throttleSpeed = settings.throttleSpeed
        
        // Ayar değişikliklerini dinle
        settings.$gamepadDeadzone
            .sink { [weak self] value in
                self?.deadzone = value
            }
            .store(in: &cancellables)
        
        settings.$gamepadHoldThrottle
            .sink { [weak self] value in
                self?.holdThrottle = value
            }
            .store(in: &cancellables)
        
        settings.$throttleSpeed
            .sink { [weak self] value in
                self?.throttleSpeed = value
            }
            .store(in: &cancellables)
        
        setupHIDManager()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.scanDevices()
        }
    }
    
    deinit {
        pollingTimer?.invalidate()
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
    
    private func setupHIDManager() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else { return }
        
        IOHIDManagerSetDeviceMatching(manager, nil)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
    
    private func scanDevices() {
        guard let manager = hidManager,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return
        }
        
        for device in devices {
            let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
            let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
            let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
            
            // Joystick (4) veya Gamepad (5)
            if usagePage == 1 && (usage == 4 || usage == 5) {
                connectDevice(device, name: name)
                break
            }
        }
    }
    
    private func connectDevice(_ device: IOHIDDevice, name: String) {
        connectedDevice = device
        
        DispatchQueue.main.async {
            self.isControllerConnected = true
            self.controllerName = name
        }
        
        print("🎮 Controller connected: \(name)")
        
        // Element analizi
        if let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] {
            for element in elements {
                let page = IOHIDElementGetUsagePage(element)
                let usage = IOHIDElementGetUsage(element)
                let min = IOHIDElementGetLogicalMin(element)
                let max = IOHIDElementGetLogicalMax(element)
                
                if page == kHIDPage_GenericDesktop && usage >= 0x30 && usage <= 0x39 {
                    axisRanges[Int(usage)] = (min: min, max: max)
                }
            }
        }
        
        // Polling başlat
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.pollInputs()
        }
    }
    
    // ============================================
    // POLLING - TÜM INPUTLARI OKUR
    // ============================================
    private func pollInputs() {
        guard let device = connectedDevice,
              let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
            return
        }
        
        for element in elements {
            let page = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            
            // Element değerini al
            var pValue: Unmanaged<IOHIDValue>?
            let result = withUnsafeMutablePointer(to: &pValue) { ptr -> IOReturn in
                return ptr.withMemoryRebound(to: Unmanaged<IOHIDValue>.self, capacity: 1) { nonOptPtr in
                    return IOHIDDeviceGetValue(device, element, nonOptPtr)
                }
            }
            
            guard result == kIOReturnSuccess, let hidValue = pValue?.takeUnretainedValue() else {
                continue
            }
            
            let value = Int(IOHIDValueGetIntegerValue(hidValue))
            let key = "\(page)-\(usage)"
            let prev = previousValues[key] ?? 0
            
            // Axis değerlerini HER ZAMAN güncelle (throttle increment için gerekli)
            if page == kHIDPage_GenericDesktop {
                updateAxis(usage: Int(usage), value: value)
            }
            
            // Butonları sadece değiştiğinde işle
            if value != prev {
                previousValues[key] = value
                
                if value > 0 && prev == 0 {
                    let isAxis = (page == kHIDPage_GenericDesktop && usage >= 0x30 && usage <= 0x39)
                    if !isAxis {
                        handleButtonAction(page: page, usage: usage)
                    }
                }
            }
        }
    }
    
    private func updateAxis(usage: Int, value: Int) {
        let normalized: Float
        if let range = axisRanges[usage] {
            let mid = (range.max + range.min) / 2
            let half = (range.max - range.min) / 2
            normalized = half > 0 ? Float(value - mid) / Float(half) : 0
        } else {
            normalized = (Float(value) - 127.5) / 127.5
        }
        
        let final = abs(normalized) < deadzone ? 0 : normalized
        
        DispatchQueue.main.async {
            switch usage {
            case 0x30: self.leftStickX = final      // X - Yaw
            case 0x31:
                // Y - Throttle
                if self.holdThrottle {
                    // INCREMENT MODE: Joystick yukarı tutulursa sürekli artar
                    let delta = -final * self.throttleSpeed
                    self.leftStickY = max(-1.0, min(1.0, self.leftStickY + delta))
                } else {
                    // DIRECT MODE: Joystick pozisyonu = throttle değeri
                    self.leftStickY = -final
                }
                
            case 0x32: self.rightStickX = final     // Z - Roll
            case 0x35: self.rightStickY = -final    // Rz - Pitch
            default: break
            }
        }
    }
    
    func getManualControlValues() -> (x: Int16, y: Int16, z: Int16, r: Int16) {
        return (
            Int16(rightStickY * 1000),
            Int16(rightStickX * 1000),
            Int16((leftStickY + 1.0) * 500),
            Int16(leftStickX * 1000)
        )
    }
    
    func resetAll() {
        DispatchQueue.main.async {
            self.leftStickX = 0
            self.leftStickY = -1
            self.rightStickX = 0
            self.rightStickY = 0
        }
    }
    
    func setThrottle(_ value: Float) {
        DispatchQueue.main.async {
            self.leftStickY = max(-1, min(1, value))
        }
    }
    
    func refreshControllers() {
        scanDevices()
    }
}

#else
// iOS
import GameController

class GamepadManager: ObservableObject {
    static let shared = GamepadManager()
    
    @Published var leftStickX: Float = 0.0
    @Published var leftStickY: Float = -1.0
    @Published var rightStickX: Float = 0.0
    @Published var rightStickY: Float = 0.0
    @Published var button4Pressed: Bool = false
    @Published var button6Pressed: Bool = false
    @Published var isControllerConnected: Bool = false
    @Published var controllerName: String = "No Controller"
    
    var deadzone: Float = 0.1
    var holdThrottle: Bool = false
    
    private init() {}
    
    func getManualControlValues() -> (x: Int16, y: Int16, z: Int16, r: Int16) {
        return (0, 0, 500, 0)
    }
    
    func resetAll() {}
    func setThrottle(_ value: Float) {}
    func refreshControllers() {}
}
#endif
