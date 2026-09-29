// ParametersPage.qml - port of ParametersView.swift
// Reads all parameters, groups them by category, edits and writes them back,
// and can restore the known-good default snapshot.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DroneControl 1.0
import "../components"

Item {
    id: page
    readonly property string progressText: {
        var got = mavlink.parameters.count
        var total = mavlink.paramTotalCount
        if (total > 0) return got + " / " + total
        return got > 0 ? String(got) : ""
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 8
        spacing: 10

        StatusBar {}

        // Header: read / restore / progress
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            RowLayout {
                spacing: 12
                Layout.fillWidth: true
                FlatButton {
                    Layout.fillWidth: page.width < 560
                    text: "Read from Vehicle"; icon: "\u2193"; fontSize: 13
                    enabled: mavlink.connected && !mavlink.restoreInProgress
                    onClicked: mavlink.requestAllParameters()
                }
                FlatButton {
                    Layout.fillWidth: page.width < 560
                    text: "Restore Defaults"; icon: "\u21BA"; fontSize: 13
                    bgColor: Theme.orange
                    enabled: mavlink.connected && !mavlink.restoreInProgress
                    onClicked: restoreDialog.open()
                }
                Item { visible: page.width >= 560; Layout.fillWidth: true }
                BusyIndicator { visible: page.width >= 560 && mavlink.paramDownloading; running: visible; implicitWidth: 24; implicitHeight: 24 }
                Text {
                    visible: page.width >= 560
                    text: page.progressText
                    color: Theme.gray
                    font.pixelSize: 12
                    font.family: Theme.mono
                }
            }
            RowLayout {
                visible: page.width < 560
                Layout.fillWidth: true
                BusyIndicator { visible: mavlink.paramDownloading; running: visible; implicitWidth: 20; implicitHeight: 20 }
                Item { Layout.fillWidth: true }
                Text { text: page.progressText; color: Theme.gray; font.pixelSize: 12; font.family: Theme.mono }
            }
            RowLayout {
                visible: mavlink.restoreInProgress
                spacing: 10
                Layout.fillWidth: true
                ProgressBar {
                    Layout.fillWidth: true
                    from: 0; to: Math.max(mavlink.restoreTotal, 1)
                    value: mavlink.restoreProgress
                }
                Text { text: mavlink.restoreProgress + "/" + mavlink.restoreTotal; color: Theme.orange; font.pixelSize: 11; font.family: Theme.mono }
                Text {
                    text: "Cancel"; color: Theme.red; font.pixelSize: 11; font.bold: true
                    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: mavlink.cancelRestore() }
                }
            }
        }

        // Search
        Rectangle {
            Layout.fillWidth: true
            radius: 8
            color: Theme.card2
            implicitHeight: 40
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8
                Text { text: "⌕"; color: Theme.gray; font.pixelSize: 16 }
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: "Search parameters (e.g. LOIT, MOT_PWM)"
                    color: Theme.white
                    background: null
                    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhUppercaseOnly
                    onTextChanged: mavlink.parameters.filter = text
                }
                Text {
                    visible: searchField.text !== ""
                    text: "✖"; color: Theme.gray; font.pixelSize: 14
                    MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: searchField.text = "" }
                }
            }
        }

        // Empty state
        ColumnLayout {
            visible: mavlink.parameters.count === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 12
            Item { Layout.fillHeight: true }
            Text { text: "☷"; color: Theme.gray; font.pixelSize: 40; Layout.alignment: Qt.AlignHCenter }
            Text {
                text: mavlink.connected ? "No parameters loaded yet.\nTap \"Read from Vehicle\" to start." : "Connect to the vehicle first."
                color: Theme.gray
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }
            Item { Layout.fillHeight: true }
        }

        // Category / parameter list
        ListView {
            id: list
            visible: mavlink.parameters.count > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: 12
            clip: true
            model: mavlink.parameters
            spacing: 0
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            delegate: Item {
                id: row
                required property int index
                required property string name
                required property string valueText
                required property real value
                required property string category
                required property string icon
                required property bool isHeader
                required property bool expanded
                required property int categoryCount
                required property bool recentlyWritten

                width: list.width
                height: isHeader ? 48 : 38

                // Category header
                Rectangle {
                    visible: row.isHeader
                    anchors.fill: parent
                    anchors.topMargin: 8
                    radius: 10
                    color: Theme.card
                    // square off the bottom corners while expanded so rows attach visually
                    Rectangle { visible: row.expanded; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 10; color: Theme.card }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8
                        Rectangle {
                            implicitWidth: 22; implicitHeight: 22; radius: 5
                            color: Theme.withAlpha(Theme.cyan, 0.2)
                            Text { anchors.centerIn: parent; text: row.icon; color: Theme.cyan; font.pixelSize: 12; font.bold: true }
                        }
                        Text { text: row.name; color: Theme.white; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: row.categoryCount; color: Theme.gray; font.pixelSize: 12; font.family: Theme.mono }
                        Text { text: row.expanded ? "▾" : "▸"; color: Theme.gray; font.pixelSize: 13 }
                    }
                    MouseArea { anchors.fill: parent; onClicked: mavlink.parameters.toggleCategory(row.category) }
                }

                // Parameter row
                Rectangle {
                    visible: !row.isHeader
                    anchors.fill: parent
                    color: Theme.card
                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: Theme.withAlpha(Theme.gray, 0.1) }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8
                        Text { text: row.name; color: Theme.white; font.pixelSize: 13; font.family: Theme.mono; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { visible: row.recentlyWritten; text: "✓"; color: Theme.green; font.pixelSize: 13; font.bold: true }
                        Text { text: row.valueText; color: Theme.cyan; font.pixelSize: 13; font.weight: Font.Medium; font.family: Theme.mono }
                        Text { text: "✎"; color: Theme.gray; font.pixelSize: 11 }
                    }
                    MouseArea { anchors.fill: parent; onClicked: page.edit(row.name, row.value) }
                }
            }
        }
    }

    function edit(name, value) {
        editDialog.paramName = name
        editDialog.currentValue = value
        editField.text = mavlink.parameters.formatValue(value)
        editDialog.open()
        editField.forceActiveFocus()
        editField.selectAll()
    }

    // Edit sheet
    Dialog {
        id: editDialog
        property string paramName: ""
        property real currentValue: 0
        readonly property var parsedValue: {
            var t = editField.text.replace(",", ".").trim()
            if (t === "") return undefined
            var v = Number(t)
            return isNaN(v) ? undefined : v
        }
        modal: true
        anchors.centerIn: parent
        width: Math.min(page.width - 32, 420)
        padding: 24
        background: Rectangle { radius: 16; color: Theme.sheetBg }

        contentItem: ColumnLayout {
            spacing: 18
            Text { text: editDialog.paramName; color: Theme.white; font.pixelSize: 18; font.bold: true; font.family: Theme.mono; Layout.alignment: Qt.AlignHCenter }
            RowLayout {
                spacing: 6
                Layout.alignment: Qt.AlignHCenter
                Text { text: "Current value:"; color: Theme.gray; font.pixelSize: 14 }
                Text { text: mavlink.parameters.formatValue(editDialog.currentValue); color: Theme.cyan; font.pixelSize: 14; font.family: Theme.mono }
            }
            TextField {
                id: editField
                Layout.fillWidth: true
                placeholderText: "New value"
                color: Theme.white
                font.pixelSize: 22
                font.weight: Font.DemiBold
                font.family: Theme.mono
                horizontalAlignment: Text.AlignHCenter
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                background: Rectangle { radius: 10; color: Theme.card2 }
                onAccepted: if (editDialog.parsedValue !== undefined) editDialog.write()
            }
            Text { visible: editDialog.parsedValue === undefined; text: "Invalid number"; color: Theme.red; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
            Text {
                text: "The value is written to the vehicle immediately.\nSome parameters take effect after reboot."
                color: Theme.orange
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }
            RowLayout {
                spacing: 16
                Layout.fillWidth: true
                FlatButton {
                    Layout.fillWidth: true
                    text: "Cancel"; bgColor: Theme.withAlpha(Theme.gray, 0.3); textColor: Theme.white; bold: false; implicitHeight: 44
                    onClicked: editDialog.close()
                }
                FlatButton {
                    Layout.fillWidth: true
                    text: "Write to Vehicle"; bgColor: Theme.cyan; textColor: Theme.black; bold: false; implicitHeight: 44
                    enabled: editDialog.parsedValue !== undefined
                    onClicked: editDialog.write()
                }
            }
        }

        function write() {
            mavlink.setParameter(paramName, parsedValue)
            mavlink.parameters.markWritten(paramName)
            close()
        }
    }

    // Restore confirmation
    Dialog {
        id: restoreDialog
        modal: true
        anchors.centerIn: parent
        width: Math.min(page.width - 32, 420)
        padding: 24
        background: Rectangle { radius: 16; color: Theme.sheetBg }
        contentItem: ColumnLayout {
            spacing: 16
            Text { text: "Restore default parameters?"; color: Theme.white; font.pixelSize: 17; font.bold: true; Layout.alignment: Qt.AlignHCenter }
            Text {
                text: "Writes the known-good snapshot to the vehicle, overwriting current values. Takes about "
                      + (Math.floor(mavlink.defaultParameterCount / 40) + 5) + " seconds. Reboot the vehicle afterwards."
                color: Theme.gray
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
            FlatButton {
                Layout.fillWidth: true
                text: "Write " + mavlink.defaultParameterCount + " parameters"
                bgColor: Theme.red; textColor: Theme.white; implicitHeight: 44
                onClicked: { mavlink.restoreDefaultParameters(); restoreDialog.close() }
            }
            FlatButton {
                Layout.fillWidth: true
                text: "Cancel"; bgColor: Theme.withAlpha(Theme.gray, 0.3); textColor: Theme.white; bold: false; implicitHeight: 44
                onClicked: restoreDialog.close()
            }
        }
    }
}
