// MapPage.qml - port of EnhancedMapView.swift.
// The actual map (Qt Location / OSM) lives in MapView.qml and is only loaded
// when the Location module is available, so the app still runs without it.
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0
import "../components"

Item {
    Rectangle { anchors.fill: parent; color: Theme.bg }

    Loader {
        anchors.fill: parent
        active: hasMapSupport
        source: hasMapSupport ? "MapView.qml" : ""
    }

    ColumnLayout {
        visible: !hasMapSupport
        anchors.centerIn: parent
        spacing: 10
        width: Math.min(parent.width - 40, 420)
        Text { text: "▦"; color: Theme.gray; font.pixelSize: 40; Layout.alignment: Qt.AlignHCenter }
        Text {
            text: "Map not available\nThis build was made without the Qt Location module (QT += location)."
            color: Theme.gray
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        KeyValueRow { label: "GPS"; value: mavlink.latitude.toFixed(5) + ", " + mavlink.longitude.toFixed(5); valueColor: Theme.cyan }
        KeyValueRow { label: "Alt"; value: mavlink.altitude.toFixed(0) + " m"; valueColor: Theme.green }
        KeyValueRow { label: "Heading"; value: mavlink.heading.toFixed(0) + "°"; valueColor: Theme.purple }
    }
}
