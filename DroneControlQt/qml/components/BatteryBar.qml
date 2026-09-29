// BatteryBar.qml - Voltage / Current / Charge (always visible on dashboard + control)
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0

InfoBar {
    InfoItem {
        icon: "⚡"
        label: "Voltage"
        value: mavlink.batteryVoltage.toFixed(2) + "V"
        color: Theme.voltageColor(mavlink.batteryVoltage)
    }
    VDivider {}
    InfoItem {
        icon: "↕"
        label: "Current"
        value: mavlink.batteryCurrent.toFixed(2) + "A"
        color: Theme.cyan
    }
    VDivider {}
    InfoItem {
        icon: "▮"
        label: "Charge"
        value: mavlink.batteryRemaining + "%"
        color: Theme.batteryColor(mavlink.batteryRemaining)
    }
}
