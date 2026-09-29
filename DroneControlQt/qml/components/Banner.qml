// Banner.qml - full-width warning strip
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0

Rectangle {
    property string text: ""
    property color bannerColor: Theme.red
    Layout.fillWidth: true
    implicitHeight: label.implicitHeight + 20
    radius: 8
    color: Theme.withAlpha(bannerColor, 0.6)
    Text {
        id: label
        anchors.fill: parent
        anchors.margins: 10
        text: parent.text
        color: Theme.white
        font.pixelSize: 14
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }
}
