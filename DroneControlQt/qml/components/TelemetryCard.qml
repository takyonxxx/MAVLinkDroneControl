// TelemetryCard.qml - icon + title + value (+ subtitle) card (Mini/Telemetry card)
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0

Rectangle {
    property string icon: ""
    property string title: ""
    property string value: ""
    property string subtitle: ""
    property color accent: Theme.cyan
    Layout.fillWidth: true
    implicitHeight: row.implicitHeight + 20
    radius: 10
    color: Theme.card

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        spacing: 10
        Text {
            text: icon
            color: accent
            font.pixelSize: 18
            font.bold: true
            Layout.preferredWidth: 26
            horizontalAlignment: Text.AlignHCenter
        }
        ColumnLayout {
            spacing: 2
            Layout.fillWidth: true
            Text { text: title; color: Theme.gray; font.pixelSize: 11 }
            Text {
                text: value
                color: Theme.white
                font.pixelSize: 15
                font.bold: true
                font.family: Theme.mono
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                visible: subtitle !== ""
                text: subtitle
                color: Theme.gray
                font.pixelSize: 10
                font.family: Theme.mono
            }
        }
    }
}
