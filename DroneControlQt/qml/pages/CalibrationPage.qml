// CalibrationPage.qml - port of CalibrationView.swift
//  - Compass: DO_START_MAG_CAL -> MAG_CAL_PROGRESS (percent + geodesic section mask)
//             -> MAG_CAL_REPORT (fitness) -> DO_ACCEPT_MAG_CAL (write to params)
//  - Gyro:    PREFLIGHT_CALIBRATION param1=1 (vehicle must be still)
//  - Baro:    PREFLIGHT_CALIBRATION param3=1 (ground pressure)
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DroneControl 1.0
import "../components"

Item {
    id: page

    property real nowMs: Date.now()
    Timer { interval: 500; repeat: true; running: page.visible; onTriggered: page.nowMs = Date.now() }

    readonly property bool canCalibrate: mavlink.connected && !mavlink.armedByPilot

    // Compass ids seen in progress or reports
    readonly property var compassIds: {
        var ids = {}
        var i
        for (i = 0; i < mavlink.magCalProgress.length; i++) ids[mavlink.magCalProgress[i].compassId] = true
        for (i = 0; i < mavlink.magCalReports.length; i++) ids[mavlink.magCalReports[i].compassId] = true
        var out = Object.keys(ids).map(Number)
        out.sort(function(a, b) { return a - b })
        return out
    }
    function progressFor(id) {
        for (var i = 0; i < mavlink.magCalProgress.length; i++)
            if (mavlink.magCalProgress[i].compassId === id) return mavlink.magCalProgress[i]
        return null
    }
    function reportFor(id) {
        for (var i = 0; i < mavlink.magCalReports.length; i++)
            if (mavlink.magCalReports[i].compassId === id) return mavlink.magCalReports[i]
        return null
    }
    readonly property int overallPct: {
        var p = mavlink.magCalProgress
        if (p.length === 0) return 0
        if (mavlink.magCalReports.length > 0 && !mavlink.magCalRunning) return 100
        var sum = 0
        for (var i = 0; i < p.length; i++) sum += p[i].completionPct
        return Math.floor(sum / p.length)
    }
    readonly property bool allReportsSuccess: {
        if (mavlink.magCalReports.length === 0) return false
        for (var i = 0; i < mavlink.magCalReports.length; i++)
            if (!mavlink.magCalReports[i].success) return false
        return true
    }

    function statusColor(s) {
        if (s === 4) return Theme.green
        if (s === 5 || s === 6 || s === 7) return Theme.red
        if (s === 2 || s === 3) return Theme.orange
        return Theme.gray
    }
    function fitnessColor(f) {
        if (f < 10) return Theme.green
        if (f < 20) return Theme.yellow
        if (f < 40) return Theme.orange
        return Theme.red
    }
    function directionHint(p) {
        var x = p.directionX, y = p.directionY, z = p.directionZ
        if (Math.abs(x) < 0.01 && Math.abs(y) < 0.01 && Math.abs(z) < 0.01) return "Keep rotating..."
        var ax = Math.abs(x), ay = Math.abs(y), az = Math.abs(z)
        if (ax >= ay && ax >= az) return x > 0 ? "Point nose UP more" : "Point nose DOWN more"
        if (ay >= ax && ay >= az) return y > 0 ? "Roll RIGHT side down" : "Roll LEFT side down"
        return z > 0 ? "Turn vehicle UPSIDE DOWN" : "Hold vehicle LEVEL / upright"
    }
    function isInProgress(st) { return st.state === "inProgress" }

    // Calibration-related STATUSTEXT (newest first, 12 entries)
    property var calMessages: []
    function refreshMessages() {
        calMessages = mavlink.messages.filtered(["CALIB", "COMPASS", "MAG", "GYRO", "BARO", "PRESSURE", "INS"], 12)
    }
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

            Banner { visible: !mavlink.connected; text: "Not connected" }
            Banner { visible: mavlink.connected && mavlink.armedByPilot; text: "Vehicle is ARMED - disarm before calibrating" }

            // ---------------- Compass ----------------
            Card {
                title: "Compass"; icon: "⌖"; color: Theme.overlay
                Text {
                    text: "Rotate the vehicle slowly around all axes until every section fills. Keep away from metal, magnets and motors running."
                    color: Theme.gray; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: mavlink.magCalRunning ? "CALIBRATING" : (mavlink.magCalReports.length === 0 ? "IDLE" : "COMPLETE")
                        color: mavlink.magCalRunning ? Theme.orange : Theme.white
                        font.pixelSize: 12; font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: page.overallPct + "%"
                        color: page.overallPct >= 100 ? Theme.green : Theme.cyan
                        font.pixelSize: 32; font.bold: true; font.family: Theme.mono
                    }
                }
                ProgressBar { Layout.fillWidth: true; from: 0; to: 100; value: page.overallPct }

                KeyValueRow {
                    visible: mavlink.magCalStartAck !== ""
                    label: "Start ACK"; value: mavlink.magCalStartAck
                    valueColor: mavlink.magCalStartAck === "ACCEPTED" ? Theme.green : Theme.red
                }

                // Per-compass detail
                Repeater {
                    model: page.compassIds
                    Rectangle {
                        id: det
                        required property int modelData
                        readonly property var prog: page.progressFor(modelData)
                        readonly property var rep: page.reportFor(modelData)
                        Layout.fillWidth: true
                        radius: 8
                        color: Theme.withAlpha(Theme.white, 0.05)
                        implicitHeight: dc.implicitHeight + 20
                        ColumnLayout {
                            id: dc
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6
                            RowLayout {
                                Text { text: "Compass " + (det.modelData + 1); color: Theme.white; font.pixelSize: 14; font.bold: true }
                                Item { Layout.fillWidth: true }
                                Text {
                                    visible: det.prog !== null
                                    text: det.rep ? det.rep.statusName : (det.prog ? det.prog.statusName : "")
                                    color: page.statusColor(det.rep ? det.rep.status : (det.prog ? det.prog.status : 0))
                                    font.pixelSize: 11; font.bold: true
                                }
                            }
                            RowLayout {
                                visible: det.prog !== null
                                Text { text: det.prog ? det.prog.completionPct + "%" : ""; color: Theme.cyan; font.pixelSize: 18; font.bold: true; font.family: Theme.mono }
                                Item { Layout.fillWidth: true }
                                Text { text: det.prog ? "attempt " + det.prog.attempt + "  sections " + det.prog.sectionsDone + "/80" : ""; color: Theme.gray; font.pixelSize: 11 }
                            }
                            // 80 geodesic sections: 8 rows x 10 columns
                            GridLayout {
                                visible: det.prog !== null
                                Layout.fillWidth: true
                                columns: 10
                                columnSpacing: 3
                                rowSpacing: 3
                                Repeater {
                                    model: 80
                                    Rectangle {
                                        required property int index
                                        readonly property bool set: det.prog !== null && ((det.prog.completionMask[Math.floor(index / 8)] >> (index % 8)) & 1) === 1
                                        Layout.fillWidth: true
                                        implicitHeight: 10
                                        radius: 2
                                        color: set ? Theme.green : Theme.withAlpha(Theme.white, 0.12)
                                    }
                                }
                            }
                            Text {
                                visible: det.prog !== null && mavlink.magCalRunning
                                text: det.prog ? page.directionHint(det.prog) : ""
                                color: Theme.orange; font.pixelSize: 11
                            }

                            HDivider { visible: det.rep !== null }
                            RowLayout {
                                visible: det.rep !== null
                                spacing: 6
                                Text { text: "Fitness"; color: Theme.gray; font.pixelSize: 12 }
                                Text { text: det.rep ? det.rep.fitness.toFixed(2) : ""; color: det.rep ? page.fitnessColor(det.rep.fitness) : Theme.gray; font.pixelSize: 26; font.bold: true; font.family: Theme.mono }
                                Text { text: "mGauss RMS"; color: Theme.gray; font.pixelSize: 11 }
                                Item { Layout.fillWidth: true }
                                Text { text: det.rep ? det.rep.qualityText : ""; color: det.rep ? page.fitnessColor(det.rep.fitness) : Theme.gray; font.pixelSize: 12; font.bold: true }
                            }
                            KeyValueRow { visible: det.rep !== null; label: "Offsets"; value: det.rep ? det.rep.ofsX.toFixed(1) + "  " + det.rep.ofsY.toFixed(1) + "  " + det.rep.ofsZ.toFixed(1) : "" }
                            KeyValueRow { visible: det.rep !== null; label: "Diag"; value: det.rep ? det.rep.diagX.toFixed(3) + "  " + det.rep.diagY.toFixed(3) + "  " + det.rep.diagZ.toFixed(3) : "" }
                            KeyValueRow { visible: det.rep !== null; label: "Off-diag"; value: det.rep ? det.rep.offdiagX.toFixed(3) + "  " + det.rep.offdiagY.toFixed(3) + "  " + det.rep.offdiagZ.toFixed(3) : "" }
                            KeyValueRow { visible: det.rep !== null; label: "Scale factor"; value: det.rep ? det.rep.scaleFactor.toFixed(3) : "" }
                            KeyValueRow { visible: det.rep !== null; label: "Orientation"; value: det.rep ? det.rep.oldOrientation + " -> " + det.rep.newOrientation + "  (conf " + det.rep.orientationConfidence.toFixed(1) + ")" : "" }
                            KeyValueRow { visible: det.rep !== null; label: "Autosaved"; value: det.rep ? (det.rep.autosaved ? "yes" : "no (ACCEPT sent)") : "" }
                        }
                    }
                }

                // Save state
                HDivider { visible: mavlink.magCalReports.length > 0 && !mavlink.magCalRunning }
                ColumnLayout {
                    visible: mavlink.magCalReports.length > 0 && !mavlink.magCalRunning
                    Layout.fillWidth: true
                    spacing: 8
                    RowLayout {
                        visible: mavlink.magCalSaved
                        Text { text: "✓"; color: Theme.green; font.pixelSize: 14; font.bold: true }
                        Text { text: "Offsets written to parameters (COMPASS_OFS_*). Reboot the FC to apply."; color: Theme.green; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    }
                    FlatButton {
                        visible: mavlink.magCalSaved
                        Layout.fillWidth: true
                        text: "Reboot flight controller"; icon: "↻"; bgColor: Theme.orange; textColor: Theme.white; implicitHeight: 40
                        onClicked: mavlink.rebootFlightController()
                    }
                    KeyValueRow {
                        visible: !mavlink.magCalSaved && mavlink.magCalAcceptAck !== ""
                        label: "Accept ACK"; value: mavlink.magCalAcceptAck; valueColor: Theme.red
                    }
                    RowLayout {
                        visible: !mavlink.magCalSaved && mavlink.magCalAcceptAck === "" && page.allReportsSuccess
                        BusyIndicator { running: visible; implicitWidth: 20; implicitHeight: 20 }
                        Text { text: "Writing offsets to device..."; color: Theme.orange; font.pixelSize: 12 }
                    }
                    Text {
                        visible: !mavlink.magCalSaved && mavlink.magCalAcceptAck === "" && page.allReportsSuccess
                        text: "Accept & save manually"; color: Theme.cyan; font.pixelSize: 12
                        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: mavlink.acceptCompassCalibration() }
                    }
                    Text {
                        visible: !mavlink.magCalSaved && mavlink.magCalAcceptAck === "" && !page.allReportsSuccess
                        text: "Calibration did not succeed - fix the issue above and start again."
                        color: Theme.red; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }

                RowLayout {
                    spacing: 10
                    Layout.fillWidth: true
                    FlatButton {
                        Layout.fillWidth: true
                        text: "Start"; icon: "▶"; textColor: Theme.white; implicitHeight: 44
                        enabled: page.canCalibrate && !mavlink.magCalRunning
                        onClicked: mavlink.startCompassCalibration(true, false, true)
                    }
                    FlatButton {
                        Layout.fillWidth: true
                        text: "Cancel"; icon: "✖"; bgColor: Theme.red; textColor: Theme.white; implicitHeight: 44
                        enabled: mavlink.magCalRunning
                        onClicked: mavlink.cancelCompassCalibration()
                    }
                }
            }

            // ---------------- Gyro ----------------
            Card {
                title: "Gyroscope"; icon: "⟳"; color: Theme.overlay
                Text {
                    text: "Place the vehicle on a stable surface and do not touch it. Takes a few seconds; the FC replies when finished."
                    color: Theme.gray; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
                SimpleCalStatus { calState: mavlink.gyroCalState }
                FlatButton {
                    Layout.fillWidth: true
                    text: "Calibrate gyro"; icon: "▶"; textColor: Theme.white; implicitHeight: 44
                    enabled: page.canCalibrate && !page.isInProgress(mavlink.gyroCalState)
                    onClicked: mavlink.calibrateGyro()
                }
            }

            // ---------------- Baro ----------------
            Card {
                title: "Barometer"; icon: "☁"; color: Theme.overlay
                Text {
                    text: "Sets current pressure as ground reference (altitude = 0). Vehicle must be stationary, out of wind."
                    color: Theme.gray; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
                SimpleCalStatus { calState: mavlink.baroCalState }
                FlatButton {
                    Layout.fillWidth: true
                    text: "Calibrate barometer"; icon: "▶"; textColor: Theme.white; implicitHeight: 44
                    enabled: page.canCalibrate && !page.isInProgress(mavlink.baroCalState)
                    onClicked: mavlink.calibrateBarometer()
                }
            }

            // ---------------- Messages ----------------
            Card {
                title: "Calibration messages"; icon: "✉"; color: Theme.overlay
                Text { visible: page.calMessages.length === 0; text: "No calibration messages yet."; color: Theme.gray; font.pixelSize: 12 }
                Repeater {
                    model: page.calMessages
                    RowLayout {
                        required property var modelData
                        spacing: 8
                        Layout.fillWidth: true
                        Text { text: modelData.time; color: Theme.gray; font.pixelSize: 11; font.family: Theme.mono; Layout.alignment: Qt.AlignTop }
                        Text {
                            text: modelData.text
                            color: modelData.severity <= 3 ? Theme.red : (modelData.severity === 4 ? Theme.orange : Theme.white)
                            font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }

    component SimpleCalStatus: RowLayout {
        property var calState: ({ state: "idle", text: "" })
        spacing: 8
        Layout.fillWidth: true
        Rectangle { visible: calState.state === "idle"; implicitWidth: 8; implicitHeight: 8; radius: 4; color: Theme.gray }
        BusyIndicator { visible: calState.state === "inProgress"; running: visible; implicitWidth: 18; implicitHeight: 18 }
        Text { visible: calState.state === "success"; text: "✓"; color: Theme.green; font.pixelSize: 14; font.bold: true }
        Text { visible: calState.state === "failed"; text: "✖"; color: Theme.red; font.pixelSize: 14; font.bold: true }
        Text {
            text: {
                switch (calState.state) {
                case "inProgress": return "In progress... " + Math.max(0, Math.round((page.nowMs - calState.startedMs) / 1000)) + " s"
                case "success": return "Done - " + calState.text
                case "failed": return "Failed - " + calState.text
                default: return "Idle"
                }
            }
            color: calState.state === "inProgress" ? Theme.orange : (calState.state === "success" ? Theme.green : (calState.state === "failed" ? Theme.red : Theme.gray))
            font.pixelSize: 12
        }
        Item { Layout.fillWidth: true }
    }
}
