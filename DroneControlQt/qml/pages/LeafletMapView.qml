// LeafletMapView.qml - Leaflet map (port of the MapWidget) in a WebView with a
// mission-planning toolbar. Satellite (Esri World Imagery) / street (OSM) / hybrid,
// OpenSeaMap seamarks overlay, vehicle marker + traversed path, home, draggable
// numbered waypoints, guided "fly here", mission upload/download/start.
//
// QML -> page: webView.runJavaScript("qt...()")   page -> QML: polled event queue (qtPullEvents)
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebView
import DroneControl 1.0
import "../components"

Item {
    id: root
    property bool pageReady: false
    property bool following: true
    property string layerName: "satellite"
    property bool seamarks: false
    property string clickMode: "none"        // none | addwp | goto
    property real missionAlt: 15
    property bool rtlAtEnd: true
    property bool compact: width < 700
    property string loadStatus: "Loading map page..."
    property bool loadFailed: false
    signal failed()                          // MapPage falls back to the Qt Location map
    property int tilesOk: -1                 // -1 unknown, 0 tile requests failing, 1 tiles loading

    function js(code) { if (pageReady) webView.runJavaScript(code) }
    function pushMission() { js("qtSetMission(" + JSON.stringify(mavlink.missionWaypoints) + ")") }
    function setClickMode(m) { clickMode = m; js("qtSetClickMode('" + m + "')") }

    WebView {
        id: webView
        anchors.fill: parent
        Component.onCompleted: {
            if (!mapHtml || mapHtml.length === 0) {
                root.loadStatus = "Map page missing from resources (web/map.html)"
                root.loadFailed = true
                console.log("[MAP] mapHtml is empty")
                return
            }
            console.log("[MAP] loading page, " + mapHtml.length + " chars")
            loadHtml(mapHtml, "http://dronecontrol.local/")   // http: tiles come from http://127.0.0.1 (no mixed-content block)
            readyTimeout.start()
        }
        onLoadingChanged: function(req) {
            if (req.status === WebView.LoadSucceededStatus) {
                console.log("[MAP] page loaded, waiting for Leaflet")
                root.loadStatus = "Page loaded, starting Leaflet..."
                readyProbe.start()            // wait for the page script to flag readiness
            } else if (req.status === WebView.LoadFailedStatus) {
                console.log("[MAP] page load failed:", req.errorString)
                root.loadStatus = "Map page failed to load: " + req.errorString
                root.loadFailed = true
                root.failed()
            } else if (req.status === WebView.LoadStartedStatus) {
                root.loadStatus = "Loading map page..."
            }
        }
    }

    Timer {
        id: readyTimeout
        interval: 10000
        onTriggered: if (!root.pageReady) {
            root.loadStatus = "Map page did not start within 10 s.\nOn Windows/Linux the Qt WebView backend is Qt WebEngine: " +
                              "check that the Qt WebEngine module is installed for this kit and see the Application Output for [MAP] lines."
            root.loadFailed = true
            console.log("[MAP] page did not report ready within 10 s")
            root.failed()
        }
    }

    // tile-server warning (page works, imagery does not arrive)
    Rectangle {
        visible: root.pageReady && root.tilesOk === 0
        anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; anchors.topMargin: 8
        width: Math.min(parent.width - 120, tileWarn.implicitWidth + 24); height: tileWarn.implicitHeight + 14
        radius: 8; color: "#cc3a2a00"; border.color: Theme.orange; z: 5
        Text {
            id: tileWarn
            anchors.centerIn: parent; width: parent.width - 24
            text: "Map tiles are not loading: no internet access and this area is not in the offline cache (" + tiles.cachedTiles + " tiles cached). " +
                  "Open the map once with internet, or use 'Cache map' to pre-download the area."
            color: Theme.orange; font.pixelSize: 12; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
        }
    }

    // status overlay until the Leaflet page is up
    Rectangle {
        anchors.fill: parent
        visible: !root.pageReady
        color: Theme.bg
        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 460)
            spacing: 12
            Text { text: root.loadFailed ? "!" : "▦"; color: root.loadFailed ? Theme.red : Theme.gray; font.pixelSize: 40; Layout.alignment: Qt.AlignHCenter }
            Text {
                text: root.loadStatus
                color: root.loadFailed ? Theme.red : Theme.gray
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }

    Timer {
        id: readyProbe
        interval: 200; repeat: true
        onTriggered: webView.runJavaScript("window.qtReady === true", function(r) {
            if (r === true) {
                readyProbe.stop()
                readyTimeout.stop()
                console.log("[MAP] Leaflet page ready")
                root.pageReady = true
                root.js("qtSetLayer('" + root.layerName + "'); qtSetSeamarks(" + root.seamarks + "); qtFollow(" + root.following + ")")
                if (mavlink.homeValid) root.js("qtSetHome(" + mavlink.homeLatitude + "," + mavlink.homeLongitude + ")")
                root.pushMission()
                root.js("qtSetCurrentSeq(" + mavlink.missionCurrentSeq + ")")
                root.js("qtSetBottomInset(" + Math.round(toolbar.height + 10) + ")")
                root.pushVehicle()
                mavlink.requestHome()
            }
        })
    }

    // page -> QML events
    Timer {
        interval: 150; repeat: true; running: root.pageReady && root.visible
        onTriggered: webView.runJavaScript("qtPullEvents()", function(res) {
            if (!res || res === "[]") return
            var evs
            try { evs = JSON.parse(res) } catch (e) { return }
            for (var i = 0; i < evs.length; i++) {
                var e = evs[i]
                switch (e.type) {
                case "center": tiles.downloadArea(e.lat, e.lng, 2000, 12, 18); break
                case "tiles":
                    root.tilesOk = e.ok
                    console.log("[MAP] tiles " + (e.ok ? "loading OK" : "FAILED: " + e.url))
                    break
                case "wpAdd": mavlink.addWaypoint(e.lat, e.lng, root.missionAlt); break
                case "wpMove": mavlink.moveWaypoint(e.index, e.lat, e.lng); break
                case "wpDelete": mavlink.removeWaypoint(e.index); break
                case "goto": mavlink.gotoLocation(e.lat, e.lng, root.missionAlt); break
                case "followOff": root.following = false; break
                }
            }
        })
    }

    // QML -> page updates (throttled to the GPS rate)
    property real lastPush: 0
    function pushVehicle() {
        js("qtSetVehicle(" + mavlink.latitude + "," + mavlink.longitude + "," + mavlink.heading + "," +
           mavlink.groundSpeed + "," + mavlink.armed + ")")
    }
    Connections {
        target: mavlink
        function onPositionChanged() {
            var now = Date.now()
            if (now - root.lastPush < 180) return
            root.lastPush = now
            root.pushVehicle()
        }
        function onMissionChanged() { root.pushMission(); root.js("qtSetCurrentSeq(" + mavlink.missionCurrentSeq + ")") }
        function onHomeChanged() { if (mavlink.homeValid) root.js("qtSetHome(" + mavlink.homeLatitude + "," + mavlink.homeLongitude + ")") }
        function onHeartbeatAliveChanged() { if (mavlink.heartbeatAlive) mavlink.requestHome() }
        function onGuidedTargetChanged() {
            if (mavlink.guidedTargetValid) root.js("qtSetGuidedTarget(" + mavlink.guidedTargetLatitude + "," + mavlink.guidedTargetLongitude + ")")
            else root.js("qtSetGuidedTarget(0,0)")
        }
    }
    onFollowingChanged: js("qtFollow(" + following + ")")
    Component.onCompleted: mavlink.requestHome()

    // ---------------- overlay: top-right telemetry ----------------
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        width: compact ? 170 : 220
        radius: 12
        color: Theme.withAlpha(Theme.black, 0.55)
        implicitHeight: tp.implicitHeight + 16
        ColumnLayout {
            id: tp
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4
            RowLayout { Text { text: "Mode"; color: Theme.gray; font.pixelSize: 10; Layout.preferredWidth: 34 } Text { text: mavlink.flightModeName; color: mavlink.flightModeColor; font.pixelSize: 12; font.bold: true } Item { Layout.fillWidth: true } Text { text: mavlink.armed ? "ARMED" : "DISARMED"; color: mavlink.armed ? Theme.orange : Theme.gray; font.pixelSize: 10; font.bold: true } }
            RowLayout { Text { text: "Alt"; color: Theme.gray; font.pixelSize: 10; Layout.preferredWidth: 34 } Text { text: mavlink.relativeAltitude.toFixed(1) + " m"; color: Theme.green; font.pixelSize: 12; font.bold: true; font.family: Theme.mono } Item { Layout.fillWidth: true } Text { text: "Spd"; color: Theme.gray; font.pixelSize: 10 } Text { text: mavlink.groundSpeed.toFixed(1) + " m/s"; color: Theme.orange; font.pixelSize: 12; font.bold: true; font.family: Theme.mono } }
            RowLayout { Text { text: "Hdg"; color: Theme.gray; font.pixelSize: 10; Layout.preferredWidth: 34 } Text { text: mavlink.heading.toFixed(0) + "°"; color: Theme.purple; font.pixelSize: 12; font.bold: true; font.family: Theme.mono } Item { Layout.fillWidth: true } Text { text: "Bat"; color: Theme.gray; font.pixelSize: 10 } Text { text: mavlink.batteryVoltage.toFixed(1) + "V"; color: Theme.voltageColor(mavlink.batteryVoltage); font.pixelSize: 12; font.bold: true; font.family: Theme.mono } }
            RowLayout { Text { text: "WP"; color: Theme.gray; font.pixelSize: 10; Layout.preferredWidth: 34 } Text { text: mavlink.missionCurrentSeq + " / " + Math.max(0, mavlink.missionCountOnVehicle - 1); color: Theme.cyan; font.pixelSize: 12; font.bold: true; font.family: Theme.mono } Item { Layout.fillWidth: true } Text { text: "Sat"; color: Theme.gray; font.pixelSize: 10 } Text { text: mavlink.gpsSatellites; color: mavlink.gpsFixType >= 3 ? Theme.green : Theme.red; font.pixelSize: 12; font.bold: true; font.family: Theme.mono } }
        }
    }

    // ---------------- overlay: left column map controls ----------------
    ColumnLayout {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 10
        anchors.topMargin: 90
        spacing: 8
        MapButton { text: root.following ? "◉" : "◎"; active: root.following; tip: "Follow"; onClicked: { root.following = !root.following; if (root.following) root.js("qtCenterVehicle()") } }
        MapButton { text: "⌂"; tip: "Home"; onClicked: if (mavlink.homeValid) root.js("qtCenterOn(" + mavlink.homeLatitude + "," + mavlink.homeLongitude + ",17)") }
        MapButton { text: root.layerName === "satellite" ? "S" : (root.layerName === "street" ? "M" : "H"); tip: "Layer"
            onClicked: { root.layerName = root.layerName === "satellite" ? "street" : (root.layerName === "street" ? "hybrid" : "satellite"); root.js("qtSetLayer('" + root.layerName + "')") } }
        MapButton { text: "⚓"; active: root.seamarks; tip: "Seamarks"; onClicked: { root.seamarks = !root.seamarks; root.js("qtSetSeamarks(" + root.seamarks + ")") } }
        MapButton { text: "✖"; tip: "Clear path"; onClicked: root.js("qtClearPath()") }
        MapButton { text: "⛶"; tip: "Fit mission"; onClicked: { root.following = false; root.js("qtFitMission()") } }
    }

    // ---------------- overlay: bottom mission toolbar ----------------
    Rectangle {
        id: toolbar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 10
        radius: 12
        color: Theme.withAlpha(Theme.black, 0.6)
        implicitHeight: bar.implicitHeight + 16
        onHeightChanged: root.js("qtSetBottomInset(" + Math.round(height + 10) + ")")

        ColumnLayout {
            id: bar
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            // status line
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    implicitWidth: 8; implicitHeight: 8; radius: 4
                    color: mavlink.missionState === "error" ? Theme.red : (mavlink.missionState === "ok" ? Theme.green : (mavlink.missionState === "idle" ? Theme.gray : Theme.orange))
                }
                Text {
                    text: mavlink.missionWaypoints.length + " waypoint(s)" + (mavlink.missionStatusText !== "" ? "  •  " + mavlink.missionStatusText : "")
                    color: Theme.white; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true
                }
                Text { text: "Alt"; color: Theme.gray; font.pixelSize: 11 }
                SpinBox {
                    id: altSpin
                    from: 2; to: 120; value: root.missionAlt; stepSize: 1
                    editable: true
                    implicitWidth: 96; implicitHeight: 30
                    font.pixelSize: 12
                    onValueModified: root.missionAlt = value
                }
                Text { text: "m"; color: Theme.gray; font.pixelSize: 11 }
                CheckBox {
                    text: "RTL at end"; checked: root.rtlAtEnd
                    font.pixelSize: 11
                    implicitHeight: 28
                    onToggled: root.rtlAtEnd = checked
                }
            }

            // buttons (wrap on narrow screens)
            Flow {
                Layout.fillWidth: true
                spacing: 6
                ToolBtn { text: root.clickMode === "addwp" ? "● Adding WP" : "+ Waypoint"; active: root.clickMode === "addwp"
                    onClicked: root.setClickMode(root.clickMode === "addwp" ? "none" : "addwp") }
                ToolBtn { text: root.clickMode === "goto" ? "● Fly here" : "Fly here"; active: root.clickMode === "goto"; activeColor: Theme.cyan
                    onClicked: root.setClickMode(root.clickMode === "goto" ? "none" : "goto") }
                ToolBtn { text: "Clear"; onClicked: { mavlink.clearLocalMission(); root.setClickMode("none") } }
                ToolBtn { text: "Upload"; bg: Theme.blue; enabled: mavlink.connected && mavlink.missionWaypoints.length > 0
                    onClicked: mavlink.uploadMission(root.missionAlt, root.rtlAtEnd) }
                ToolBtn { text: "Download"; enabled: mavlink.connected; onClicked: mavlink.downloadMission() }
                ToolBtn { text: "Clear on vehicle"; enabled: mavlink.connected; onClicked: mavlink.clearVehicleMission() }
                ToolBtn { text: "Takeoff " + root.missionAlt + " m"; bg: Theme.armGreen1; enabled: mavlink.connected && mavlink.armed
                    onClicked: mavlink.takeoff(root.missionAlt) }
                ToolBtn { text: "Start AUTO"; bg: Theme.purple; enabled: mavlink.connected && mavlink.missionCountOnVehicle > 1
                    onClicked: mavlink.startMission() }
                ToolBtn { text: "RTL"; bg: Theme.red; enabled: mavlink.connected; onClicked: mavlink.setFlightMode(6) }
                ToolBtn { text: "Land"; bg: Theme.brown; enabled: mavlink.connected; onClicked: mavlink.setFlightMode(9) }
                ToolBtn {
                    // offline cache: pre-download satellite tiles (2 km radius, zoom 12-18) around the vehicle / home
                    text: tiles.downloading ? ("Caching " + tiles.downloadDone + "/" + tiles.downloadTotal)
                                            : ("Cache map (" + tiles.cachedTiles + ")")
                    bg: tiles.downloading ? Theme.orange : Theme.card
                    enabled: tiles.port > 0
                    onClicked: {
                        if (tiles.downloading) { tiles.cancelDownload(); return }
                        var lat = mavlink.gpsFixType >= 2 ? mavlink.latitude : (mavlink.homeValid ? mavlink.homeLatitude : 0)
                        var lon = mavlink.gpsFixType >= 2 ? mavlink.longitude : (mavlink.homeValid ? mavlink.homeLongitude : 0)
                        if (lat === 0 && lon === 0) { root.js("qtGetCenter()"); return }
                        tiles.downloadArea(lat, lon, 2000, 12, 18)
                    }
                }
            }
        }
    }

    // ---------------- components ----------------
    component MapButton: Rectangle {
        property string text: ""
        property string tip: ""
        property bool active: false
        signal clicked()
        implicitWidth: 40; implicitHeight: 40; radius: 20
        color: active ? Theme.withAlpha(Theme.cyan, 0.85) : Theme.withAlpha(Theme.black, 0.55)
        border.width: 1; border.color: Theme.withAlpha(Theme.white, 0.25)
        Text { anchors.centerIn: parent; text: parent.text; color: parent.active ? Theme.black : Theme.white; font.pixelSize: 17; font.bold: true }
        ToolTip.visible: hover.hovered && tip !== ""
        ToolTip.text: tip
        ToolTip.delay: 500
        HoverHandler { id: hover }
        MouseArea { anchors.fill: parent; onClicked: parent.clicked() }
    }

    component ToolBtn: Rectangle {
        property string text: ""
        property bool active: false
        property bool enabled: true
        property color bg: Theme.card3
        property color activeColor: Theme.orange
        signal clicked()
        implicitWidth: label.implicitWidth + 22
        implicitHeight: 32
        radius: 8
        color: active ? activeColor : bg
        opacity: enabled ? 1 : 0.45
        Text { id: label; anchors.centerIn: parent; text: parent.text; color: parent.active ? Theme.black : Theme.white; font.pixelSize: 12; font.weight: Font.DemiBold }
        MouseArea { anchors.fill: parent; enabled: parent.enabled; onClicked: parent.clicked() }
    }
}
