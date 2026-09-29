// PageBackground.qml - vertical gradient used by most secondary pages
import QtQuick
import DroneControl 1.0

Rectangle {
    anchors.fill: parent
    gradient: Gradient {
        GradientStop { position: 0.0; color: Theme.gradTop }
        GradientStop { position: 1.0; color: Theme.gradBottom }
    }
}
