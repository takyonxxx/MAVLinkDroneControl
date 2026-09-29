// GPSInfoCard.qml - fix / sats / lat-lon (compact dashboard) or stacked (wide)
import QtQuick
import QtQuick.Layouts
import DroneControl 1.0

Rectangle {
    property bool wide: false
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 20
    radius: 10
    color: Theme.card

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        RowLayout {
            spacing: 10
            Layout.fillWidth: true
            Text {
                text: "●"
                color: Theme.gpsColor(mavlink.gpsFixType)
                font.pixelSize: wide ? 20 : 16
                Layout.preferredWidth: wide ? 30 : 18
                horizontalAlignment: Text.AlignHCenter
            }
            ColumnLayout {
                spacing: 2
                Text { text: "GPS"; color: wide ? Theme.gray : Theme.cyan; font.pixelSize: wide ? 11 : 12 }
                Text {
                    text: Theme.gpsFixName(mavlink.gpsFixType)
                    color: Theme.white
                    font.pixelSize: wide ? 16 : 14
                    font.bold: true
                    font.family: Theme.mono
                }
                Text {
                    visible: wide
                    text: mavlink.gpsSatellites + " sats"
                    color: Theme.gray
                    font.pixelSize: 10
                    font.family: Theme.mono
                }
            }
            Item { Layout.fillWidth: true }
            RowLayout {
                visible: !wide
                spacing: 4
                Text { text: "⩡"; color: Theme.cyan; font.pixelSize: 12 }
                Text {
                    text: mavlink.gpsSatellites
                    color: Theme.cyan
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    font.family: Theme.mono
                }
            }
        }

        HDivider {}

        // Compact: single row; wide: two rows
        RowLayout {
            visible: !wide
            spacing: 2
            Layout.fillWidth: true
            Text { text: "LAT:"; color: Theme.gray; font.pixelSize: 12 }
            Text { text: mavlink.latitude.toFixed(5) + "°"; color: Theme.white; font.pixelSize: 14; font.family: Theme.mono; font.weight: Font.Medium }
            Text { text: "•"; color: Theme.withAlpha(Theme.gray, 0.5); font.pixelSize: 12; leftPadding: 6; rightPadding: 6 }
            Text { text: "LON:"; color: Theme.gray; font.pixelSize: 12 }
            Text { text: mavlink.longitude.toFixed(5) + "°"; color: Theme.white; font.pixelSize: 14; font.family: Theme.mono; font.weight: Font.Medium }
            Item { Layout.fillWidth: true }
        }
        ColumnLayout {
            visible: wide
            spacing: 4
            RowLayout {
                spacing: 4
                Text { text: "LAT:"; color: Theme.gray; font.pixelSize: 9 }
                Text { text: mavlink.latitude.toFixed(6) + "°"; color: Theme.white; font.pixelSize: 10; font.family: Theme.mono }
            }
            RowLayout {
                spacing: 4
                Text { text: "LON:"; color: Theme.gray; font.pixelSize: 9 }
                Text { text: mavlink.longitude.toFixed(6) + "°"; color: Theme.white; font.pixelSize: 10; font.family: Theme.mono }
            }
        }
    }
}
