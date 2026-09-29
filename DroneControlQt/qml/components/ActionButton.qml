// ActionButton.qml - gradient pill button used for Reset / ARM / DISARM etc.
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0

Rectangle {
    id: root
    property string text: ""
    property string icon: ""
    property color color1: Theme.buttonBlue1
    property color color2: Theme.buttonBlue2
    property color textColor: Theme.white
    property int fontSize: 16
    property bool enabled: true
    signal clicked()

    radius: 12
    implicitWidth: row.implicitWidth + 48
    implicitHeight: row.implicitHeight + 24
    opacity: enabled ? 1.0 : 0.5
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: root.color1 }
        GradientStop { position: 1.0; color: root.color2 }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8
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
            font.weight: Font.DemiBold
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        onClicked: root.clicked()
        onPressed: root.scale = 0.96
        onReleased: root.scale = 1.0
        onCanceled: root.scale = 1.0
    }
    Behavior on scale { NumberAnimation { duration: 80 } }
}
