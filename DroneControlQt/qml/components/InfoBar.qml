// InfoBar.qml - horizontal gradient bar holding InfoItems separated by dividers
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0

Rectangle {
    id: root
    default property alias content: row.data
    Layout.fillWidth: true
    implicitHeight: row.implicitHeight + 20
    radius: 10
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Theme.card2 }
        GradientStop { position: 1.0; color: Theme.card }
    }
    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        spacing: 10
    }
}
