// MapView.qml - satellite/OSM map with live drone marker, flight path and telemetry overlay
import QtQuick
import QtQuick.Layouts
import QtLocation
import QtPositioning
import DroneControl 1.0
import "../components"

Item {
    id: root
    property bool following: true
    property var flightPath: []              // array of coordinates
    property var droneCoordinate: QtPositioning.coordinate(39.9334, 32.8597)   // Ankara default
    property bool hasPosition: false
    readonly property int maxPathPoints: 1000
    readonly property real minDistanceBetweenPoints: 1.0

    function updateDroneLocation() {
        if (mavlink.latitude === 0 && mavlink.longitude === 0)
            return
        var c = QtPositioning.coordinate(mavlink.latitude, mavlink.longitude)
        droneCoordinate = c
        hasPosition = true
        var path = flightPath
        if (path.length === 0 || path[path.length - 1].distanceTo(c) >= minDistanceBetweenPoints) {
            path.push(c)
            if (path.length > maxPathPoints)
                path.splice(0, path.length - maxPathPoints)
            flightPath = path
            pathLine.path = path
        }
        if (following)
            centerOnDrone()
    }

    function centerOnDrone() {
        if (!hasPosition) return
        map.center = droneCoordinate
    }

    function clearFlightPath() {
        flightPath = []
        pathLine.path = []
    }

    Connections {
        target: mavlink
        function onPositionChanged() { root.updateDroneLocation() }
    }

    Plugin {
        id: osmPlugin
        name: "osm"
        // Default OSM providers; the tile server can be overridden with
        // PluginParameter { name: "osm.mapping.custom.host"; value: "https://..." }
        PluginParameter { name: "osm.mapping.highdpi_tiles"; value: true }
    }

    Map {
        id: map
        anchors.fill: parent
        plugin: osmPlugin
        center: root.droneCoordinate
        zoomLevel: 16
        copyrightsVisible: true

        // Prefer a satellite map type when the provider offers one
        Component.onCompleted: {
            for (var i = 0; i < supportedMapTypes.length; i++) {
                if (supportedMapTypes[i].style === MapType.SatelliteMapDay) {
                    activeMapType = supportedMapTypes[i]
                    break
                }
            }
        }

        // Pan / pinch / wheel
        PinchHandler {
            id: pinch
            target: null
            onActiveChanged: if (active) { map.startCentroid = map.toCoordinate(pinch.centroid.position, false); root.following = false }
            onScaleChanged: (delta) => {
                map.zoomLevel += Math.log2(delta)
                map.alignCoordinateToPoint(map.startCentroid, pinch.centroid.position)
            }
            onRotationChanged: (delta) => {
                map.bearing -= delta
                map.alignCoordinateToPoint(map.startCentroid, pinch.centroid.position)
            }
            grabPermissions: PointerHandler.TakeOverForbidden
        }
        WheelHandler {
            id: wheel
            acceptedDevices: Qt.platform.pluginName === "cocoa" || Qt.platform.pluginName === "wayland"
                             ? PointerDevice.Mouse | PointerDevice.TouchPad
                             : PointerDevice.Mouse
            rotationScale: 1 / 120
            property: "zoomLevel"
        }
        DragHandler {
            id: drag
            target: null
            onActiveChanged: if (active) root.following = false
            onTranslationChanged: (delta) => map.pan(-delta.x, -delta.y)
        }
        property var startCentroid

        // Flight path (yellow)
        MapPolyline {
            id: pathLine
            line.width: 4
            line.color: Qt.rgba(1.0, 0.8, 0.0, 0.9)
        }

        // Drone marker rotated with heading
        MapQuickItem {
            visible: root.hasPosition
            coordinate: root.droneCoordinate
            anchorPoint.x: marker.width / 2
            anchorPoint.y: marker.height / 2
            sourceItem: Item {
                id: marker
                width: 60; height: 60
                Rectangle {
                    anchors.fill: parent
                    radius: 30
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.withAlpha(Theme.cyan, 0.6) }
                        GradientStop { position: 1.0; color: Theme.withAlpha(Theme.cyan, 0.0) }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 42; height: 42; radius: 21
                    color: Theme.white
                    rotation: mavlink.heading
                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.fillStyle = Theme.cyan
                            ctx.beginPath()
                            ctx.moveTo(21, 6)     // nose
                            ctx.lineTo(34, 34)
                            ctx.lineTo(21, 27)
                            ctx.lineTo(8, 34)
                            ctx.closePath()
                            ctx.fill()
                        }
                    }
                }
            }
        }
    }

    // Telemetry overlay panel (top right)
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 12
        width: 220
        radius: 12
        color: Theme.withAlpha(Theme.black, 0.4)
        implicitHeight: tp.implicitHeight + 16
        ColumnLayout {
            id: tp
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6
            TelemetryDataRow { icon: "●"; title: "GPS"; value: mavlink.latitude.toFixed(5) + "," + mavlink.longitude.toFixed(5); color: Theme.cyan }
            RowLayout {
                spacing: 6
                TelemetryDataRow { icon: "↑"; title: "Alt"; value: mavlink.altitude.toFixed(0) + "m"; color: Theme.green }
                TelemetryDataRow { icon: "⏱"; title: "Spd"; value: mavlink.groundSpeed.toFixed(1); color: Theme.orange }
            }
            RowLayout {
                spacing: 6
                TelemetryDataRow { icon: "⌖"; title: "Hdg"; value: mavlink.heading.toFixed(0) + "°"; color: Theme.purple }
                TelemetryDataRow {
                    icon: "⚡"; title: "Bat"; value: mavlink.batteryVoltage.toFixed(1) + "V"
                    color: mavlink.batteryVoltage < 10.5 ? Theme.red : (mavlink.batteryVoltage < 11.1 ? Theme.orange : Theme.green)
                }
            }
            TelemetryDataRow {
                icon: "⩡"; title: "SAT"; value: mavlink.gpsSatellites
                color: mavlink.gpsSatellites >= 8 ? Theme.green : (mavlink.gpsSatellites >= 5 ? Theme.orange : Theme.red)
            }
        }
    }

    // Bottom controls: follow toggle + clear
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        anchors.bottomMargin: 30
        Rectangle {
            implicitWidth: 44; implicitHeight: 44; radius: 22
            color: Theme.withAlpha(Theme.black, 0.4)
            Text {
                anchors.centerIn: parent
                text: root.following ? "◉" : "◎"
                color: root.following ? Theme.cyan : Theme.white
                font.pixelSize: 20
                font.bold: true
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.following = !root.following
                    if (root.following) root.centerOnDrone()
                }
            }
        }
        Item { Layout.fillWidth: true }
        Rectangle {
            radius: height / 2
            color: Theme.withAlpha(Theme.black, 0.4)
            implicitWidth: clearRow.implicitWidth + 32
            implicitHeight: 40
            RowLayout {
                id: clearRow
                anchors.centerIn: parent
                spacing: 6
                Text { text: "✖"; color: Theme.white; font.pixelSize: 14 }
                Text { text: "Clear"; color: Theme.white; font.pixelSize: 14; font.weight: Font.DemiBold }
            }
            MouseArea { anchors.fill: parent; onClicked: root.clearFlightPath() }
        }
    }

    component TelemetryDataRow: RowLayout {
        property string icon: ""
        property string title: ""
        property string value: ""
        property color color: Theme.cyan
        Layout.fillWidth: true
        spacing: 6
        Text { text: icon; color: parent.color; font.pixelSize: 12; font.bold: true; Layout.preferredWidth: 14 }
        Text { text: title; color: Theme.withAlpha(Theme.white, 0.7); font.pixelSize: 10; font.weight: Font.Medium; Layout.preferredWidth: 28 }
        Item { Layout.fillWidth: true }
        Text { text: value; color: Theme.white; font.pixelSize: 11; font.bold: true; font.family: Theme.mono }
    }
}
