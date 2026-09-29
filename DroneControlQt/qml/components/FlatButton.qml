// FlatButton.qml - solid colored button (cyan/red/gray) with optional icon
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0

Rectangle {
    id: root
    property string text: ""
    property string icon: ""
    property color bgColor: Theme.cyan
    property color textColor: Theme.black
    property int fontSize: 14
    property bool enabled: true
    property bool bold: true
    signal clicked()

    radius: 8
    implicitWidth: row.implicitWidth + 28
    implicitHeight: Math.max(34, row.implicitHeight + 16)
    color: enabled ? bgColor : Theme.gray
    opacity: enabled ? 1.0 : 0.6

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Text {
            visible: root.icon !== ""
            text: root.icon
            color: root.textColor
            font.pixelSize: root.fontSize
            font.bold: true
        }
        Text {
            text: root.text
            color: root.textColor
            font.pixelSize: root.fontSize
            font.bold: root.bold
        }
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        onClicked: root.clicked()
    }
}
