// JoystickControl.qml - touch/mouse virtual stick (port of JoystickControl in JoystickView.swift)
// posX / posY are normalized -1..1 with Y pointing up.
import QtQuick
import DroneControl 1.0

Item {
    id: root
    property real size: 140
    property real posX: 0
    property real posY: 0
    property bool returnToCenterX: true
    property bool returnToCenterY: true
    property bool dragging: false

    implicitWidth: size
    implicitHeight: size

    function updatePosition(px, py) {
        var center = size / 2
        var dx = (px - center) / (size * 0.35)
        var dy = -(py - center) / (size * 0.35)
        var d = Math.sqrt(dx * dx + dy * dy)
        if (d <= 1.0) {
            posX = dx
            posY = dy
        } else {
            var a = Math.atan2(dy, dx)
            posX = Math.cos(a)
            posY = Math.sin(a)
        }
    }

    function release() {
        dragging = false
        if (returnToCenterX) posX = 0
        if (returnToCenterY) posY = 0
    }

    // Base
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.card }
            GradientStop { position: 1.0; color: Theme.card3 }
        }
    }
    // Center ring
    Rectangle {
        anchors.centerIn: parent
        width: size * 0.3
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Theme.withAlpha(Theme.gray, 0.3)
    }
    // Crosshair
    Rectangle { x: size / 2 - 0.5; y: 0; width: 1; height: size; color: Theme.withAlpha(Theme.gray, 0.2) }
    Rectangle { x: 0; y: size / 2 - 0.5; width: size; height: 1; color: Theme.withAlpha(Theme.gray, 0.2) }

    // Stick knob
    Rectangle {
        id: knob
        width: size * 0.3
        height: width
        radius: width / 2
        x: size / 2 - width / 2 + root.posX * size * 0.35
        y: size / 2 - height / 2 - root.posY * size * 0.35
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#4D80E6" }
            GradientStop { position: 1.0; color: "#3366CC" }
        }
        border.color: Theme.withAlpha(Theme.black, 0.3)
        border.width: 1
        Behavior on x { enabled: !root.dragging; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        Behavior on y { enabled: !root.dragging; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
    }

    // One touch point per stick so both sticks work simultaneously; mouse works too.
    MultiPointTouchArea {
        anchors.fill: parent
        minimumTouchPoints: 1
        maximumTouchPoints: 1
        mouseEnabled: true
        touchPoints: [ TouchPoint { id: tp } ]
        onPressed: { root.dragging = true; root.updatePosition(tp.x, tp.y) }
        onUpdated: { if (root.dragging) root.updatePosition(tp.x, tp.y) }
        onReleased: root.release()
        onCanceled: root.release()
    }
}
