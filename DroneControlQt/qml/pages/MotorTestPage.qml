// MotorTestPage.qml - port of MotorTestView.swift
//
// Quad X motor test with MAV_CMD_DO_MOTOR_TEST, one motor at a time, PWM 1000-2000 us.
// Physical wiring (Pixhawk PWM output -> motor):
//   PWM1 -> M1 front right (CCW)   PWM2 -> M2 rear left (CCW)
//   PWM3 -> M3 front left  (CW)    PWM4 -> M4 rear right (CW)
// ArduCopter's param1 is the TEST ORDER (A=1 front right, B=2 rear right,
// C=3 rear left, D=4 front left - clockwise), not the output number, hence the mapping.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DroneControl 1.0
import "../components"

Item {
    id: page

    readonly property var motors: [
        { id: 1, position: "Front Right", pwmChannel: 1, testSeq: 1, rotation: "CCW" },
        { id: 2, position: "Rear Left",   pwmChannel: 2, testSeq: 3, rotation: "CCW" },
        { id: 3, position: "Front Left",  pwmChannel: 3, testSeq: 4, rotation: "CW" },
        { id: 4, position: "Rear Right",  pwmChannel: 4, testSeq: 2, rotation: "CW" }
    ]
    function motor(id) { return motors[id - 1] }

    property var pwmValues: ({ 1: 1000, 2: 1000, 3: 1000, 4: 1000 })
    property int runningMotor: 0
    readonly property real keepaliveInterval: 1.0
    readonly property real keepaliveTimeout: 3.0
    readonly property bool canTest: mavlink.connected && !mavlink.armedByPilot

    function setPwm(id, v) {
        var copy = Object.assign({}, pwmValues)
        copy[id] = v
        pwmValues = copy
        if (runningMotor === id) sendTest(id)
    }

    function start(id) {
        if (!canTest) return
        if (runningMotor !== 0 && runningMotor !== id)
            mavlink.stopMotorTest(motor(runningMotor).testSeq)
        runningMotor = id
        sendTest(id)
        keepalive.restart()
    }

    function sendTest(id) {
        var pwm = Math.max(1000, Math.min(2000, pwmValues[id]))
        mavlink.motorTest(motor(id).testSeq, pwm, keepaliveTimeout)
    }

    function stopAll(sendCommand) {
        if (sendCommand === undefined) sendCommand = true
        keepalive.stop()
        var seq = runningMotor !== 0 ? motor(runningMotor).testSeq : 1
        runningMotor = 0
        if (sendCommand && mavlink.connected)
            mavlink.stopMotorTest(seq)
    }

    Timer {
        id: keepalive
        interval: keepaliveInterval * 1000
        repeat: true
        onTriggered: if (runningMotor !== 0) sendTest(runningMotor)
    }

    onVisibleChanged: if (!visible) stopAll()
    Connections {
        target: mavlink
        function onConnectedChanged() { if (!mavlink.connected) stopAll(false) }
    }

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
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 16

            // Safety card
            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: Theme.overlay
                implicitHeight: safety.implicitHeight + 28
                ColumnLayout {
                    id: safety
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10
                    RowLayout {
                        Text { text: "⚠"; color: Theme.orange; font.pixelSize: 16 }
                        Text { text: "Motor Test"; color: Theme.white; font.pixelSize: 17; font.bold: true }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            visible: runningMotor !== 0
                            radius: 6
                            color: Theme.orange
                            implicitWidth: runText.implicitWidth + 16
                            implicitHeight: runText.implicitHeight + 8
                            Text { id: runText; anchors.centerIn: parent; text: "RUNNING M" + runningMotor; color: Theme.black; font.pixelSize: 12; font.bold: true }
                        }
                    }
                    FlatButton {
                        Layout.fillWidth: true
                        text: "STOP ALL MOTORS"
                        icon: "✋"
                        bgColor: Theme.red
                        textColor: Theme.white
                        fontSize: 16
                        implicitHeight: 48
                        enabled: mavlink.connected
                        onClicked: stopAll()
                    }
                    RowLayout {
                        spacing: 6
                        Text { text: "Last ACK:"; color: Theme.gray; font.pixelSize: 12 }
                        Text {
                            text: mavlink.motorTestAckAccepted < 0 ? "--"
                                : ((mavlink.motorTestAckAccepted === 1 ? "✓ " : "✗ ") + mavlink.motorTestAckText)
                            color: mavlink.motorTestAckAccepted < 0 ? Theme.gray : (mavlink.motorTestAckAccepted === 1 ? Theme.green : Theme.red)
                            font.pixelSize: 12
                        }
                        Item { Layout.fillWidth: true }
                        Text { text: "keepalive " + keepaliveInterval + "s / timeout " + keepaliveTimeout + "s"; color: Theme.gray; font.pixelSize: 10 }
                    }
                }
            }

            Banner { visible: !mavlink.connected; text: "Not connected"; bannerColor: Theme.red }
            Banner { visible: mavlink.connected && mavlink.armedByPilot; text: "Vehicle is ARMED - disarm before motor test"; bannerColor: Theme.red }
            Banner { visible: mavlink.connected && !mavlink.armedByPilot && mavlink.motorTestActive; text: "Motor test active - FC reports ARMED during test, this is normal"; bannerColor: Theme.orange }

            // Quad X layout: top row front, bottom row rear
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 12
                rowSpacing: 12
                MotorCard { motorId: 3 }   // front left
                MotorCard { motorId: 1 }   // front right
                MotorCard { motorId: 2 }   // rear left
                MotorCard { motorId: 4 }   // rear right
            }

            // Wiring card
            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: Theme.overlay
                implicitHeight: wiring.implicitHeight + 28
                ColumnLayout {
                    id: wiring
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 6
                    Text { text: "Quad X wiring"; color: Theme.white; font.pixelSize: 12; font.bold: true }
                    Repeater {
                        model: motors
                        RowLayout {
                            spacing: 0
                            Text { text: "PWM" + modelData.pwmChannel; Layout.preferredWidth: 48; color: Theme.gray; font.pixelSize: 11; font.family: Theme.mono }
                            Text { text: "M" + modelData.id; Layout.preferredWidth: 32; color: Theme.gray; font.pixelSize: 11; font.family: Theme.mono }
                            Text { text: modelData.position; Layout.preferredWidth: 96; color: Theme.gray; font.pixelSize: 11; font.family: Theme.mono }
                            Text { text: modelData.rotation; Layout.preferredWidth: 38; color: Theme.gray; font.pixelSize: 11; font.family: Theme.mono }
                            Text { text: "test seq " + modelData.testSeq; color: Theme.gray; font.pixelSize: 11; font.family: Theme.mono }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }
        }
    }

    // ---------------- Motor card ----------------
    component MotorCard: Rectangle {
        id: card
        property int motorId: 1
        readonly property var m: page.motor(motorId)
        readonly property bool isRunning: page.runningMotor === motorId
        readonly property int feedback: mavlink.servoValues[m.pwmChannel - 1]
        readonly property int target: page.pwmValues[motorId]

        Layout.fillWidth: true
        radius: 12
        color: Theme.withAlpha(Theme.black, isRunning ? 0.5 : 0.3)
        border.width: 2
        border.color: isRunning ? Theme.orange : "transparent"
        implicitHeight: mc.implicitHeight + 28

        ColumnLayout {
            id: mc
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            RowLayout {
                ColumnLayout {
                    spacing: 2
                    Text { text: "M" + card.motorId; color: Theme.white; font.pixelSize: 17; font.bold: true }
                    Text { text: card.m.position; color: Theme.gray; font.pixelSize: 11 }
                }
                Item { Layout.fillWidth: true }
                ColumnLayout {
                    spacing: 2
                    Text { text: "PWM" + card.m.pwmChannel; color: Theme.cyan; font.pixelSize: 11; Layout.alignment: Qt.AlignRight }
                    Text { text: card.m.rotation; color: card.m.rotation === "CW" ? Theme.orange : Theme.green; font.pixelSize: 11; font.bold: true; Layout.alignment: Qt.AlignRight }
                }
            }

            Text {
                text: card.target
                color: card.isRunning ? Theme.orange : Theme.white
                font.pixelSize: 28
                font.bold: true
                font.family: Theme.mono
                Layout.alignment: Qt.AlignHCenter
            }

            Slider {
                Layout.fillWidth: true
                from: 1000; to: 2000; stepSize: 10
                value: card.target
                enabled: page.canTest
                onMoved: page.setPwm(card.motorId, Math.round(value))
            }

            RowLayout {
                spacing: 6
                Layout.fillWidth: true
                Repeater {
                    model: [1000, 1100, 1300, 1500]
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: 6
                        color: Theme.withAlpha(Theme.cyan, 0.25)
                        opacity: page.canTest ? 1 : 0.5
                        Text { anchors.centerIn: parent; text: modelData; color: Theme.white; font.pixelSize: 11 }
                        MouseArea { anchors.fill: parent; enabled: page.canTest; onClicked: page.setPwm(card.motorId, modelData) }
                    }
                }
            }

            RowLayout {
                spacing: 4
                Text { text: "Output:"; color: Theme.gray; font.pixelSize: 11 }
                Text {
                    text: card.feedback > 0 ? card.feedback + " us" : "--"
                    color: card.feedback > 1050 ? Theme.orange : Theme.gray
                    font.pixelSize: 12
                    font.family: Theme.mono
                }
                Item { Layout.fillWidth: true }
            }

            FlatButton {
                Layout.fillWidth: true
                text: card.isRunning ? "Stop" : "Run"
                icon: card.isRunning ? "■" : "▶"
                bgColor: card.isRunning ? Theme.red : Theme.cyan
                textColor: Theme.white
                enabled: page.canTest
                implicitHeight: 40
                onClicked: card.isRunning ? page.stopAll() : page.start(card.motorId)
            }
        }
    }
}
