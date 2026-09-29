// SettingsPage.qml - port of SettingsView.swift
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DroneControl 1.0
import "../components"

Item {
    id: page
    property bool showParameters: false
    property var paramList: []

    Rectangle { anchors.fill: parent; color: Theme.bg }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: col
            x: 16; y: 16
            width: parent.width - 32
            spacing: 20

            // ---------------- Connection ----------------
            Card {
                title: "MAVLink Connection"; icon: "☁"; pad: 16
                GridLayout {
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 10
                    Layout.fillWidth: true
                    Text { text: "Host"; color: Theme.gray; font.pixelSize: 14; Layout.preferredWidth: 80 }
                    TextField {
                        Layout.fillWidth: true
                        text: settings.connectionHost
                        placeholderText: "192.168.4.1"
                        color: Theme.white
                        inputMethodHints: Qt.ImhPreferNumbers | Qt.ImhNoPredictiveText
                        onEditingFinished: settings.connectionHost = text
                    }
                    Text { text: "Port"; color: Theme.gray; font.pixelSize: 14; Layout.preferredWidth: 80 }
                    TextField {
                        Layout.fillWidth: true
                        text: settings.connectionPort
                        placeholderText: "14550"
                        color: Theme.white
                        inputMethodHints: Qt.ImhDigitsOnly
                        validator: IntValidator { bottom: 1; top: 65535 }
                        onEditingFinished: settings.connectionPort = text
                    }
                }
                Text {
                    text: "UDP, local port 14550. Changes reconnect automatically."
                    color: Theme.gray; font.pixelSize: 11
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }

            // ---------------- Gamepad ----------------
            Card {
                title: "Gamepad Settings"; icon: "▣"; pad: 16
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Rectangle { implicitWidth: 10; implicitHeight: 10; radius: 5; color: gamepad.controllerConnected ? Theme.green : Theme.red }
                    Text { text: gamepad.controllerConnected ? "Connected" : "Disconnected"; color: Theme.gray; font.pixelSize: 12 }
                }
                KeyValueRow { visible: gamepad.controllerConnected; label: "Controller"; value: gamepad.controllerName; valueColor: Theme.cyan; fontSize: 14 }
                Text {
                    visible: !gamepad.backendAvailable
                    text: "Gamepad input is not available on this platform; the on-screen sticks are used."
                    color: Theme.gray; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
                HDivider {}

                // Deadzone
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Deadzone"; color: Theme.gray; font.pixelSize: 14 }
                    Item { Layout.fillWidth: true }
                    Text { text: settings.gamepadDeadzone.toFixed(2); color: Theme.cyan; font.pixelSize: 14; font.family: Theme.mono }
                }
                Slider {
                    Layout.fillWidth: true
                    from: 0.0; to: 0.3; stepSize: 0.01
                    value: settings.gamepadDeadzone
                    onMoved: settings.gamepadDeadzone = value
                }

                // Hold throttle
                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        Text { text: "Hold Throttle Position"; color: Theme.white; font.pixelSize: 14 }
                        Text { text: "Throttle stays at last position instead of returning to center"; color: Theme.gray; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    }
                    Switch {
                        checked: settings.gamepadHoldThrottle
                        onToggled: settings.gamepadHoldThrottle = checked
                    }
                }

                // Throttle speed
                ColumnLayout {
                    visible: settings.gamepadHoldThrottle
                    Layout.fillWidth: true
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Throttle Speed"; color: Theme.gray; font.pixelSize: 14 }
                        Item { Layout.fillWidth: true }
                        Text { text: settings.throttleSpeed.toFixed(3); color: Theme.cyan; font.pixelSize: 14; font.family: Theme.mono }
                    }
                    Slider {
                        Layout.fillWidth: true
                        from: 0.005; to: 0.05; stepSize: 0.005
                        value: settings.throttleSpeed
                        onMoved: settings.throttleSpeed = value
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Slow"; color: Theme.gray; font.pixelSize: 10 }
                        Item { Layout.fillWidth: true }
                        Text { text: "Fast"; color: Theme.gray; font.pixelSize: 10 }
                    }
                }
                HDivider {}
                Text { text: "Button Mapping"; color: Theme.white; font.pixelSize: 14; font.weight: Font.DemiBold }
                Repeater {
                    model: [
                        { b: "Left Stick", a: "Throttle (Y) / Yaw (X)" },
                        { b: "Right Stick", a: "Pitch (Y) / Roll (X)" },
                        { b: "Start", a: "ARM" },
                        { b: "Back", a: "DISARM" },
                        { b: "L3 / R3", a: "Reset All" }
                    ]
                    RowLayout {
                        spacing: 8
                        Text { text: modelData.b; color: Theme.orange; font.pixelSize: 12; font.family: Theme.mono; Layout.preferredWidth: 100 }
                        Text { text: "→"; color: Theme.gray; font.pixelSize: 12 }
                        Text { text: modelData.a; color: Theme.gray; font.pixelSize: 12 }
                    }
                }
            }

            // ---------------- Telemetry status ----------------
            Card {
                title: "Telemetry Status"; icon: "⩡"; pad: 16
                TelemetryRow { label: "Connection"; value: mavlink.connected ? "Connected" : "Disconnected"; valueColor: mavlink.connected ? Theme.green : Theme.red }
                TelemetryRow { label: "Vehicle heartbeat"; value: mavlink.heartbeatAlive ? "OK" : "none"; valueColor: mavlink.heartbeatAlive ? Theme.green : Theme.red }
                TelemetryRow { label: "Armed"; value: mavlink.armed ? "ARMED" : "Disarmed"; valueColor: mavlink.armed ? Theme.red : Theme.green }
                TelemetryRow { label: "Flight Mode"; value: mavlink.flightModeName; valueColor: mavlink.flightModeColor }
                HDivider {}
                TelemetryRow { label: "Battery"; value: mavlink.batteryVoltage.toFixed(2) + "V (" + mavlink.batteryRemaining + "%)"; valueColor: Theme.batteryColor(mavlink.batteryRemaining) }
                TelemetryRow { label: "Current"; value: mavlink.batteryCurrent.toFixed(2) + "A"; valueColor: Theme.cyan }
                HDivider {}
                TelemetryRow { label: "GPS Fix"; value: Theme.gpsFixName(mavlink.gpsFixType); valueColor: Theme.gpsColor(mavlink.gpsFixType) }
                TelemetryRow { label: "Satellites"; value: mavlink.gpsSatellites; valueColor: Theme.cyan }
                HDivider {}
                TelemetryRow { label: "Altitude"; value: mavlink.altitude.toFixed(1) + "m"; valueColor: Theme.cyan }
                TelemetryRow { label: "Speed"; value: mavlink.groundSpeed.toFixed(1) + "m/s"; valueColor: Theme.green }
            }

            // ---------------- System ----------------
            Card {
                title: "System"; icon: "⚙"; pad: 16
                TelemetryRow { label: "System ID"; value: mavlink.targetSystemId; valueColor: Theme.white }
                TelemetryRow { label: "Component ID"; value: mavlink.targetComponentId; valueColor: Theme.white }
                TelemetryRow { label: "Vehicle Type"; value: mavlink.vehicleTypeName; valueColor: Theme.white }
                TelemetryRow { label: "Parameters"; value: mavlink.parameters.count; valueColor: Theme.white }
                TelemetryRow { label: "App version"; value: Qt.application.version; valueColor: Theme.gray }
            }

            // ---------------- Parameters ----------------
            Card {
                title: "Parameters"; icon: "≡"; pad: 16
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        radius: 8
                        color: Theme.withAlpha(Theme.cyan, 0.2)
                        implicitWidth: pc.implicitWidth + 20
                        implicitHeight: pc.implicitHeight + 8
                        Text { id: pc; anchors.centerIn: parent; text: mavlink.parameters.count; color: Theme.cyan; font.pixelSize: 14; font.bold: true; font.family: Theme.mono }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    radius: 8
                    color: Theme.withAlpha(Theme.cyan, 0.1)
                    implicitHeight: 42
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        Text { text: page.showParameters ? "Hide Parameters" : "Show Parameters"; color: Theme.cyan; font.pixelSize: 14; font.weight: Font.Medium }
                        Item { Layout.fillWidth: true }
                        Text { text: page.showParameters ? "▴" : "▾"; color: Theme.cyan; font.pixelSize: 14 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            page.showParameters = !page.showParameters
                            if (page.showParameters) page.paramList = mavlink.parameters.sortedList()
                        }
                    }
                }
                ListView {
                    visible: page.showParameters
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(300, count * 30)
                    clip: true
                    spacing: 6
                    model: page.paramList
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: 24
                        radius: 4
                        color: Theme.card3
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            Text { text: modelData.name; color: Theme.white; font.pixelSize: 11; font.family: Theme.mono }
                            Item { Layout.fillWidth: true }
                            Text { text: modelData.value.toFixed(2); color: Theme.cyan; font.pixelSize: 11; font.family: Theme.mono }
                        }
                    }
                }
            }
        }
    }

    component TelemetryRow: KeyValueRow {
        fontSize: 15
        labelColor: Theme.gray
    }
}
