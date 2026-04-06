import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "keybindingCheatSheet"

    readonly property string scriptPath:
        Qt.resolvedUrl("parse-keybindings.sh").toString().replace(/^file:\/\//, "")

    // ── Live-parsed sections (runs the parser whenever compositor/path changes) ──
    property var parsedSections: []
    property string _stdoutBuf: ""

    function reloadSections() {
        if (!pluginService) return
        _stdoutBuf = ""
        settingsParser.running = false
        settingsParser.command = [
            root.scriptPath,
            root.loadValue("compositor", "hyprland"),
            root.loadValue("configPath", ""),
            root.loadValue("additionalFiles", "")
        ]
        settingsParser.running = true
    }

    onPluginServiceChanged: if (pluginService) reloadSections()

    Process {
        id: settingsParser
        stdout: SplitParser {
            onRead: data => root._stdoutBuf += data + "\n"
        }
        onExited: Qt.callLater(function() {
            try {
                var parsed = JSON.parse(root._stdoutBuf.trim())
                root.parsedSections = parsed.sections || []
            } catch(e) {
                root.parsedSections = []
            }
        })
    }

    function hiddenSections() {
        try { return JSON.parse(root.loadValue("hiddenSections", "[]") || "[]") } catch(e) { return [] }
    }

    function toggleSection(sectionId, nowVisible) {
        var hidden = hiddenSections()
        if (!nowVisible) {
            if (hidden.indexOf(sectionId) === -1) hidden.push(sectionId)
        } else {
            var idx = hidden.indexOf(sectionId)
            if (idx !== -1) hidden.splice(idx, 1)
        }
        pluginService.savePluginData(pluginId, "hiddenSections", JSON.stringify(hidden))
    }

    // ── Compositor ─────────────────────────────────────────────────────────────
    SelectionSetting {
        settingKey: "compositor"
        label: "Compositor"
        description: "Which compositor config format to parse"
        defaultValue: "hyprland"
        options: [
            { label: "Hyprland", value: "hyprland" },
            { label: "MangoWC",  value: "mangowc"  },
            { label: "Sway",     value: "sway"     },
            { label: "Niri",     value: "niri"     }
        ]
    }

    StringSetting {
        settingKey: "configPath"
        label: "Config Path"
        description: "Leave empty to use the default path for the selected compositor"
        placeholder: "~/.config/hypr/hyprland.conf"
    }

    StringSetting {
        settingKey: "additionalFiles"
        label: "Additional Files"
        description: "Comma-separated extra files to parse (e.g. separate binds sub-configs)"
        placeholder: "~/.config/hypr/binds.conf"
    }

    // ── Appearance ─────────────────────────────────────────────────────────────

    SelectionSetting {
        settingKey: "columns"
        label: "Columns"
        description: "Number of columns to distribute sections across"
        defaultValue: "1"
        options: [
            { label: "1", value: "1" },
            { label: "2", value: "2" },
            { label: "3", value: "3" },
            { label: "4", value: "4" },
            { label: "5", value: "5" }
        ]
    }

    // ── Color mode picker (Primary / Secondary / Custom) ───────────────────────
    Column {
        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            text: "Color"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        Row {
            spacing: Theme.spacingS

            Repeater {
                model: [
                    { id: "primary",   label: "Primary",   color: Theme.primary,   icon: "" },
                    { id: "secondary", label: "Secondary", color: Theme.secondary, icon: "" },
                    { id: "custom",    label: "Custom",    color: "",              icon: "edit" }
                ]

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    readonly property string modeId: modelData.id
                    readonly property bool isSelected: {
                        var m = root.loadValue("accentColorMode", "primary")
                        return m === modeId
                    }

                    width: 90
                    height: 80
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    border.color: isSelected ? Theme.primary : "transparent"
                    border.width: 2

                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        // Color circle or icon
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 28; height: 28; radius: 14
                            color: modeId === "custom"
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                : modelData.color
                            visible: modeId !== "custom"
                        }

                        DankIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "edit"
                            size: 22
                            color: Theme.surfaceText
                            visible: modeId === "custom"
                        }

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.label
                            font.pixelSize: Theme.fontSizeSmall
                            color: isSelected ? Theme.primary : Theme.surfaceText
                        }
                    }

                    HoverHandler { id: tileHover }
                    TapHandler {
                        onTapped: {
                            if (modeId === "custom") {
                                var current = root.loadValue("accentColorCustom", Theme.primary.toString())
                                if (PopoutService && PopoutService.colorPickerModal) {
                                    PopoutService.colorPickerModal.selectedColor = current
                                    PopoutService.colorPickerModal.pickerTitle = "Custom Accent Color"
                                    PopoutService.colorPickerModal.onColorSelectedCallback = function(c) {
                                        root.saveValue("accentColorCustom", c.toString())
                                        root.saveValue("accentColorMode", "custom")
                                    }
                                    PopoutService.colorPickerModal.show()
                                }
                            } else {
                                root.saveValue("accentColorMode", modeId)
                            }
                        }
                    }
                }
            }
        }
    }

    SliderSetting {
        settingKey: "backgroundOpacity"
        label: "Background Opacity"
        description: "Transparency of the widget background"
        defaultValue: 70
        minimum: 0
        maximum: 100
        unit: "%"
    }

    SliderSetting {
        settingKey: "fontScale"
        label: "Font Scale"
        description: "Scale factor for all text in the widget"
        defaultValue: 100
        minimum: 50
        maximum: 200
        unit: "%"
    }

    // ── Section order & visibility ─────────────────────────────────────────────

    ColumnLayout {
        width: parent.width
        spacing: Theme.spacingS

        // Helper functions for sort order
        function getSectionOrder() {
            var existingIds = root.parsedSections.map(s => s.id)
            try {
                var saved = JSON.parse(root.loadValue("sectionOrder", "[]") || "[]")
                // Filter out stale IDs that no longer exist
                return saved.filter(id => existingIds.indexOf(id) !== -1)
            } catch(e) { return [] }
        }

        function buildOrderedSections() {
            var order = getSectionOrder()
            var secs  = root.parsedSections || []
            var result = []
            // First: sections in saved order
            for (var o = 0; o < order.length; o++) {
                var found = secs.find(s => s.id === order[o])
                if (found) result.push(found)
            }
            // Then: sections not yet in order
            for (var s = 0; s < secs.length; s++) {
                if (order.indexOf(secs[s].id) === -1) result.push(secs[s])
            }
            return result
        }

        function moveSection(fromIdx, toIdx) {
            var ordered = buildOrderedSections()
            if (toIdx < 0 || toIdx >= ordered.length) return
            var ids = ordered.map(s => s.id)
            var tmp = ids[fromIdx]
            ids[fromIdx] = ids[toIdx]
            ids[toIdx] = tmp
            pluginService.savePluginData(pluginId, "sectionOrder", JSON.stringify(ids))
        }

        // Header row
        RowLayout {
            Layout.fillWidth: true

            StyledText {
                text: "Sections"
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
                color: Theme.surfaceText
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 28; height: 28
                radius: Theme.cornerRadius / 2
                color: reloadHover.containsMouse ? Theme.surfaceHover : "transparent"

                DankIcon {
                    anchors.centerIn: parent
                    name: "refresh"
                    size: Theme.iconSize
                    color: Theme.primary
                }

                HoverHandler { id: reloadHover }
                TapHandler { onTapped: root.reloadSections() }
            }
        }

        StyledText {
            visible: root.parsedSections.length === 0
            Layout.fillWidth: true
            text: "No sections cached yet. The widget must be active and parse successfully first."
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.Wrap
        }

        Repeater {
            id: sectionRepeater
            model: parent.buildOrderedSections()

            delegate: RowLayout {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: Theme.spacingXS

                // Move up
                Rectangle {
                    width: 24; height: 24
                    radius: Theme.cornerRadius / 2
                    color: upHover.containsMouse ? Theme.surfaceHover : "transparent"
                    opacity: index === 0 ? 0.3 : 1

                    DankIcon { anchors.centerIn: parent; name: "keyboard_arrow_up"; size: 16; color: Theme.surfaceText }
                    HoverHandler { id: upHover }
                    TapHandler { onTapped: { if (index > 0) parent.parent.parent.moveSection(index, index - 1) } }
                }

                // Move down
                Rectangle {
                    width: 24; height: 24
                    radius: Theme.cornerRadius / 2
                    color: downHover.containsMouse ? Theme.surfaceHover : "transparent"
                    opacity: index === sectionRepeater.count - 1 ? 0.3 : 1

                    DankIcon { anchors.centerIn: parent; name: "keyboard_arrow_down"; size: 16; color: Theme.surfaceText }
                    HoverHandler { id: downHover }
                    TapHandler { onTapped: { if (index < sectionRepeater.count - 1) parent.parent.parent.moveSection(index, index + 1) } }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: modelData.name
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                }

                StyledText {
                    text: modelData.bindings.length + " bindings"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }

                Switch {
                    checked: root.hiddenSections().indexOf(modelData.id) === -1
                    onToggled: root.toggleSection(modelData.id, checked)
                }
            }
        }
    }
}
