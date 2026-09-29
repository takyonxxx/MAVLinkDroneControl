// QuadMotorPanel.qml - the four motor outputs laid out as a Pixhawk Quad X frame
//
//   M3 front left  (CW)    M1 front right (CCW)
//   M2 rear  left  (CCW)   M4 rear  right (CW)
//
// PWM1..4 = M1..M4 (SERVO_OUTPUT_RAW servo1..servo4).
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0

Rectangle {
    id: root
    property bool compact: false
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 20
    radius: 10
    color: Theme.card

    readonly property var motors: [
        { id: 3, position: "Front Left",  rotation: "CW" },
        { id: 1, position: "Front Right", rotation: "CCW" },
        { id: 2, position: "Rear Left",   rotation: "CCW" },
        { id: 4, position: "Rear Right",  rotation: "CW" }
    ]

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            spacing: 6
            Text { text: "✱"; color: Theme.cyan; font.pixelSize: 12 }
            Text { text: "Motor Outputs"; color: Theme.white; font.pixelSize: 13; font.bold: true }
            Item { Layout.fillWidth: true }
            Text { text: "Quad X"; color: Theme.gray; font.pixelSize: 11 }
        }

        // FRONT marker
        Text { text: "FRONT"; color: Theme.gray; font.pixelSize: 9; font.letterSpacing: 2; Layout.alignment: Qt.AlignHCenter }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 8
            rowSpacing: 8
            Repeater {
                model: root.motors
                Rectangle {
                    required property var modelData
                    readonly property int pwm: mavlink.servoValues[modelData.id - 1]
                    readonly property color barColor: Theme.servoColor(pwm, Theme.cyan)
                    Layout.fillWidth: true
                    radius: 8
                    color: Theme.card3
                    implicitHeight: mc.implicitHeight + 16
                    ColumnLayout {
                        id: mc
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4
                        RowLayout {
                            spacing: 6
                            Text { text: "M" + modelData.id; color: Theme.white; font.pixelSize: 15; font.bold: true; font.family: Theme.mono }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: modelData.rotation
                                color: modelData.rotation === "CW" ? Theme.orange : Theme.green
                                font.pixelSize: 11; font.bold: true
                            }
                        }
                        Text { text: modelData.position; color: Theme.gray; font.pixelSize: 10 }
                        RowLayout {
                            spacing: 6
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 14
                                radius: 3
                                color: Theme.barBg
                                clip: true
                                Rectangle {
                                    visible: pwm > 0
                                    height: parent.height
                                    width: Theme.servoProportion(pwm) * parent.width
                                    radius: parent.radius
                                    color: barColor
                                }
                            }
                            Text {
                                text: pwm
                                color: pwm > 0 ? barColor : Theme.gray
                                font.pixelSize: 13; font.weight: Font.DemiBold; font.family: Theme.mono
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 40
                            }
                        }
                    }
                }
            }
        }
    }
}
