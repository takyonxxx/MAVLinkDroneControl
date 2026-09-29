// Card.qml - rounded dark container; children are laid out in a ColumnLayout
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0

Rectangle {
    id: root
    default property alias content: column.data
    property alias spacing: column.spacing
    property int pad: 14
    property string title: ""
    property string icon: ""
    property color titleColor: Theme.white
    property color iconColor: Theme.cyan

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + 2 * pad
    radius: 12
    color: Theme.card

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.pad
        spacing: 10

        RowLayout {
            visible: root.title !== ""
            spacing: 8
            Layout.fillWidth: true
            Text {
                visible: root.icon !== ""
                text: root.icon
                color: root.iconColor
                font.pixelSize: 15
                font.bold: true
            }
            Text {
                text: root.title
                color: root.titleColor
                font.pixelSize: 17
                font.bold: true
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }
    }
}
