// InfoItem.qml - icon + label + value (port of BatteryInfoItem)
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0

RowLayout {
    id: item
    property string icon: ""
    property string label: ""
    property string value: ""
    property color color: Theme.cyan
    property int valueSize: 17

    Layout.fillWidth: true
    spacing: 6

    Text {
        text: icon
        color: item.color
        font.pixelSize: 14
        font.bold: true
        visible: icon !== ""
    }
    ColumnLayout {
        spacing: 1
        Layout.fillWidth: true
        Text {
            text: label
            color: Theme.gray
            font.pixelSize: 10
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Text {
            text: value
            color: item.color
            font.pixelSize: valueSize
            font.bold: true
            font.family: Theme.mono
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }
}
