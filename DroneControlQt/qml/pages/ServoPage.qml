// ServoPage.qml - port of ServoMonitorView.swift (16-channel monitor + DO_SET_SERVO sheet)
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DroneControl 1.0
import "../components"

Item {
    id: page

    PageBackground {}

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: grid.implicitHeight + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        GridLayout {
            id: grid
            x: 16
            y: 16
            width: parent.width - 32
            columns: page.width >= 1100 ? 4 : (page.width >= 700 ? 3 : 2)
            columnSpacing: 12
            rowSpacing: 12

            Repeater {
                model: 16
                Rectangle {
                    required property int index
                    readonly property int channel: index + 1
                    readonly property int value: mavlink.servoValues[index]
                    readonly property color pwmColor: value === 0 ? Theme.gray
                                                    : (value < 1100 ? Theme.red : (value > 1900 ? Theme.orange : Theme.green))
                    Layout.fillWidth: true
                    radius: 12
                    color: Theme.overlay
                    implicitHeight: sc.implicitHeight + 28

                    ColumnLayout {
                        id: sc
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12
                        RowLayout {
                            Text { text: "CH " + channel; color: Theme.white; font.pixelSize: 17; font.bold: true }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "≡"
                                color: Theme.cyan
                                font.pixelSize: 18
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    onClicked: page.openControl(channel, value)
                                }
                            }
                        }
                        ColumnLayout {
                            spacing: 4
                            Layout.alignment: Qt.AlignHCenter
                            Text {
                                text: value
                                color: pwmColor
                                font.pixelSize: 32
                                font.bold: true
                                font.family: Theme.mono
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text { text: "µs"; color: Theme.gray; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 8
                            radius: 4
                            color: Theme.withAlpha(Theme.gray, 0.2)
                            Rectangle {
                                height: parent.height
                                radius: 4
                                width: parent.width * Theme.servoProportion(value)
                                color: pwmColor
                            }
                        }
                    }
                }
            }
        }
    }

    function openControl(channel, current) {
        controlDialog.channel = channel
        controlDialog.pwm = current > 0 ? current : 1500
        controlDialog.open()
    }

    // Servo control sheet
    Dialog {
        id: controlDialog
        property int channel: 1
        property int pwm: 1500
        modal: true
        anchors.centerIn: parent
        width: Math.min(page.width - 32, 420)
        padding: 0
        background: Rectangle {
            radius: 16
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.gradTop }
                GradientStop { position: 1.0; color: Theme.gradBottom }
            }
        }

        contentItem: ColumnLayout {
            spacing: 20
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 16
                Text { text: "Servo Control"; color: Theme.white; font.pixelSize: 16; font.bold: true }
                Item { Layout.fillWidth: true }
                Text {
                    text: "Done"; color: Theme.cyan; font.pixelSize: 14
                    MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: controlDialog.close() }
                }
            }
            Text { text: "Channel " + controlDialog.channel; color: Theme.white; font.pixelSize: 20; font.bold: true; Layout.alignment: Qt.AlignHCenter }
            Text {
                text: controlDialog.pwm + " µs"
                color: Theme.cyan
                font.pixelSize: 44
                font.bold: true
                font.family: Theme.mono
                Layout.alignment: Qt.AlignHCenter
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                spacing: 12
                RowLayout {
                    Text { text: "1000 µs"; color: Theme.gray; font.pixelSize: 11 }
                    Item { Layout.fillWidth: true }
                    Text { text: "2000 µs"; color: Theme.gray; font.pixelSize: 11 }
                }
                Slider {
                    Layout.fillWidth: true
                    from: 1000; to: 2000; stepSize: 10
                    value: controlDialog.pwm
                    onMoved: controlDialog.pwm = Math.round(value)
                }
                RowLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    Repeater {
                        model: [{ t: "Min", v: 1000 }, { t: "Center", v: 1500 }, { t: "Max", v: 2000 }]
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: 8
                            color: Theme.withAlpha(Theme.cyan, 0.3)
                            Text { anchors.centerIn: parent; text: modelData.t; color: Theme.white; font.pixelSize: 12 }
                            MouseArea { anchors.fill: parent; onClicked: controlDialog.pwm = modelData.v }
                        }
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 16
                spacing: 12
                FlatButton {
                    Layout.fillWidth: true
                    text: "Set PWM"; bgColor: Theme.cyan; textColor: Theme.white; fontSize: 16; implicitHeight: 48
                    onClicked: {
                        mavlink.setServo(controlDialog.channel, controlDialog.pwm)
                        controlDialog.close()
                    }
                }
                FlatButton {
                    Layout.fillWidth: true
                    text: "Cancel"; bgColor: Theme.gray; textColor: Theme.white; fontSize: 16; implicitHeight: 48
                    onClicked: controlDialog.close()
                }
            }
        }
    }
}
