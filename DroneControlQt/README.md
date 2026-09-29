# DroneControlQt

Qt 6 port of the **DroneControl** iOS/macOS app (`../DroneControl`, SwiftUI):
a MAVLink v2 ground control station for ArduPilot vehicles over UDP.
Builds with **qmake** (`DroneControlQt.pro`) for desktop (Windows, Linux,
macOS) and **Android** from the same sources.

Feature parity with the iOS app, tab for tab:

| Tab | What it does | iOS source |
|-----|--------------|------------|
| Dashboard | Artificial horizon + compass rose, battery bar, GPS, M1-M4 outputs, alt/speed/climb (compact and wide layouts) | `MainDashboardView`, `AttitudeIndicator` |
| Control | Two virtual sticks (throttle holds, others recenter), MANUAL_CONTROL at 20 Hz, gamepad, ARM/DISARM | `JoystickView`, `GamepadManager` |
| Motors | Quad X motor test (`MAV_CMD_DO_MOTOR_TEST`, keepalive 1 s / timeout 3 s, ArduPilot test-order mapping) | `MotorTestView` |
| Modes | Current mode card, 8 mode buttons, device-synced ARMING_CHECK toggle | `FlightModeView` |
| Map | OSM/satellite map, drone marker with heading, flight path, follow/clear | `EnhancedMapView` |
| Servos | 16-channel monitor + `DO_SET_SERVO` sheet | `ServoMonitorView` |
| Params | Full parameter download, categories, search, edit/write, restore known-good defaults (845 values) | `ParametersView`, `DefaultParameters` |
| Messages | STATUSTEXT log with severity filter + EKF health card | `MessagesView` |
| Calibrate | Compass (progress mask, fitness, accept), gyro, barometer | `CalibrationView` |
| Settings | Host/port, gamepad deadzone / hold-throttle / speed, telemetry + system info | `SettingsView`, `SettingsManager` |
| GPS | GPS diagnostics: sensor bits, stream rate, fix, raw fields, GPS messages | `GPSView` |

## Layout

```
DroneControlQt/
  DroneControlQt.pro      qmake project (desktop + Android)
  resources.qrc           QML + icons
  src/                    C++ backend
    MavlinkManager.*      MAVLink parsing, telemetry properties, commands  (MAVLinkManager.swift + MAVLinkProtocol.swift)
    UdpConnection.*       QUdpSocket link, session peers                   (UDPConnection.swift)
    ParameterModel.*      parameter store / categories for QML
    MessagesModel.*       STATUSTEXT log model
    GamepadManager.*      XInput (Windows) / joystick API (Linux) backends
    SettingsManager.*     QSettings persistence
    DefaultParameters.*   known-good parameter snapshot (generated)
  qml/                    UI (Qt Quick, Material dark)
    Main.qml, Theme.qml, components/, pages/
  mavlink/                MAVLink C headers (ardupilotmega dialect + deps), copied from ../DroneControl/MAVLink
  android/                AndroidManifest.xml + launcher icons
  icons/                  app icon (png/ico)
  tools/sim_vehicle.py    pymavlink vehicle simulator for testing without hardware
```

## Building

Requirements: Qt 6.5 or newer (developed against 6.11) with the modules
`Quick`, `QuickControls2`, `Network` and, for the map tab, `Positioning` +
`Location`. The map tab is optional: without Qt Location the project still
builds and shows a placeholder.

### Desktop (Qt Creator)

Open `DroneControlQt.pro`, pick a desktop kit, build and run. Command line:

```
mkdir build && cd build
qmake ../DroneControlQt.pro
make -j        # nmake / jom / mingw32-make on Windows
```

### Android (Qt Creator)

1. Install the Android kit (SDK 35, NDK, JDK 17) via *Preferences > Devices > Android*.
2. Open `DroneControlQt.pro`, choose the Android Qt 6.11 kit (arm64-v8a),
   build and deploy. `android/AndroidManifest.xml` is picked up through
   `ANDROID_PACKAGE_SOURCE_DIR`; the package id is `com.tbiliyor.dronecontrol`.
3. The app needs Wi-Fi access to the vehicle's network (default
   `192.168.4.1:14550`, local port 14550 - same as the iOS app).

## Connecting

Settings tab: host and UDP port of the vehicle/bridge. The app binds local
port 14550, sends a GCS heartbeat every 500 ms, requests the telemetry
streams with `SET_MESSAGE_INTERVAL` and, like the iOS app, echoes outgoing
packets to every peer that has sent it data in the session.

## Gamepad

* **Windows**: any XInput controller (Xbox layout). Loaded at runtime, no SDK needed.
* **Linux**: `/dev/input/js0..3` (Xbox-style axis/button numbering).
* **Android / macOS**: not implemented - the on-screen sticks are used.

Mapping is identical to the iOS/macOS app: left stick throttle/yaw, right
stick pitch/roll, Start = ARM (forced), Back = DISARM (forced), L3/R3 = reset.

## Testing without a vehicle

```
pip install pymavlink
python3 tools/sim_vehicle.py 127.0.0.1 14550
```

Set the host to `127.0.0.1` in Settings. The simulator answers parameters,
commands, motor tests and compass calibration and streams fake telemetry.

Debug aids (environment variables): `DRONECONTROL_SCREENSHOT_DIR=<dir>` walks
through every tab and saves a PNG of each; `DRONECONTROL_SCREENSHOT_SIZE=360x740`
forces the window size (phone layout).

## Notes / differences from the iOS app

* Changing host/port in Settings reconnects automatically (the iOS app needs a restart).
* Heartbeats from other GCS (`MAV_TYPE_GCS`) are ignored; the status bar shows
  "Connected (no HB)" while the socket is open but no vehicle heartbeat has
  arrived in the last 5 s.
* SF Symbols are replaced by simple Unicode glyphs; colors follow the iOS palette (`qml/Theme.qml`).
