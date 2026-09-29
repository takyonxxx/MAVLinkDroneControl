// MessagesPage.qml - port of MessagesView.swift (STATUSTEXT log + EKF health card)
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DroneControl 1.0
import "../components"

Item {
    id: page

    Rectangle { anchors.fill: parent; color: Theme.bg }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 8
        spacing: 10

        StatusBar {}

        // EKF health card
        InfoBar {
            id: ekfCard
            readonly property int bitPosHorizAbs: 1 << 4
            readonly property int bitConstPos: 1 << 7
            readonly property bool posOk: (mavlink.ekfFlags & bitPosHorizAbs) !== 0
            readonly property bool constPos: (mavlink.ekfFlags & bitConstPos) !== 0
            readonly property color stateColor: !mavlink.ekfReportReceived ? Theme.gray : (posOk ? Theme.green : (constPos ? Theme.yellow : Theme.red))
            readonly property string stateText: !mavlink.ekfReportReceived ? "EKF: waiting for data"
                : (posOk ? "EKF: position OK — Loiter ready"
                   : (constPos ? "EKF: no position source (waiting for GPS fix)" : "EKF: degraded (flags: " + mavlink.ekfFlags + ")"))
            function varColor(v) { return v < 0.5 ? Theme.green : (v < 1.0 ? Theme.yellow : Theme.red) }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                RowLayout {
                    spacing: 8
                    Rectangle { implicitWidth: 10; implicitHeight: 10; radius: 5; color: ekfCard.stateColor }
                    Text { text: ekfCard.stateText; color: Theme.white; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                }
                RowLayout {
                    visible: mavlink.ekfReportReceived
                    spacing: 14
                    Repeater {
                        model: [
                            { n: "Compass", v: mavlink.ekfCompassVariance },
                            { n: "Position", v: mavlink.ekfPosHorizVariance },
                            { n: "Velocity", v: mavlink.ekfVelocityVariance }
                        ]
                        RowLayout {
                            spacing: 4
                            Text { text: modelData.n; color: Theme.gray; font.pixelSize: 11 }
                            Text { text: modelData.v.toFixed(2); color: ekfCard.varColor(modelData.v); font.pixelSize: 11; font.weight: Font.DemiBold; font.family: Theme.mono }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text { visible: page.width >= 480; text: "< 0.5 good"; color: Theme.gray; font.pixelSize: 10 }
                }
            }
        }

        // Filter bar
        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            Repeater {
                model: [{ t: "All", s: 7 }, { t: "Warnings+", s: 4 }, { t: "Errors+", s: 3 }]
                Rectangle {
                    readonly property bool sel: mavlink.messages.maxSeverity === modelData.s
                    radius: 8
                    color: sel ? Theme.cyan : Theme.card2
                    implicitWidth: ft.implicitWidth + 24
                    implicitHeight: ft.implicitHeight + 12
                    Text { id: ft; anchors.centerIn: parent; text: modelData.t; color: sel ? Theme.black : Theme.gray; font.pixelSize: 12; font.weight: Font.DemiBold }
                    MouseArea { anchors.fill: parent; onClicked: mavlink.messages.maxSeverity = modelData.s }
                }
            }
            Item { Layout.fillWidth: true }
            Text { text: mavlink.messages.count; color: Theme.gray; font.pixelSize: 12; font.family: Theme.mono }
            Text {
                text: "✖"; color: Theme.gray; font.pixelSize: 13
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: mavlink.messages.clear() }
            }
        }

        // Empty state
        ColumnLayout {
            visible: mavlink.messages.count === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignHCenter
            Item { Layout.fillHeight: true }
            Text { text: "✉"; color: Theme.gray; font.pixelSize: 40; Layout.alignment: Qt.AlignHCenter }
            Text {
                text: mavlink.connected ? "No messages yet.\nPreArm and status messages will appear here." : "Connect to the vehicle first."
                color: Theme.gray; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; Layout.alignment: Qt.AlignHCenter
            }
            Item { Layout.fillHeight: true }
        }

        // Message list (auto-scrolls to the newest entry)
        ListView {
            id: list
            visible: mavlink.messages.count > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: 12
            clip: true
            spacing: 4
            model: mavlink.messages
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            onCountChanged: Qt.callLater(function() { list.positionViewAtEnd() })

            delegate: Rectangle {
                id: msgRow
                required property string text
                required property int severity
                required property string severityName
                required property string time
                readonly property color msgColor: severity <= 3 ? Theme.red : (severity === 4 ? Theme.orange : (severity === 5 ? Theme.yellow : (severity === 6 ? Theme.white : Theme.gray)))
                readonly property string icon: severity <= 3 ? "✖" : (severity === 4 ? "⚠" : "ℹ")
                width: list.width
                radius: 8
                color: Theme.card
                implicitHeight: mr.implicitHeight + 12
                RowLayout {
                    id: mr
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.topMargin: 6
                    anchors.bottomMargin: 6
                    spacing: 8
                    Text { text: icon; color: msgColor; font.pixelSize: 12; Layout.alignment: Qt.AlignTop }
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        Text { text: msgRow.text; color: msgColor; font.pixelSize: 13; font.family: Theme.mono; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        RowLayout {
                            spacing: 6
                            Text { text: time; color: Theme.gray; font.pixelSize: 10; font.family: Theme.mono }
                            Text { text: severityName; color: Theme.gray; font.pixelSize: 10; font.family: Theme.mono }
                        }
                    }
                }
            }
        }
    }
}
