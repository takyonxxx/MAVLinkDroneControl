// FlightModePage.qml - port of FlightModeView.swift (mode grid + ARMING_CHECK toggle)
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DroneControl 1.0
import "../components"

Item {
    id: page

    PageBackground {}

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: col
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 16

            // Current mode card
            Rectangle {
                Layout.fillWidth: true
                radius: 16
                color: Theme.withAlpha(mavlink.flightModeColor, 0.15)
                border.width: 2
                border.color: Theme.withAlpha(mavlink.flightModeColor, 0.5)
                implicitHeight: cur.implicitHeight + 48
                ColumnLayout {
                    id: cur
                    anchors.centerIn: parent
                    spacing: 12
                    Text { text: "Current Mode"; color: Theme.gray; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                    RowLayout {
                        spacing: 16
                        Layout.alignment: Qt.AlignHCenter
                        Rectangle {
                            implicitWidth: 56; implicitHeight: 56; radius: 28
                            color: Theme.withAlpha(mavlink.flightModeColor, 0.25)
                            Text { anchors.centerIn: parent; text: mavlink.flightModeIcon; color: mavlink.flightModeColor; font.pixelSize: 28; font.bold: true }
                        }
                        ColumnLayout {
                            spacing: 4
                            Text { text: mavlink.flightModeName; color: Theme.white; font.pixelSize: 28; font.bold: true }
                            Text { text: "Mode " + mavlink.flightMode; color: Theme.gray; font.pixelSize: 12 }
                        }
                    }
                }
            }

            // Armed warning
            Rectangle {
                visible: mavlink.armed
                Layout.fillWidth: true
                radius: 8
                color: Theme.withAlpha(Theme.orange, 0.15)
                implicitHeight: warn.implicitHeight + 20
                RowLayout {
                    id: warn
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8
                    Text { text: "⚠"; color: Theme.orange; font.pixelSize: 14 }
                    Text { text: "Vehicle is armed - change modes carefully"; color: Theme.orange; font.pixelSize: 12 }
                }
            }

            // Mode grid
            GridLayout {
                Layout.fillWidth: true
                columns: page.width >= 900 ? 4 : 2
                columnSpacing: 10
                rowSpacing: 10
                Repeater {
                    model: mavlink.availableModes
                    Rectangle {
                        required property var modelData
                        readonly property bool selected: mavlink.flightMode === modelData.mode
                        Layout.fillWidth: true
                        implicitHeight: modeCol.implicitHeight + 24
                        radius: 12
                        color: selected ? Theme.withAlpha(modelData.color, 0.2) : Theme.overlay
                        border.width: 2
                        border.color: selected ? modelData.color : "transparent"
                        opacity: mavlink.connected ? 1 : 0.5
                        ColumnLayout {
                            id: modeCol
                            anchors.centerIn: parent
                            width: parent.width - 16
                            spacing: 6
                            Text {
                                text: modelData.icon
                                color: selected ? modelData.color : Theme.gray
                                font.pixelSize: 22
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: modelData.name
                                color: selected ? Theme.white : Theme.gray
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: modelData.description
                                color: Theme.gray
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: mavlink.connected
                            onClicked: mavlink.setFlightMode(modelData.mode)
                        }
                    }
                }
            }

            // ARMING_CHECK toggle (device-synced: shows the echoed value, not the requested one)
            Rectangle {
                id: armingCheck
                Layout.fillWidth: true
                Layout.bottomMargin: 24
                radius: 12
                implicitHeight: acRow.implicitHeight + 28

                readonly property string paramName: "ARMING_CHECK"
                property var deviceValue: mavlink.parameters.get(paramName)
                readonly property bool known: deviceValue !== undefined
                readonly property bool enabledOnDevice: known && deviceValue !== 0
                property bool writePending: false

                Connections {
                    target: mavlink.parameters
                    function onValueChanged(name, value) {
                        if (name === armingCheck.paramName) {
                            armingCheck.deviceValue = value
                            armingCheck.writePending = false   // FC echoed the new value
                        }
                    }
                }
                Component.onCompleted: mavlink.requestParameter(paramName)
                Connections {
                    target: page
                    function onVisibleChanged() { if (page.visible && mavlink.connected) mavlink.requestParameter(armingCheck.paramName) }
                }
                Timer {
                    interval: 3000; repeat: true; running: page.visible
                    onTriggered: if (mavlink.connected) mavlink.requestParameter(armingCheck.paramName)
                }

                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: !armingCheck.known ? Theme.withAlpha(Theme.gray, 0.5) : (armingCheck.enabledOnDevice ? Theme.armGreen1 : Theme.armRed1) }
                    GradientStop { position: 1.0; color: !armingCheck.known ? Theme.withAlpha(Theme.gray, 0.4) : (armingCheck.enabledOnDevice ? Theme.armGreen2 : Theme.armRed2) }
                }

                RowLayout {
                    id: acRow
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10
                    Text {
                        text: armingCheck.known && !armingCheck.enabledOnDevice ? "☒" : "☑"
                        color: Theme.white
                        font.pixelSize: 20
                    }
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        Text {
                            text: {
                                if (!armingCheck.known)
                                    return mavlink.connected ? "Arming Checks: reading..." : "Arming Checks: not connected"
                                if (!armingCheck.enabledOnDevice)
                                    return "Arming Checks: DISABLED"
                                var v = armingCheck.deviceValue
                                return "Arming Checks: ENABLED" + (v === 1 ? "" : " (mask: " + v.toFixed(0) + ")")
                            }
                            color: Theme.white
                            font.pixelSize: 15
                            font.bold: true
                        }
                        Text {
                            text: !armingCheck.known ? "Waiting for device value"
                                : (armingCheck.enabledOnDevice ? "Tap to disable all pre-arm checks" : "Unsafe! Tap to re-enable pre-arm checks")
                            color: Theme.white
                            opacity: 0.85
                            font.pixelSize: 11
                        }
                    }
                    BusyIndicator {
                        visible: armingCheck.writePending
                        running: visible
                        implicitWidth: 24; implicitHeight: 24
                    }
                    Text { visible: !armingCheck.writePending; text: "↻"; color: Theme.white; opacity: 0.8; font.pixelSize: 14 }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: armingCheck.known
                    onClicked: {
                        armingCheck.writePending = true
                        mavlink.setParameter(armingCheck.paramName, armingCheck.enabledOnDevice ? 0 : 1)
                    }
                }
            }
        }
    }
}
