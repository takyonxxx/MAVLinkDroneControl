// GpsPage.qml - port of GPSView.swift (GPS diagnostics: sensor bits, stream rate,
// fix, raw GPS_RAW_INT fields and GPS-related STATUSTEXT).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DroneControl 1.0
import "../components"

Item {
    id: page

    property real nowMs: Date.now()
    Timer { interval: 1000; repeat: true; running: page.visible; onTriggered: page.nowMs = Date.now() }

    readonly property int gpsSensorBit: 32           // MAV_SYS_STATUS_SENSOR_GPS
    readonly property var raw: mavlink.gpsRaw
    readonly property bool rawReceived: raw.received === true
    readonly property int fixType: rawReceived ? raw.fixType : 0
    readonly property string fixNameText: rawReceived ? raw.fixName : "NO GPS"
    readonly property int sats: rawReceived ? raw.satellitesVisible : 255
    readonly property bool sensorPresent: (mavlink.sensorsPresent & gpsSensorBit) !== 0
    readonly property bool sensorEnabled: (mavlink.sensorsEnabled & gpsSensorBit) !== 0
    readonly property bool sensorHealthy: (mavlink.sensorsHealth & gpsSensorBit) !== 0
    readonly property bool dataFlowing: rawReceived && (nowMs - raw.lastReceived) < 3000
    readonly property string secondsSinceLast: {
        if (!rawReceived) return "never"
        var dt = (nowMs - raw.lastReceived) / 1000
        return dt < 1 ? "<1 s ago" : dt.toFixed(0) + " s ago"
    }
    readonly property string hdopText: rawReceived && raw.eph !== 65535 ? (raw.eph / 100).toFixed(2) : "--"
    readonly property string vdopText: rawReceived && raw.epv !== 65535 ? (raw.epv / 100).toFixed(2) : "--"

    readonly property var verdict: {
        if (!mavlink.connected)
            return { text: "NOT CONNECTED", detail: "No MAVLink link to the flight controller.", color: Theme.red }
        if (mavlink.sysStatusReceived && !sensorPresent)
            return { text: "GPS NOT DETECTED", detail: "SYS_STATUS reports no GPS sensor. Check wiring/port (SERIALx_PROTOCOL=5, GPS_TYPE) and power.", color: Theme.red }
        if (!rawReceived || !dataFlowing)
            return { text: "NO GPS DATA", detail: "GPS_RAW_INT is not arriving. Either the FC has no GPS driver active or the stream is not enabled.", color: Theme.red }
        if (fixType === 0)
            return { text: "GPS DRIVER: NO GPS", detail: "FC is streaming GPS_RAW_INT but reports fix type 0 (no module talking on the port). Check TX/RX crossover and baud.", color: Theme.orange }
        if (fixType === 1)
            return { text: "GPS DETECTED - NO FIX", detail: "Module is communicating (" + (sats === 255 ? "?" : sats) + " sats). Waiting for a fix - needs open sky.", color: Theme.orange }
        if (fixType === 2)
            return { text: "2D FIX", detail: "Horizontal position only, altitude not valid yet.", color: Theme.yellow }
        if (!sensorHealthy && mavlink.sysStatusReceived)
            return { text: fixNameText + " - UNHEALTHY", detail: "Fix present but FC flags GPS as unhealthy (HDOP/accuracy or lag). Check antenna placement/interference.", color: Theme.orange }
        return { text: fixNameText, detail: "GPS healthy. " + sats + " satellites, HDOP " + hdopText + ".", color: Theme.green }
    }

    readonly property color fixColor: fixType <= 1 ? Theme.red : (fixType === 2 ? Theme.yellow : Theme.green)
    readonly property string gpsTimeText: {
        if (!rawReceived || raw.timeUsec <= 0) return "--"
        var d = new Date(Number(raw.timeUsec) / 1000)
        function two(n) { return (n < 10 ? "0" : "") + n }
        return d.getUTCFullYear() + "-" + two(d.getUTCMonth() + 1) + "-" + two(d.getUTCDate()) + " "
             + two(d.getUTCHours()) + ":" + two(d.getUTCMinutes()) + ":" + two(d.getUTCSeconds()) + " UTC"
    }
    function hex8(v) {
        var s = (v >>> 0).toString(16).toUpperCase()
        while (s.length < 8) s = "0" + s
        return "0x" + s
    }

    property var gpsMessages: []
    function refreshMessages() { gpsMessages = mavlink.messages.filtered(["GPS", "GNSS"], 15) }
    Connections { target: mavlink.messages; function onCountChanged() { page.refreshMessages() } }
    Component.onCompleted: refreshMessages()

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
            x: 16; y: 16
            width: parent.width - 32
            spacing: 16

            // Verdict
            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: Theme.overlay
                border.width: 1
                border.color: Theme.withAlpha(page.verdict.color, 0.6)
                implicitHeight: vc.implicitHeight + 28
                ColumnLayout {
                    id: vc
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8
                    RowLayout {
                        spacing: 8
                        Rectangle { implicitWidth: 14; implicitHeight: 14; radius: 7; color: page.verdict.color }
                        Text { text: page.verdict.text; color: Theme.white; font.pixelSize: 18; font.bold: true; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    }
                    Text { text: page.verdict.detail; color: Theme.gray; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                }
            }

            Card {
                title: "Hardware / Link"; color: Theme.overlay
                StatusRow { label: "SYS_STATUS received"; ok: mavlink.sysStatusReceived; text: mavlink.sysStatusReceived ? "yes" : "waiting" }
                StatusRow { label: "GPS sensor present"; ok: page.sensorPresent; text: mavlink.sysStatusReceived ? (page.sensorPresent ? "PRESENT" : "ABSENT") : "--" }
                StatusRow { label: "GPS sensor enabled"; ok: page.sensorEnabled; text: mavlink.sysStatusReceived ? (page.sensorEnabled ? "ENABLED" : "DISABLED") : "--" }
                StatusRow { label: "GPS sensor healthy"; ok: page.sensorHealthy; text: mavlink.sysStatusReceived ? (page.sensorHealthy ? "HEALTHY" : "UNHEALTHY") : "--" }
                HDivider {}
                StatusRow { label: "GPS_RAW_INT stream"; ok: page.dataFlowing; text: page.dataFlowing ? "FLOWING" : "STALLED" }
                KeyValueRow { label: "Message count"; value: page.rawReceived ? raw.messageCount : 0 }
                KeyValueRow { label: "Rate"; value: page.rawReceived ? raw.rateHz.toFixed(1) + " Hz (requested 5 Hz)" : "--" }
                KeyValueRow { label: "Last message"; value: page.secondsSinceLast }
            }

            Card {
                title: "Fix"; color: Theme.overlay
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: page.fixNameText; color: page.fixColor; font.pixelSize: 28; font.bold: true; font.family: Theme.mono }
                    Item { Layout.fillWidth: true }
                    ColumnLayout {
                        spacing: 0
                        Text { text: page.sats === 255 ? "--" : page.sats; color: Theme.white; font.pixelSize: 28; font.bold: true; font.family: Theme.mono; Layout.alignment: Qt.AlignRight }
                        Text { text: "satellites"; color: Theme.gray; font.pixelSize: 11; Layout.alignment: Qt.AlignRight }
                    }
                }
                KeyValueRow { label: "fix_type (raw)"; value: page.fixType }
                KeyValueRow { label: "HDOP"; value: page.hdopText }
                KeyValueRow { label: "VDOP"; value: page.vdopText }
                KeyValueRow { label: "GPS time"; value: page.gpsTimeText }
            }

            Card {
                id: posCard
                title: "Position (GPS_RAW_INT)"; color: Theme.overlay
                readonly property bool valid: page.fixType >= 2
                KeyValueRow { label: "Latitude"; value: posCard.valid ? (raw.lat / 1e7).toFixed(7) : "--" }
                KeyValueRow { label: "Longitude"; value: posCard.valid ? (raw.lon / 1e7).toFixed(7) : "--" }
                KeyValueRow { label: "Alt MSL"; value: page.fixType >= 3 ? (raw.alt / 1000).toFixed(2) + " m" : "--" }
                KeyValueRow { label: "Alt ellipsoid"; value: page.fixType >= 3 && raw.altEllipsoid !== 0 ? (raw.altEllipsoid / 1000).toFixed(2) + " m" : "--" }
                KeyValueRow { label: "Ground speed"; value: page.rawReceived && raw.vel !== 65535 ? (raw.vel / 100).toFixed(2) + " m/s" : "--" }
                KeyValueRow { label: "Course over ground"; value: page.rawReceived && raw.cog !== 65535 ? (raw.cog / 100).toFixed(2) + " deg" : "--" }
                KeyValueRow { label: "GPS yaw"; value: page.rawReceived && raw.yaw !== 0 ? (raw.yaw / 100).toFixed(2) + " deg" : "n/a" }
            }

            Card {
                title: "Accuracy estimates"; color: Theme.overlay
                KeyValueRow { label: "Horizontal (h_acc)"; value: page.rawReceived && raw.hAcc !== 0 ? (raw.hAcc / 1000).toFixed(2) + " m" : "--" }
                KeyValueRow { label: "Vertical (v_acc)"; value: page.rawReceived && raw.vAcc !== 0 ? (raw.vAcc / 1000).toFixed(2) + " m" : "--" }
                KeyValueRow { label: "Speed (vel_acc)"; value: page.rawReceived && raw.velAcc !== 0 ? (raw.velAcc / 1000).toFixed(2) + " m/s" : "--" }
                KeyValueRow { label: "Heading (hdg_acc)"; value: page.rawReceived && raw.hdgAcc !== 0 ? (raw.hdgAcc / 1e5).toFixed(2) + " deg" : "--" }
            }

            Card {
                title: "Raw fields"; color: Theme.overlay
                Repeater {
                    model: [
                        ["time_usec", page.rawReceived ? String(raw.timeUsec) : "0"],
                        ["fix_type", page.fixType],
                        ["lat", page.rawReceived ? raw.lat : 0],
                        ["lon", page.rawReceived ? raw.lon : 0],
                        ["alt", page.rawReceived ? raw.alt : 0],
                        ["eph", page.rawReceived ? raw.eph : 65535],
                        ["epv", page.rawReceived ? raw.epv : 65535],
                        ["vel", page.rawReceived ? raw.vel : 65535],
                        ["cog", page.rawReceived ? raw.cog : 65535],
                        ["satellites_visible", page.sats],
                        ["alt_ellipsoid", page.rawReceived ? raw.altEllipsoid : 0],
                        ["h_acc", page.rawReceived ? raw.hAcc : 0],
                        ["v_acc", page.rawReceived ? raw.vAcc : 0],
                        ["vel_acc", page.rawReceived ? raw.velAcc : 0],
                        ["hdg_acc", page.rawReceived ? raw.hdgAcc : 0],
                        ["yaw", page.rawReceived ? raw.yaw : 0],
                        ["sensors_present", page.hex8(mavlink.sensorsPresent)],
                        ["sensors_enabled", page.hex8(mavlink.sensorsEnabled)],
                        ["sensors_health", page.hex8(mavlink.sensorsHealth)]
                    ]
                    KeyValueRow {
                        required property var modelData
                        label: modelData[0]; value: String(modelData[1])
                        labelColor: Theme.cyan; monoLabel: true; fontSize: 11
                    }
                }
            }

            Card {
                title: "GPS status messages (STATUSTEXT)"; color: Theme.overlay
                Text {
                    visible: page.gpsMessages.length === 0
                    text: "No GPS-related messages yet. ArduPilot prints e.g. \"GPS 1: detected as u-blox\" at boot."
                    color: Theme.gray; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
                Repeater {
                    model: page.gpsMessages
                    RowLayout {
                        required property var modelData
                        spacing: 8
                        Layout.fillWidth: true
                        Text { text: modelData.time; color: Theme.gray; font.pixelSize: 11; font.family: Theme.mono; Layout.alignment: Qt.AlignTop }
                        Text {
                            text: modelData.severityName
                            color: modelData.severity <= 3 ? Theme.red : (modelData.severity === 4 ? Theme.orange : Theme.cyan)
                            font.pixelSize: 11; font.bold: true; Layout.alignment: Qt.AlignTop
                        }
                        Text { text: modelData.text; color: Theme.white; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    }
                }
            }
        }
    }

    component StatusRow: RowLayout {
        property string label: ""
        property bool ok: false
        property string text: ""
        Layout.fillWidth: true
        spacing: 6
        Text { text: parent.label; color: Theme.gray; font.pixelSize: 12 }
        Item { Layout.fillWidth: true }
        Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: parent.ok ? Theme.green : Theme.red }
        Text { text: parent.text; color: parent.ok ? Theme.green : Theme.red; font.pixelSize: 12; font.family: Theme.mono }
    }
}
