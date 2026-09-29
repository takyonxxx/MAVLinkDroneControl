// KeyValueRow.qml - "label ......... value" row in monospace
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0

RowLayout {
    property string label: ""
    property string value: ""
    property color valueColor: Theme.white
    property color labelColor: Theme.gray
    property int fontSize: 12
    property bool monoLabel: false
    Layout.fillWidth: true
    Text {
        text: label
        color: labelColor
        font.pixelSize: fontSize
        font.family: monoLabel ? Theme.mono : Qt.application.font.family
    }
    Item { Layout.fillWidth: true }
    Text {
        text: value
        color: valueColor
        font.pixelSize: fontSize
        font.family: Theme.mono
        horizontalAlignment: Text.AlignRight
        wrapMode: Text.NoWrap
    }
}
