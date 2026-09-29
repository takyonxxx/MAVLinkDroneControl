// ServoBar.qml - one PWM channel bar (compact "M1" style or wide "CH1" style)
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0

RowLayout {
    property int channel: 1
    property int pwm: 0
    property bool compact: true
    Layout.fillWidth: true
    spacing: compact ? 8 : 6

    Text {
        text: compact ? "M" + channel : "CH" + channel
        color: compact ? Theme.white : Theme.gray
        font.pixelSize: compact ? 13 : 10
        font.bold: compact
        font.family: Theme.mono
        Layout.preferredWidth: compact ? 30 : 32
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: compact ? 18 : 16
        radius: compact ? 4 : 2
        color: compact ? Theme.card3 : Theme.barBg
        border.width: compact ? 1 : 0
        border.color: Theme.withAlpha(Theme.gray, 0.2)
        clip: true
        Rectangle {
            visible: pwm > 0
            height: parent.height
            width: Theme.servoProportion(pwm) * parent.width
            radius: parent.radius
            color: Theme.servoColor(pwm, compact ? Theme.cyan : Theme.orange)
        }
    }
    Text {
        text: pwm
        color: pwm > 0 ? (compact ? Theme.servoColor(pwm, Theme.cyan) : Theme.white) : Theme.gray
        font.pixelSize: compact ? 13 : 10
        font.weight: Font.DemiBold
        font.family: Theme.mono
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: compact ? 46 : 38
    }
}
