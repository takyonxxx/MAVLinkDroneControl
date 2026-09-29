// MapPage.qml - port of EnhancedMapView.swift.
// The actual map (Qt Location / OSM) lives in MapView.qml and is only loaded
// when the Location module is available, so the app still runs without it.
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0
import "../components"

Item {
    Rectangle { anchors.fill: parent; color: Theme.bg }

    property bool leafletFailed: false
    property bool useLeaflet: hasWebView && !leafletFailed
    property bool useLocation: !useLeaflet && hasMapSupport

    Loader {
        id: mapLoader
        anchors.fill: parent
        active: useLeaflet || useLocation
        source: useLeaflet ? "LeafletMapView.qml" : (useLocation ? "MapView.qml" : "")
        onStatusChanged: {
            if (status === Loader.Error) {
                console.log("[MAP] failed to load " + source + " (QML error, see messages above)")
                if (useLeaflet) leafletFailed = true       // fall back to the Qt Location map
            } else if (status === Loader.Ready) {
                console.log("[MAP] loaded " + source)
            }
        }
    }

    Connections {
        target: mapLoader.item
        ignoreUnknownSignals: true
        function onFailed() {
            if (hasMapSupport) { console.log("[MAP] Leaflet page failed - switching to the Qt Location map"); leafletFailed = true }
        }
    }

    ColumnLayout {
        visible: !useLeaflet && !useLocation
        anchors.centerIn: parent
        spacing: 10
        width: Math.min(parent.width - 40, 420)
        Text { text: "▦"; color: Theme.gray; font.pixelSize: 40; Layout.alignment: Qt.AlignHCenter }
        Text {
            text: leafletFailed ? "Map not available\nLeafletMapView.qml failed to load (see Application Output) and Qt Location is not in this build."
                                : "Map not available\nThis build has neither Qt WebView (Leaflet map) nor Qt Location."
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
