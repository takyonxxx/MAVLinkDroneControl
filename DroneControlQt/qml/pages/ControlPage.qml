// ControlPage.qml - port of JoystickView.swift (touch joysticks + gamepad + ARM)
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DroneControl 1.0
import "../components"

Item {
    id: page
    property bool compact: width < 600
    property real joystickSize: compact ? 140 : 180
    property bool active: false          // set by Main.qml when this tab is current
    property bool everActive: false
    onActiveChanged: if (active) everActive = true

    // MANUAL_CONTROL at 20 Hz once this tab has been opened (like the iOS app) or a gamepad is
    // connected. Stopping the stream mid-flight would trigger ArduPilot's radio failsafe.
    Timer {
        interval: 50
        repeat: true
        running: mavlink.connected && (page.everActive || gamepad.controllerConnected)
        onTriggered: {
            syncGamepadValues()
            sendManualControl()
        }
    }

    function syncGamepadValues() {
        if (gamepad.controllerConnected) {
            leftStick.posX = gamepad.leftStickX
            leftStick.posY = gamepad.leftStickY
            rightStick.posX = gamepad.rightStickX
            rightStick.posY = gamepad.rightStickY
        }
    }

    function sendManualControl() {
        var x, y, z, r
        if (gamepad.controllerConnected) {
            var v = gamepad.manualControlValues()
            x = v.x; y = v.y; z = v.z; r = v.r
        } else {
            x = Math.round(rightStick.posY * 1000)
            y = Math.round(rightStick.posX * 1000)
            z = Math.round((leftStick.posY + 1.0) * 500)
            r = Math.round(leftStick.posX * 1000)
        }
        mavlink.sendManualControl(x, y, z, r, 0)
    }

    readonly property int throttleValue: gamepad.controllerConnected ? Math.round((gamepad.leftStickY + 1.0) * 500) : Math.round((leftStick.posY + 1.0) * 500)
    readonly property int yawValue: gamepad.controllerConnected ? Math.round(gamepad.leftStickX * 1000) : Math.round(leftStick.posX * 1000)
    readonly property int pitchValue: gamepad.controllerConnected ? Math.round(gamepad.rightStickY * 1000) : Math.round(rightStick.posY * 1000)
    readonly property int rollValue: gamepad.controllerConnected ? Math.round(gamepad.rightStickX * 1000) : Math.round(rightStick.posX * 1000)

    Rectangle { anchors.fill: parent; color: Theme.bg }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(height, col.implicitHeight + 32)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // Do not let the flickable steal the joystick drags
        interactive: !leftStick.dragging && !rightStick.dragging

        ColumnLayout {
            id: col
            width: parent.width
            y: 8
            spacing: compact ? 12 : 20

            StatusBar { Layout.leftMargin: 16; Layout.rightMargin: 16 }

            // Gamepad status
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                radius: 10
                color: Theme.card
                implicitHeight: gpCol.implicitHeight + 24
                ColumnLayout {
                    id: gpCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    RowLayout {
                        spacing: 12
                        Text {
                            text: "▣"
                            color: gamepad.controllerConnected ? Theme.green : Theme.gray
                            font.pixelSize: 20
                        }
                        ColumnLayout {
                            spacing: 2
                            Text {
                                text: gamepad.controllerConnected ? "Gamepad Connected" : "No Gamepad"
                                color: Theme.white
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: gamepad.backendAvailable ? gamepad.controllerName : "Gamepad not supported on this platform - use touch sticks"
                                color: Theme.gray
                                font.pixelSize: 12
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                    RowLayout {
                        visible: gamepad.controllerConnected
                        spacing: 16
                        Repeater {
                            model: [
                                { n: "L-X", v: gamepad.leftStickX },
                                { n: "L-Y", v: gamepad.leftStickY },
                                { n: "R-X", v: gamepad.rightStickX },
                                { n: "R-Y", v: gamepad.rightStickY }
                            ]
                            ColumnLayout {
                                spacing: 2
                                Text { text: modelData.n; color: Theme.gray; font.pixelSize: 10; Layout.alignment: Qt.AlignHCenter }
                                Text {
                                    text: modelData.v.toFixed(2)
                                    color: Math.abs(modelData.v) > 0.1 ? Theme.orange : Theme.white
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    font.family: Theme.mono
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }

            BatteryBar { Layout.leftMargin: 16; Layout.rightMargin: 16 }
            FlightTelemetryBar { Layout.leftMargin: 16; Layout.rightMargin: 16 }
            GPSInfoBar { Layout.leftMargin: 16; Layout.rightMargin: 16 }

            // Values
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: compact ? 4 : 10
                spacing: compact ? 16 : 40
                Repeater {
                    model: [
                        { n: "Throttle", v: page.throttleValue },
                        { n: "Yaw", v: page.yawValue },
                        { n: "Pitch", v: page.pitchValue },
                        { n: "Roll", v: page.rollValue }
                    ]
                    ColumnLayout {
                        spacing: 4
                        Text { text: modelData.n; color: Theme.gray; font.pixelSize: compact ? 12 : 14; Layout.alignment: Qt.AlignHCenter }
                        Text {
                            text: modelData.v
                            color: Math.abs(modelData.v) < 100 ? Theme.green : (Math.abs(modelData.v) < 500 ? Theme.orange : Theme.red)
                            font.pixelSize: compact ? 18 : 22
                            font.bold: true
                            font.family: Theme.mono
                            Layout.minimumWidth: compact ? 50 : 70
                            horizontalAlignment: Text.AlignHCenter
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }

            // Joysticks
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: compact ? 8 : 16
                spacing: compact ? 20 : 60
                ColumnLayout {
                    spacing: 8
                    JoystickControl {
                        id: leftStick
                        size: page.joystickSize
                        posY: -1                      // throttle starts at minimum
                        returnToCenterX: true         // yaw recenters
                        returnToCenterY: false        // throttle holds
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text { text: "Throttle / Yaw"; color: Theme.gray; font.pixelSize: compact ? 13 : 14; font.weight: Font.Medium; Layout.alignment: Qt.AlignHCenter }
                }
                ColumnLayout {
                    spacing: 8
                    JoystickControl {
                        id: rightStick
                        size: page.joystickSize
                        returnToCenterX: true
                        returnToCenterY: true
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text { text: "Pitch / Roll"; color: Theme.gray; font.pixelSize: compact ? 13 : 14; font.weight: Font.Medium; Layout.alignment: Qt.AlignHCenter }
                }
            }

            // Reset + ARM/DISARM
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 20
                Layout.bottomMargin: 20
                spacing: 20
                ActionButton {
                    text: "Reset"
                    icon: "↺"
                    onClicked: {
                        leftStick.posX = 0; leftStick.posY = -1
                        rightStick.posX = 0; rightStick.posY = 0
                        gamepad.resetAll()
                    }
                }
                ActionButton {
                    text: mavlink.armed ? "DISARM" : "ARM"
                    icon: "⏻"
                    color1: mavlink.armed ? Theme.armRed1 : Theme.armGreen1
                    color2: mavlink.armed ? Theme.armRed2 : Theme.armGreen2
                    onClicked: {
                        if (mavlink.armed) mavlink.disarmVehicle(false)
                        else mavlink.armVehicle(false)
                    }
                }
            }
        }
    }
}
