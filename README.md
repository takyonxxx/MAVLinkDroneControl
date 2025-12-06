# 🚁 DroneControl

**Professional iOS Drone Control Application with MAVLink v2 Protocol**

A native iOS application for controlling ArduPilot-based drones (Copter, Plane, Rover, Sub) with real-time telemetry, attitude visualization, and manual control capabilities.

---

## ✨ Features

### 🔌 MAVLink v2 Integration
- Full MAVLink v2 protocol support
- UDP connection (WiFi/4G)
- Real-time bidirectional communication
- Automatic telemetry stream management
- Parameter read/write capability

### 📊 Real-Time Dashboard
- **Artificial Horizon (HSI)** with pitch ladder and compass rose
- Live battery monitoring (Voltage, Current, Remaining %)
- GPS status and satellite count
- Altitude, speed, and climb rate telemetry
- Motor PWM outputs visualization (M1-M4)
- Roll, Pitch, Yaw attitude display

### 🎮 Manual Control
- Dual joystick interface (Throttle/Yaw, Pitch/Roll)
- Precise touch control with visual feedback
- One-tap reset to center position
- Real-time control value display

### ✈️ Flight Modes
- 28 ArduPilot flight modes support
- Visual mode selection interface
- Current mode indicator
- Quick mode switching

### ⚙️ Vehicle Control
- ARM/DISARM commands
- Flight mode changes
- Quick actions:
  - Hold Position
  - Return Home
  - Land
  - Hold Altitude

### 📡 Servo Monitor
- 16-channel PWM monitoring
- Color-coded status indicators
- Real-time value updates
- Visual progress bars

---

## 📱 Screenshots

### Dashboard
<img src="https://raw.githubusercontent.com/takyonxxx/MAVLinkDroneControl/main/images/Ekran%20Resmi%202025-12-06%20-%2015.58.55.png" width="300">

### Joystick Control
<img src="https://raw.githubusercontent.com/takyonxxx/MAVLinkDroneControl/main/images/Ekran%20Resmi%202025-12-06%20-%2016.00.00.png" width="300">

### Control Panel
<img src="https://raw.githubusercontent.com/takyonxxx/MAVLinkDroneControl/main/images/Ekran%20Resmi%202025-12-06%20-%2015.59.38.png" width="300">

### Flight Modes
<img src="https://raw.githubusercontent.com/takyonxxx/MAVLinkDroneControl/main/images/Ekran%20Resmi%202025-12-06%20-%2016.00.39.png" width="300">

### Servo Monitor
<img src="https://raw.githubusercontent.com/takyonxxx/MAVLinkDroneControl/main/images/Ekran%20Resmi%202025-12-06%20-%2016.01.17.png" width="300">

*16-channel servo output monitoring*

---

## 🛠 Technologies

- **Swift** - Native iOS development
- **SwiftUI** - Modern declarative UI framework
- **MAVLink v2** - Communication protocol
- **ArduPilot** - Compatible with Copter, Plane, Rover, Sub
- **UDP Networking** - Real-time data transmission

---

## 📋 Requirements

- iOS 16.0+
- iPhone/iPad
- ArduPilot-based vehicle with MAVLink support
- WiFi/4G connection to vehicle

---

## 🚀 Installation

### Clone Repository
```bash
git clone https://github.com/yourusername/DroneControl.git
cd DroneControl
```

### Open in Xcode
```bash
open DroneControl.xcodeproj
```

### Build and Run
1. Select your target device (iPhone/iPad)
2. Press `⌘ + R` to build and run
3. Configure connection settings (IP: 192.168.4.1, Port: 14550)
4. Connect to your vehicle

---

## 📖 Usage

### 1. Connect to Vehicle
- Launch the app
- Navigate to Settings tab
- Enter vehicle IP address (default: 192.168.4.1)
- Port: 14550 (MAVLink default)
- Connection status will show "Connected" when successful

### 2. Monitor Telemetry
- Dashboard tab shows real-time data:
  - Attitude (Roll, Pitch, Yaw)
  - Battery status
  - GPS information
  - Motor outputs
  - Speed and altitude

### 3. Control Vehicle
- **Manual Control**: Use Joystick tab for direct control
- **ARM/DISARM**: Use Control tab
- **Flight Modes**: Switch modes from Modes tab
- **Quick Actions**: Execute common commands

---

## 🎯 Key Features

### MAVLink Protocol
- ✅ HEARTBEAT messages
- ✅ SYS_STATUS (Battery)
- ✅ GPS_RAW_INT
- ✅ ATTITUDE
- ✅ GLOBAL_POSITION_INT
- ✅ SERVO_OUTPUT_RAW
- ✅ VFR_HUD
- ✅ COMMAND_LONG
- ✅ SET_MESSAGE_INTERVAL
- ✅ PARAM_VALUE/SET
- ✅ MANUAL_CONTROL

### Telemetry
- Real-time attitude visualization
- Battery monitoring with alerts
- GPS fix status
- Motor PWM outputs
- Speed and climb rate

### Safety
- Connection watchdog
- Heartbeat monitoring
- Command acknowledgment
- Armed state indicators

---

## 🔧 Configuration

### Connection Settings
Default MAVLink UDP configuration:
- **Host**: 192.168.4.1
- **Port**: 14550
- **System ID**: 1
- **Component ID**: 1

### Telemetry Rates
- ATTITUDE: 10Hz
- SERVO_OUTPUT_RAW: 10Hz
- GPS_RAW_INT: 5Hz
- SYS_STATUS: 2Hz
- VFR_HUD: 5Hz

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- [ArduPilot](https://ardupilot.org/) - Open source autopilot software
- [MAVLink](https://mavlink.io/) - Micro Air Vehicle communication protocol
- SwiftUI community for excellent resources

---

## 📞 Support

For issues and questions:
- Open an issue on GitHub
- Check ArduPilot documentation
- MAVLink protocol reference

---

**Made with ❤️ for the drone community**
