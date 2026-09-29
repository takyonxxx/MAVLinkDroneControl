// AttitudeValue.qml - "Roll  12.3°" stacked readout
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0

ColumnLayout {
    property string label: ""
    property real value: 0
    property string unit: "°"
    spacing: 4
    Text {
        text: label
        color: Theme.gray
        font.pixelSize: 12
        Layout.alignment: Qt.AlignHCenter
    }
    Text {
        text: value.toFixed(1) + unit
        color: Theme.white
        font.pixelSize: 16
        font.bold: true
        font.family: Theme.mono
        Layout.alignment: Qt.AlignHCenter
    }
}
