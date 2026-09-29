// StatusBar.qml - Connection / ARMED / Mode strip (port of StatusBar.swift)
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0

RowLayout {
    Layout.fillWidth: true
    spacing: 12

    RowLayout {
        spacing: 5
        Rectangle {
            implicitWidth: 8; implicitHeight: 8; radius: 4
            color: mavlink.connected ? Theme.green : Theme.red
        }
        Text {
            text: mavlink.connected ? (mavlink.heartbeatAlive ? "Connected" : "Connected (no HB)") : "Disconnected"
            color: Theme.white
            font.pixelSize: 11
            font.weight: Font.Medium
        }
    }
    Item { Layout.fillWidth: true }
    RowLayout {
        spacing: 5
        Text {
            text: mavlink.armed ? "⚠" : "⚿"
            color: mavlink.armed ? Theme.orange : Theme.gray
            font.pixelSize: 11
        }
        Text {
            text: mavlink.armed ? "ARMED" : "DISARMED"
            color: mavlink.armed ? Theme.orange : Theme.gray
            font.pixelSize: 11
            font.bold: true
        }
    }
    Item { Layout.fillWidth: true }
    Rectangle {
        radius: 6
        color: Theme.withAlpha(mavlink.flightModeColor, 0.2)
        implicitWidth: modeText.implicitWidth + 16
        implicitHeight: modeText.implicitHeight + 8
        Text {
            id: modeText
            anchors.centerIn: parent
            text: mavlink.flightModeName
            color: mavlink.flightModeColor
            font.pixelSize: 11
            font.bold: true
        }
    }
}
