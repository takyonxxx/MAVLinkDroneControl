// FlightTelemetryBar.qml - Heading / Alt AGL / Speed with GPS-or-fallback source labels
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0

InfoBar {
    InfoItem {
        icon: "⌖"
        label: "Heading"
        value: mavlink.heading.toFixed(0) + "°"
        color: Theme.cyan
    }
    VDivider {}
    InfoItem {
        icon: "↑"
        label: mavlink.usingGpsSource ? "Alt AGL (GPS)" : "Alt AGL (Baro)"
        value: mavlink.displayAltitude.toFixed(1) + "m"
        color: Theme.green
    }
    VDivider {}
    InfoItem {
        icon: "⏱"
        label: mavlink.usingGpsSource ? "Speed (GPS)" : "Speed (IMU)"
        value: (mavlink.displaySpeed * 3.6).toFixed(1) + " km/h"
        color: Theme.orange
    }
}
