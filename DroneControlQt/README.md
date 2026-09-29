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
| Modes | Current mode card, 12 mode buttons (Stabilize, AltHold, PosHold, Loiter, Guided, Auto, RTL, Smart RTL, Land, Brake, Circle, Autotune), device-synced ARMING_CHECK toggle | `FlightModeView` |
| Map | Leaflet map (port of the MarenControlConsole MapWidget): Esri satellite / OSM street / hybrid, OpenSeaMap seamarks, vehicle marker + traversed path, home, mission planning (tap / right-click to add, drag, delete), upload/download/start mission, guided "fly here", takeoff, RTL, Land | `EnhancedMapView` + `mapwidget.cpp` |
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
    TileCache.*           local tile proxy + offline disk cache for the map
    SettingsManager.*     QSettings persistence
    DefaultParameters.*   known-good parameter snapshot (generated)
  qml/                    UI (Qt Quick, Material dark)
    Main.qml, Theme.qml, components/, pages/
  web/map.html            Leaflet map page (+ leaflet.js/css inlined at runtime, shown in a WebView)
  mavlink/                MAVLink C headers (ardupilotmega dialect + deps), copied from ../DroneControl/MAVLink
  android/                AndroidManifest.xml + launcher icons
  icons/                  app icon (png/ico)
  tools/sim_vehicle.py    pymavlink vehicle simulator for testing without hardware
```

## Building

Requirements: Qt 6.5 or newer (developed against 6.11) with the modules
`Quick`, `QuickControls2`, `Network` and, for the map tab, `WebView` (Qt
WebEngine on desktop, the native WebView on Android). Without WebView the map
falls back to Qt Location (`Positioning` + `Location`) and without both it
shows a placeholder; the rest of the app builds regardless.

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

## Map and missions

The map tab is the MarenControlConsole MapWidget's Leaflet page ported to a
WebView (`web/map.html`, `qml/pages/LeafletMapView.qml`): Esri World Imagery
satellite, OSM street and hybrid layers, the OpenSeaMap seamarks overlay,
red-arrow vehicle marker with a yellow traversed path (0.5 m spacing, 2000
points), home marker and numbered draggable waypoints with a dashed mission
path. The page talks to QML with `runJavaScript` (QML -> JS calls, JS -> QML
through a polled event queue), so no WebChannel is needed and it also works in
the Android WebView.

Tiles are fetched through a local cache server (`src/TileCache.*`, port of the
MapWidget's OfflineMapCache): every tile shown once is stored under the app's
cache directory (`MapTiles/arcgis/{z}/{y}/{x}.png`, the same layout as
MarenControlConsole, whose cache is also read), so the map keeps working on the
vehicle Wi-Fi without internet; missing tiles are filled from the nearest cached
zoom level. "Cache map" in the toolbar pre-downloads a 2 km radius (zoom 12-18)
around the vehicle. When tiles cannot be loaded at all the map shows a warning
banner, and the Application Output has `[MAP]` / `[TILES]` lines for diagnosis.

Mission workflow: "+ Waypoint" (or right-click / long-press on the map) adds
waypoints at the altitude in the toolbar; drag to move, tap a marker for
Delete. "Upload" sends the mission (home, NAV_TAKEOFF, waypoints, optional
RTL) with the MAVLink mission protocol, "Download" reads the vehicle's mission,
"Start AUTO" switches to AUTO and sends MISSION_START. "Fly here" switches to
GUIDED and sends SET_POSITION_TARGET_GLOBAL_INT, "Takeoff" sends NAV_TAKEOFF in
GUIDED.

## Testing without a vehicle

```
pip install pymavlink
python3 tools/sim_vehicle.py 127.0.0.1 14550
```

Set the host to `127.0.0.1` in Settings. The simulator models the real
vehicle (Pixhawk + ArduCopter parameters from `turkay_copter.param`, Zino Pro
Plus airframe on a T-Motor F55A Pro II, 3S 2200 mAh LiPo): stick-driven
Stabilize / AltHold / Loiter / PosHold / Brake flight, GUIDED takeoff and
goto, AUTO missions (takeoff, waypoints, RTL/land items, MISSION_CURRENT and
MISSION_ITEM_REACHED), CIRCLE, RTL / Smart RTL and LAND, a battery model with
voltage sag and mAh consumption, the FC's battery failsafe messages, motor
tests, parameters, compass/gyro/baro calibration.

Debug aids (environment variables): `DRONECONTROL_SCREENSHOT_DIR=<dir>` walks
through every tab and saves a PNG of each; `DRONECONTROL_SCREENSHOT_SIZE=360x740`
forces the window size (phone layout).

## Notes / differences from the iOS app

* Changing host/port in Settings reconnects automatically (the iOS app needs a restart).
* Heartbeats from other GCS (`MAV_TYPE_GCS`) are ignored; the status bar shows
  "Connected (no HB)" while the socket is open but no vehicle heartbeat has
  arrived in the last 5 s.
* SF Symbols are replaced by simple Unicode glyphs; colors follow the iOS palette (`qml/Theme.qml`).
