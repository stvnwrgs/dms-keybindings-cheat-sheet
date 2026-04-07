import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    minWidth: 200
    minHeight: 120

    // ── Settings ───────────────────────────────────────────────────────────────
    readonly property string compositor:      pluginData.compositor      || "hyprland"
    readonly property string configPath:      pluginData.configPath      || ""
    readonly property string additionalFiles: pluginData.additionalFiles || ""
    readonly property int    numColumns:      Math.max(1, Math.min(5, parseInt(pluginData.columns) || 1))
    readonly property real   bgOpacity:       Math.max(0, Math.min(1, (pluginData.backgroundOpacity ?? 70) / 100))
    readonly property real   fontScale:       Math.max(0.5, Math.min(2.0, (pluginData.fontScale ?? 100) / 100))
    readonly property color  accentColor: {
        var mode = pluginData.accentColorMode || "primary"
        if (mode === "secondary") return Theme.secondary
        if (mode === "custom") {
            var c = pluginData.accentColorCustom || ""
            if (c !== "") return c
        }
        return Theme.primary
    }
    readonly property var hiddenSections: {
        try { return JSON.parse(pluginData.hiddenSections || "[]") } catch(e) { return [] }
    }

    // ── Runtime state ──────────────────────────────────────────────────────────
    property var    sections:   []
    property bool   loading:    true
    property string parseError: ""
    property string stdoutBuf:  ""

    readonly property string scriptPath:
        Qt.resolvedUrl("parse-keybindings.sh").toString().replace(/^file:\/\//, "")

    readonly property var sectionOrder: {
        try { return JSON.parse(pluginData.sectionOrder || "[]") } catch(e) { return [] }
    }

    // Build a flat item list and split across N columns.
    // Each item: { type: "header"|"binding", name?, key?, description? }
    readonly property var columnData: {
        try {
            var secs   = root.sections       || []
            var hidden = root.hiddenSections  || []
            var order  = root.sectionOrder    || []
            var n      = root.numColumns

            // Sort sections: ordered IDs first, then remaining in parse order
            var ordered = []
            var secById = {}
            for (var s = 0; s < secs.length; s++) secById[secs[s].id] = secs[s]

            for (var o = 0; o < order.length; o++) {
                if (secById[order[o]]) ordered.push(secById[order[o]])
            }
            for (var s2 = 0; s2 < secs.length; s2++) {
                if (order.indexOf(secs[s2].id) === -1) ordered.push(secs[s2])
            }

            // Flatten all visible sections into a single item list
            var flat = []
            for (var i = 0; i < ordered.length; i++) {
                if (hidden.indexOf(ordered[i].id) !== -1) continue
                flat.push({ type: "header", name: ordered[i].name })
                var binds = ordered[i].bindings || []
                for (var b = 0; b < binds.length; b++) {
                    flat.push({ type: "binding", key: binds[b].key, description: binds[b].description })
                }
            }

            // Split flat list evenly across columns
            var perCol = Math.ceil(flat.length / n)
            var cols   = []
            for (var c = 0; c < n; c++) {
                cols.push(flat.slice(c * perCol, (c + 1) * perCol))
            }
            return cols
        } catch(e) {
            return [[]]
        }
    }

    readonly property bool hasContent:
        columnData.some(col => col && col.length > 0)

    Component.onCompleted:    reload()
    onCompositorChanged:      reload()
    onConfigPathChanged:      reload()
    onAdditionalFilesChanged: reload()

    function reload() {
        stdoutBuf  = ""
        parseError = ""
        loading    = true
        parserProcess.running = false
        Qt.callLater(function() {
            try {
                parserProcess.running = true
            } catch(e) {
                loading    = false
                parseError = "Could not start parser"
            }
        })
    }

    // ── Parser process ─────────────────────────────────────────────────────────
    Process {
        id: parserProcess
        command: [root.scriptPath, root.compositor, root.configPath, root.additionalFiles]

        stdout: SplitParser {
            onRead: data => root.stdoutBuf += data + "\n"
        }

        onExited: (code, signal) => {
            Qt.callLater(function() {
                root.loading = false
                if (root.stdoutBuf.trim() === "") {
                    root.parseError = "No output from parser (exit code " + code + ")"
                    return
                }
                try {
                    var parsed = JSON.parse(root.stdoutBuf.trim())
                    if (parsed.error) {
                        root.parseError = parsed.error
                        root.sections   = []
                    } else {
                        root.sections   = parsed.sections || []
                        root.parseError = ""
                    }
                } catch(e) {
                    root.parseError = "JSON parse failed: " + e
                    root.sections   = []
                }
            })
        }
    }

    // ── Background ─────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color:   Theme.surfaceContainer
        opacity: root.bgOpacity
        radius:  Theme.cornerRadius
    }

    // ── Content ────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingS

        // Header row
        RowLayout {
            Layout.fillWidth: true

            DankIcon {
                name:  "keyboard"
                size:  Theme.iconSize
                color: root.accentColor
            }

            StyledText {
                text: "Keybindings"
                font.pixelSize: Theme.fontSizeMedium * root.fontScale
                font.bold: true
                color: Theme.surfaceText
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 20; height: 20
                radius: Theme.cornerRadius / 2
                color: refreshHover.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.15) : "transparent"

                DankIcon {
                    anchors.centerIn: parent
                    name: "refresh"
                    size: 14
                    color: root.accentColor
                }

                HoverHandler { id: refreshHover }
                TapHandler { onTapped: root.reload() }
            }

            StyledText {
                text: root.compositor.toUpperCase()
                font.pixelSize: (Theme.fontSizeSmall - 1) * root.fontScale
                font.letterSpacing: 1.2
                color: root.accentColor
            }

            Rectangle {
                width: 6; height: 6; radius: 3
                color: root.loading    ? Theme.warning
                     : root.parseError ? Theme.error
                                       : root.accentColor
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.3)
        }

        // Loading / error / empty
        Item {
            visible: root.loading || !root.hasContent
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledText {
                anchors.centerIn: parent
                width: parent.width - Theme.spacingL
                text: root.loading      ? "Parsing…"
                    : root.parseError   ? "Could not parse config.\nCheck compositor and path in settings."
                                        : "No sections found.\nAdd # @section markers to your config."
                color: (!root.loading && root.parseError) ? Theme.error : Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall * root.fontScale
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // Columns
        Item {
            visible: !root.loading && root.hasContent
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Flickable {
                id: colFlickable
                anchors.fill: parent
                contentWidth: width
                contentHeight: colRow.implicitHeight
                flickableDirection: Flickable.VerticalFlick
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Row {
                    id: colRow
                    width: colFlickable.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: root.columnData

                        delegate: Column {
                            id: colDelegate
                            required property var modelData   // flat item array for this column
                            required property int index

                            width: {
                                try {
                                    var n = root.columnData ? root.columnData.length : 1
                                    if (n < 1) n = 1
                                    return (colRow.width - (n - 1) * Theme.spacingS) / n
                                } catch(e) { return colRow.width }
                            }
                            spacing: 3

                            Repeater {
                                model: colDelegate.modelData || []

                                delegate: Loader {
                                    id: itemLoader
                                    required property var modelData
                                    required property int index
                                    width: colDelegate.width

                                    sourceComponent: modelData.type === "header" ? headerComp : bindingComp

                                    property var itemData: modelData
                                    property real colWidth: colDelegate.width
                                    property color accent: root.accentColor
                                    property bool isFirstInCol: index === 0
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Section header component ────────────────────────────────────────────────
    Component {
        id: headerComp

        Item {
            width: colWidth
            height: 24 + (isFirstInCol ? 0 : Theme.spacingS)

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 24
                color: Qt.rgba(accent.r, accent.g, accent.b, 0.15)
                radius: Theme.cornerRadius / 2

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    text: (itemData.name || "").toUpperCase()
                    color: accent
                    font.pixelSize: (Theme.fontSizeSmall - 1) * root.fontScale
                    font.bold: true
                    font.letterSpacing: 0.8
                }
            }
        }
    }

    // ── Binding row component ───────────────────────────────────────────────────
    Component {
        id: bindingComp

        Item {
            width: colWidth
            height: 24

            readonly property real keyW: Math.floor(colWidth * 0.38)

            // Key badge
            Rectangle {
                id: keyRect
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                width: parent.keyW
                height: 20
                color: Qt.rgba(accent.r, accent.g, accent.b, 0.10)
                radius: 3

                StyledText {
                    anchors.centerIn: parent
                    width: parent.width - 6
                    text: itemData.key || ""
                    color: accent
                    font.pixelSize: (Theme.fontSizeSmall - 2) * root.fontScale
                    font.family: "monospace"
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            // Description
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: keyRect.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: parent.right
                text: itemData.description || ""
                color: Theme.surfaceVariantText
                font.pixelSize: (Theme.fontSizeSmall - 1) * root.fontScale
                elide: Text.ElideRight
            }
        }
    }
}
