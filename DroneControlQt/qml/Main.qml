// Main.qml - DroneControlQt
// Port of ContentView.swift: tabbed shell. Bottom scrollable tab bar on phones,
// top tab bar on desktop.
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import DroneControl 1.0
import "pages"

ApplicationWindow {
    id: window
    visible: true
    title: "Drone Control"
    width: 1200
    height: 800
    minimumWidth: 360
    minimumHeight: 480
    color: Theme.bg

    Component.onCompleted: {
        if (screenshotSize.width > 0) { width = screenshotSize.width; height = screenshotSize.height }
    }

    Material.theme: Material.Dark
    Material.accent: Theme.cyan
    Material.primary: Theme.bgHeader
    Material.background: Theme.bg
    Material.foreground: Theme.white

    readonly property bool compact: width < 700
    property int currentTab: 0

    readonly property var tabs: [
        { title: "Dashboard", icon: "◎" },
        { title: "Control",   icon: "▣" },
        { title: "Motors",    icon: "✱" },
        { title: "Modes",     icon: "✈" },
        { title: "Map",       icon: "▦" },
        { title: "Servos",    icon: "≡" },
        { title: "Params",    icon: "☷" },
        { title: "Messages",  icon: "✉" },
        { title: "Calibrate", icon: "⌖" },
        { title: "Settings",  icon: "⚙" },
        { title: "GPS",       icon: "●" }
    ]

    // ---------------- Tab bar ----------------
    component TabStrip: Rectangle {
        id: strip
        color: Theme.bgHeader
        implicitHeight: compact ? 62 : 52
        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.withAlpha(Theme.gray, 0.25); visible: compact }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.withAlpha(Theme.gray, 0.25); visible: !compact }

        Flickable {
            id: tabFlick
            anchors.fill: parent
            contentWidth: Math.max(width, tabRow.implicitWidth)
            contentHeight: height
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: tabRow
                height: parent.height
                spacing: 0
                Repeater {
                    model: window.tabs
                    Item {
                        id: tab
                        required property int index
                        required property var modelData
                        readonly property bool selected: window.currentTab === index
                        width: compact ? Math.max(76, tabFlick.width / 5) : Math.max(96, tabFlick.width / window.tabs.length)
                        height: tabRow.height
                        Column {
                            anchors.centerIn: parent
                            spacing: 3
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tab.modelData.icon
                                color: tab.selected ? Theme.cyan : Theme.gray
                                font.pixelSize: compact ? 20 : 16
                                font.bold: true
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tab.modelData.title
                                color: tab.selected ? Theme.cyan : Theme.gray
                                font.pixelSize: compact ? 11 : 12
                                font.weight: tab.selected ? Font.DemiBold : Font.Normal
                            }
                        }
                        Rectangle {
                            visible: !compact && tab.selected
                            anchors.bottom: parent.bottom
                            width: parent.width; height: 2
                            color: Theme.cyan
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                window.currentTab = tab.index
                                // keep the selected tab visible in the strip
                                var left = tab.x - tabFlick.contentX
                                if (left < 0) tabFlick.contentX = Math.max(0, tab.x - 8)
                                else if (left + tab.width > tabFlick.width)
                                    tabFlick.contentX = Math.min(tabFlick.contentWidth - tabFlick.width, tab.x + tab.width - tabFlick.width + 8)
                            }
                        }
                    }
                }
            }
        }
    }

    header: TabStrip { visible: !compact }
    footer: TabStrip { visible: compact }

    // Debug aid (see main.cpp): walk through every tab and save a screenshot of each
    Timer {
        id: shotTimer
        property int shot: 0
        interval: screenshotDelayMs
        repeat: true
        running: screenshotDir !== ""
        onTriggered: {
            var idx = shot
            pages.grabToImage(function(result) {
                result.saveToFile(screenshotDir + "/tab" + idx + "_" + window.tabs[idx].title + ".png")
                if (idx + 1 >= window.tabs.length) { shotTimer.stop(); Qt.quit(); return }
                window.currentTab = idx + 1
                // exercise a few actions so the screenshots show populated pages
                if (idx + 1 === 4) { mavlink.addWaypoint(mavlink.latitude + 0.0006, mavlink.longitude + 0.0004, 15); mavlink.addWaypoint(mavlink.latitude + 0.0010, mavlink.longitude - 0.0003, 20); mavlink.uploadMission(15, true) }
                if (idx + 1 === 6) { mavlink.requestAllParameters(); mavlink.parameters.toggleCategory("Radio (RC)") }
                if (idx + 1 === 8) { mavlink.startCompassCalibration(true, false, true); mavlink.calibrateGyro() }
            })
            shot++
        }
    }

    // ---------------- Pages ----------------
    StackLayout {
        id: pages
        anchors.fill: parent
        currentIndex: window.currentTab

        DashboardPage {}
        ControlPage { active: window.currentTab === 1 }
        MotorTestPage {}
        FlightModePage {}
        MapPage {}
        ServoPage {}
        ParametersPage {}
        MessagesPage {}
        CalibrationPage {}
        SettingsPage {}
        GpsPage {}
    }
}
