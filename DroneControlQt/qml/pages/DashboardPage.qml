// DashboardPage.qml - port of MainDashboardView.swift
// Compact (phone): scrollable column. Wide (desktop/tablet): 3-column layout.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DroneControl 1.0
import "../components"

Item {
    id: page
    property bool compact: width < 600

    Rectangle { anchors.fill: parent; color: Theme.bg }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Status + battery header (always visible)
        Rectangle {
            Layout.fillWidth: true
            color: Theme.bgHeader
            implicitHeight: header.implicitHeight + 16
            ColumnLayout {
                id: header
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                spacing: 8
                StatusBar {}
                BatteryBar {}
            }
        }

        // ---------------- Compact layout ----------------
        Flickable {
            visible: page.compact
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: compactCol.implicitHeight + 34
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: compactCol
                width: parent.width
                y: 10
                spacing: 12

                AttitudeIndicator {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 250
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.topMargin: 10
                    roll: mavlink.roll
                    pitch: mavlink.pitch
                    heading: mavlink.heading
                }

                // Motor outputs M1-M4 (Quad X)
                QuadMotorPanel {
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    compact: true
                }

                // Roll / Pitch / Yaw
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    spacing: 16
                    Item { Layout.fillWidth: true }
                    AttitudeValue { label: "Roll"; value: mavlink.roll }
                    VDivider { Layout.preferredHeight: 20 }
                    AttitudeValue { label: "Pitch"; value: mavlink.pitch }
                    VDivider { Layout.preferredHeight: 20 }
                    AttitudeValue { label: "Yaw"; value: mavlink.yaw }
                    Item { Layout.fillWidth: true }
                }

                GPSInfoCard {
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                }

                // Alt / Speed / Climb
                GridLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.bottomMargin: 20
                    columns: page.width < 420 ? 1 : 3
                    columnSpacing: 12
                    rowSpacing: 12
                    TelemetryCard { icon: "↑"; title: "Alt"; value: mavlink.altitude.toFixed(1) + "m"; accent: Theme.cyan }
                    TelemetryCard { icon: "⏱"; title: "Speed"; value: mavlink.groundSpeed.toFixed(1) + "m/s"; accent: Theme.green }
                    TelemetryCard { icon: "↗"; title: "Climb"; value: mavlink.climbRate.toFixed(1) + "m/s"; accent: Theme.orange }
                }
            }
        }

        // ---------------- Wide layout ----------------
        Item {
            visible: !page.compact
            Layout.fillWidth: true
            Layout.fillHeight: true

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 20
                property real sideWidth: Math.max(200, width * 0.22)

                // Left: telemetry
                ColumnLayout {
                    Layout.preferredWidth: parent.sideWidth
                    Layout.maximumWidth: parent.sideWidth
                    Layout.fillHeight: true
                    spacing: 12
                    TelemetryCard {
                        icon: "▮"; title: "Battery"
                        value: mavlink.batteryVoltage.toFixed(1) + "V"
                        subtitle: mavlink.batteryRemaining + "%"
                        accent: Theme.batteryColor(mavlink.batteryRemaining)
                    }
                    GPSInfoCard { wide: true }
                    TelemetryCard {
                        icon: "↑"; title: "Altitude"
                        value: mavlink.altitude.toFixed(1) + "m"
                        subtitle: mavlink.climbRate.toFixed(1) + "m/s"
                        accent: Theme.cyan
                    }
                    TelemetryCard {
                        icon: "⏱"; title: "Speed"
                        value: mavlink.groundSpeed.toFixed(1) + "m/s"
                        subtitle: (mavlink.groundSpeed * 3.6).toFixed(1) + "km/h"
                        accent: Theme.green
                    }
                    Item { Layout.fillHeight: true }
                }

                // Center: attitude
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 16
                    Item { Layout.fillHeight: true }
                    AttitudeIndicator {
                        id: wideHsi
                        property real ind: Math.min(Math.max(300, page.width * 0.45) - 40, page.height * 0.5)
                        Layout.preferredWidth: ind
                        Layout.preferredHeight: ind
                        Layout.alignment: Qt.AlignHCenter
                        roll: mavlink.roll
                        pitch: mavlink.pitch
                        heading: mavlink.heading
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 30
                        AttitudeValue { label: "Roll"; value: mavlink.roll }
                        AttitudeValue { label: "Pitch"; value: mavlink.pitch }
                        AttitudeValue { label: "Yaw"; value: mavlink.yaw }
                    }
                    Item { Layout.fillHeight: true }
                }

                // Right: motors (Quad X)
                ColumnLayout {
                    Layout.preferredWidth: parent.sideWidth
                    Layout.maximumWidth: parent.sideWidth
                    Layout.fillHeight: true
                    spacing: 10
                    QuadMotorPanel {}
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
