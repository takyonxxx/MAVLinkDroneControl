// ParametersPage.qml - port of ParametersView.swift
// Reads all parameters, groups them by category, edits and writes them back,
// and can restore the known-good default snapshot or load a .param file from
// local storage (verified bulk write, see MavlinkManager::startParamWrite).
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
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

        // Header: read / load file / restore / progress
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            RowLayout {
                spacing: 12
                Layout.fillWidth: true
                FlatButton {
                    Layout.fillWidth: page.width < 560
                    text: page.width < 560 ? "Read" : "Read from Vehicle"; icon: "\u2193"; fontSize: 13
                    enabled: mavlink.connected && !mavlink.paramWriteInProgress
                    onClicked: mavlink.requestAllParameters()
                }
                FlatButton {
                    Layout.fillWidth: page.width < 560
                    text: page.width < 560 ? "File" : "Load from File"; icon: "\u2191"; fontSize: 13
                    bgColor: Theme.green
                    enabled: !mavlink.paramWriteInProgress
                    onClicked: paramFileDialog.open()
                }
                FlatButton {
                    Layout.fillWidth: page.width < 560
                    text: page.width < 560 ? "Defaults" : "Restore Defaults"; icon: "\u21BA"; fontSize: 13
                    bgColor: Theme.orange
                    enabled: mavlink.connected && !mavlink.paramWriteInProgress
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
            // Bulk write progress: pass 1 shows sent count, retries show confirmed count
            RowLayout {
                visible: mavlink.paramWriteInProgress
                spacing: 10
                Layout.fillWidth: true
                ProgressBar {
                    Layout.fillWidth: true
                    from: 0; to: Math.max(mavlink.paramWriteTotal, 1)
                    value: mavlink.paramWritePass === 1 ? mavlink.paramWriteSent : mavlink.paramWriteConfirmed
                }
                Text {
                    text: (mavlink.paramWritePass > 1 ? "retry " + mavlink.paramWritePass + "  " : "")
                          + "\u2713" + mavlink.paramWriteConfirmed + "/" + mavlink.paramWriteTotal
                    color: Theme.orange; font.pixelSize: 11; font.family: Theme.mono
                }
                Text {
                    text: "Cancel"; color: Theme.red; font.pixelSize: 11; font.bold: true
                    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: mavlink.cancelParamWrite() }
                }
            }

            // Result of the last bulk write
            Rectangle {
                id: resultBanner
                readonly property var res: mavlink.paramWriteResult
                readonly property int failCount: res.failed ? res.failed.length : 0
                readonly property bool bad: failCount > 0 || (res.error ? res.error !== "" : false) || res.cancelled === true
                visible: !mavlink.paramWriteInProgress && res.done === true
                Layout.fillWidth: true
                implicitHeight: resultRow.implicitHeight + 16
                radius: 8
                color: Theme.withAlpha(bad ? Theme.orange : Theme.green, 0.15)
                border.color: bad ? Theme.orange : Theme.green
                RowLayout {
                    id: resultRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Theme.white
                        font.pixelSize: 12
                        text: {
                            var r = resultBanner.res
                            if (!r.done) return ""
                            if (r.error) return "\u26A0 " + r.error + (r.ok ? "  (" + r.ok + "/" + r.total + " confirmed)" : "")
                            var t = (r.cancelled ? "Cancelled - " : "\u2713 ") + r.ok + "/" + r.total + " parameters confirmed"
                            if (resultBanner.failCount > 0) t += ", " + resultBanner.failCount + " failed"
                            return t + ". Reboot the vehicle to apply."
                        }
                    }
                    Text {
                        text: "Details"; color: Theme.cyan; font.pixelSize: 12; font.bold: true
                        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: writeResultDialog.open() }
                    }
                    Text {
                        text: "\u2716"; color: Theme.gray; font.pixelSize: 13
                        MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: mavlink.clearParamWriteResult() }
                    }
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

    // ---------------------------------------------------------------------
    // Load parameter file from local storage

    FileDialog {
        id: paramFileDialog
        title: "Load parameter file"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Parameter files (*.param *.parm *.params *.txt)", "All files (*)"]
        onAccepted: {
            mavlink.loadParameterFile(selectedFile)
            fileSheet.open()
        }
    }

    component OptionToggle: RowLayout {
        id: opt
        property string text: ""
        property string detail: ""
        property bool checked: true
        Layout.fillWidth: true
        spacing: 10
        TapHandler { onTapped: opt.checked = !opt.checked }
        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 2
            implicitWidth: 22; implicitHeight: 22; radius: 5
            color: opt.checked ? Theme.cyan : "transparent"
            border.color: opt.checked ? Theme.cyan : Theme.gray
            border.width: 2
            Text { anchors.centerIn: parent; visible: opt.checked; text: "\u2713"; color: Theme.black; font.pixelSize: 14; font.bold: true }
        }
        ColumnLayout {
            spacing: 1
            Layout.fillWidth: true
            Text { text: opt.text; color: Theme.white; font.pixelSize: 13; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            Text { visible: opt.detail !== ""; text: opt.detail; color: Theme.gray; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
    }

    component StatCell: ColumnLayout {
        property string label: ""
        property int value: 0
        property color valueColor: Theme.white
        spacing: 0
        Layout.fillWidth: true
        Text { text: parent.value; color: parent.valueColor; font.pixelSize: 18; font.bold: true; font.family: Theme.mono; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
        Text { text: parent.label; color: Theme.gray; font.pixelSize: 10; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
    }

    Dialog {
        id: fileSheet
        objectName: "paramFileSheet"
        modal: true
        anchors.centerIn: parent
        width: Math.min(page.width - 24, 520)
        height: Math.min(page.height - 24, implicitHeight)
        padding: 20
        background: Rectangle { radius: 16; color: Theme.sheetBg }
        onClosed: mavlink.clearParameterFile()

        readonly property var info: mavlink.paramFile
        readonly property bool loaded: info.loaded === true
        // Re-evaluated when options, the vehicle parameter list or the file change
        readonly property var plan: {
            var deps = mavlink.parameters.count + (mavlink.paramWriteInProgress ? 1 : 0)
            if (!loaded) return ({})
            return mavlink.parameterFilePlan(keepCalToggle.checked, onlyChangedToggle.checked)
        }
        readonly property bool canWrite: loaded && plan.write > 0 && mavlink.connected
                                         && !mavlink.armed && !mavlink.paramWriteInProgress

        contentItem: ColumnLayout {
            spacing: 12

            Text {
                text: "Load parameter file"; color: Theme.white; font.pixelSize: 17; font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: fileSheet.info.fileName || ""
                color: Theme.cyan; font.pixelSize: 13; font.family: Theme.mono
                elide: Text.ElideMiddle; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
            }

            // Fatal error (cannot open / nothing parsed)
            Text {
                visible: !!fileSheet.info.error
                text: "\u26A0 " + (fileSheet.info.error || "")
                color: Theme.red; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }

            Text {
                visible: fileSheet.loaded
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.gray; font.pixelSize: 12
                text: fileSheet.info.count + " parameters in file"
                      + (fileSheet.info.duplicates > 0 ? ", " + fileSheet.info.duplicates + " duplicates (last value used)" : "")
                      + (fileSheet.info.errorCount > 0 ? ", " + fileSheet.info.errorCount + " unreadable lines ignored" : "")
            }
            Text {
                visible: fileSheet.loaded && fileSheet.info.errorCount > 0
                text: (fileSheet.info.errors || []).slice(0, 3).join("\n")
                color: Theme.orange; font.pixelSize: 11; font.family: Theme.mono
                Layout.fillWidth: true; elide: Text.ElideRight
            }

            OptionToggle {
                id: keepCalToggle
                visible: fileSheet.loaded
                checked: true
                text: "Keep this vehicle's calibration"
                detail: "Skips compass/accel/gyro offsets, level trim, RC min/max/trim, power module and sensor IDs ("
                        + (fileSheet.plan.skippedCalibration || 0) + " params)"
            }
            OptionToggle {
                id: onlyChangedToggle
                visible: fileSheet.loaded
                checked: true
                text: "Write only changed values"
                detail: fileSheet.plan.vehicleParamsLoaded ? "Compared against the parameters read from the vehicle"
                                                           : "Vehicle parameters not read yet - every value will be written"
            }

            // Plan summary
            RowLayout {
                visible: fileSheet.loaded
                Layout.fillWidth: true
                spacing: 4
                StatCell { label: "to write"; value: fileSheet.plan.write || 0; valueColor: Theme.cyan }
                StatCell { label: "changed"; value: fileSheet.plan.changed || 0; valueColor: Theme.orange }
                StatCell { label: "same"; value: fileSheet.plan.same || 0; valueColor: Theme.green }
                StatCell { label: "not on vehicle"; value: fileSheet.plan.unknown || 0; valueColor: Theme.gray }
            }

            // Preview of differences
            Rectangle {
                visible: fileSheet.loaded && (fileSheet.plan.changes || []).length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 80
                Layout.preferredHeight: Math.min(220, (fileSheet.plan.changes || []).length * 26 + 8)
                radius: 10
                color: Theme.card
                ListView {
                    id: changeList
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    model: fileSheet.plan.changes || []
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    delegate: RowLayout {
                        required property var modelData
                        width: changeList.width
                        height: 26
                        spacing: 6
                        Text { text: modelData.name; color: Theme.white; font.pixelSize: 12; font.family: Theme.mono; Layout.fillWidth: true; Layout.leftMargin: 8; elide: Text.ElideRight }
                        Text { text: modelData.oldText; color: Theme.gray; font.pixelSize: 12; font.family: Theme.mono }
                        Text { text: "\u2192"; color: Theme.gray; font.pixelSize: 12 }
                        Text { text: modelData.newText; color: modelData.isNew ? Theme.gray : Theme.cyan; font.pixelSize: 12; font.family: Theme.mono; Layout.rightMargin: 8 }
                    }
                }
            }

            Text {
                visible: fileSheet.loaded && mavlink.armed
                text: "\u26A0 Vehicle is armed - disarm before writing parameters."
                color: Theme.red; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            Text {
                visible: fileSheet.loaded && !mavlink.connected
                text: "Not connected - connect to the vehicle to write."
                color: Theme.orange; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            Text {
                visible: fileSheet.loaded && (fileSheet.plan.unknown || 0) > 0 && fileSheet.plan.vehicleParamsLoaded === true
                text: "Parameters not on the vehicle usually appear after an *_ENABLE / *_TYPE change and a reboot. Load the file again after rebooting."
                color: Theme.gray; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }

            RowLayout {
                spacing: 12
                Layout.fillWidth: true
                FlatButton {
                    Layout.fillWidth: true
                    text: "Cancel"; bgColor: Theme.withAlpha(Theme.gray, 0.3); textColor: Theme.white; bold: false; implicitHeight: 44
                    onClicked: fileSheet.close()
                }
                FlatButton {
                    Layout.fillWidth: true
                    visible: fileSheet.loaded
                    text: "Write " + (fileSheet.plan.write || 0) + " parameters"
                    bgColor: Theme.red; textColor: Theme.white; implicitHeight: 44
                    enabled: fileSheet.canWrite
                    onClicked: {
                        mavlink.writeParameterFile(keepCalToggle.checked, onlyChangedToggle.checked)
                        fileSheet.close()
                    }
                }
            }
        }
    }

    // Details of the last bulk write
    Dialog {
        id: writeResultDialog
        objectName: "paramWriteResultDialog"
        modal: true
        anchors.centerIn: parent
        width: Math.min(page.width - 24, 520)
        height: Math.min(page.height - 24, implicitHeight)
        padding: 20
        background: Rectangle { radius: 16; color: Theme.sheetBg }
        readonly property var res: mavlink.paramWriteResult
        readonly property var failed: res.failed || []

        contentItem: ColumnLayout {
            spacing: 12
            Text {
                text: writeResultDialog.res.source === "defaults" ? "Restore defaults result" : "Parameter file write result"
                color: Theme.white; font.pixelSize: 17; font.bold: true; Layout.alignment: Qt.AlignHCenter
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.gray; font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
                text: (writeResultDialog.res.ok || 0) + " of " + (writeResultDialog.res.total || 0)
                      + " confirmed by the vehicle" + (writeResultDialog.res.error ? "\n" + writeResultDialog.res.error : "")
            }
            Rectangle {
                visible: writeResultDialog.failed.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 80
                Layout.preferredHeight: Math.min(260, writeResultDialog.failed.length * 40 + 8)
                radius: 10
                color: Theme.card
                ListView {
                    id: failList
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    model: writeResultDialog.failed
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    delegate: ColumnLayout {
                        required property var modelData
                        width: failList.width
                        spacing: 1
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 8; Layout.rightMargin: 8; Layout.topMargin: 4
                            Text { text: modelData.name; color: Theme.white; font.pixelSize: 12; font.family: Theme.mono; Layout.fillWidth: true }
                            Text { text: modelData.value; color: Theme.cyan; font.pixelSize: 12; font.family: Theme.mono }
                        }
                        Text { text: modelData.reason; color: Theme.orange; font.pixelSize: 11; Layout.leftMargin: 8; Layout.bottomMargin: 4 }
                    }
                }
            }
            Text {
                text: "Most changes take effect after a reboot. Parameters that appear only after enabling a feature need a reboot and a second load."
                color: Theme.gray; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            RowLayout {
                spacing: 12
                Layout.fillWidth: true
                FlatButton {
                    Layout.fillWidth: true
                    text: "Close"; bgColor: Theme.withAlpha(Theme.gray, 0.3); textColor: Theme.white; bold: false; implicitHeight: 44
                    onClicked: writeResultDialog.close()
                }
                FlatButton {
                    Layout.fillWidth: true
                    text: "Reboot Vehicle"; bgColor: Theme.orange; textColor: Theme.black; implicitHeight: 44
                    enabled: mavlink.connected && !mavlink.armed
                    onClicked: { mavlink.rebootFlightController(); writeResultDialog.close() }
                }
            }
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
