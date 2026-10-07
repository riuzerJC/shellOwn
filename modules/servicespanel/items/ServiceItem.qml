pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.servicespanel.core

// Vertical card for the 179x179 grid cell (ServiceList.qml). The cell owns the width and forwards
// the height; this file only lays its content out vertically.
//
// Height budget inside Tokens.padding.medium (155 px of content), measured from a live screenshot
// at 1920x1080 scale 1 where one 11 pt line box is 18 px:
//   header 22 (icon + state label + dot) | 4 | name 18 | 4 | metrics 76 | 4 | actions 24  = 152
// The state label shares the header row with the icon: an 18 px line of its own plus its 4 px gap
// would put the action row 24 px past the bottom of the cell, which the screenshot confirmed.
//
// Width: 5 x 24 px buttons with Tokens.spacing.small gaps need 152 px of the 155 px usable width.
StyledRect {
    id: root

    required property var modelData
    required property var list

    // `state` is a built-in Item property, so the model's state is read through `serviceState`.
    // `checking` and `unknown` share one treatment: the probe has not resolved a state yet, or the
    // unit could not be queried at all.
    readonly property string serviceState: root.modelData?.state ?? "unknown"
    readonly property bool isRunning: root.serviceState === "running"
    readonly property bool isStopped: root.serviceState === "stopped"
    readonly property bool isFailed: root.serviceState === "failed"
    readonly property bool isBusy: root.modelData?.busy ?? false

    // Capability defaults mirror ServiceOrchestrator's: start, restart and autostart default on and
    // stop defaults off, so a mapping without a capabilities block never offers an impossible action.
    readonly property bool canStart: root.modelData?.capabilities?.start ?? true
    readonly property bool canStop: root.modelData?.capabilities?.stop ?? false
    readonly property bool canRestart: root.modelData?.capabilities?.restart ?? true
    readonly property bool canAutostart: root.modelData?.capabilities?.autostart ?? true
    readonly property bool canPrimary: root.isRunning ? root.canStop : root.canStart

    // Every metric comes from the probe. `—` is what a metric the probe could not resolve reads as.
    readonly property string uptimeText: {
        // `lastUpdatedAt` is read so this binding re-evaluates on every probe: uptime is relative to
        // now, and `activeSince` alone would not change when the probe refreshes it.
        const revision = root.modelData?.lastUpdatedAt ?? 0;

        return root.formatDuration(root.modelData?.activeSince ?? "");
    }
    readonly property string restartsText: `×${root.modelData?.restarts ?? 0}`
    readonly property string memoryText: root.formatBytes(root.modelData?.memoryBytes ?? null)
    readonly property string cpuText: root.formatPercent(root.modelData?.cpuPercent ?? 0)
    readonly property bool autostartOn: root.modelData?.autostart === true

    // State language (L8): stopped sinks, running rises in primary, failed is the only state that
    // shouts. Only running and failed light the dot (L9).
    readonly property color cardColour: {
        if (root.isFailed)
            return Colours.tPalette.m3errorContainer;
        if (root.isRunning)
            return Colours.tPalette.m3surfaceContainerHigh;
        if (root.isStopped)
            return Colours.tPalette.m3surfaceContainerLowest;
        return Colours.tPalette.m3surfaceContainer;
    }
    readonly property color hoverColour: {
        if (root.isFailed)
            return Colours.layer(Colours.palette.m3errorContainer, 2);
        if (root.isRunning)
            return Colours.tPalette.m3surfaceContainerHighest;
        if (root.isStopped)
            return Colours.tPalette.m3surfaceContainerLow;
        return Colours.tPalette.m3surfaceContainerHigh;
    }
    readonly property color borderColour: {
        if (root.isFailed)
            return Colours.tPalette.m3error;
        if (root.isRunning)
            return Colours.tPalette.m3primary;
        return Colours.tPalette.m3outlineVariant;
    }
    readonly property color titleColour: {
        if (root.isFailed)
            return Colours.tPalette.m3onErrorContainer;
        if (root.isStopped)
            return Colours.tPalette.m3onSurfaceVariant;
        return Colours.tPalette.m3onSurface;
    }
    readonly property color detailColour: {
        if (root.isFailed)
            return Colours.tPalette.m3onErrorContainer;
        if (root.isRunning)
            return Colours.tPalette.m3primary;
        return Colours.tPalette.m3onSurfaceVariant;
    }
    readonly property color iconColour: {
        if (root.isFailed)
            return Colours.tPalette.m3onErrorContainer;
        if (root.isRunning)
            return Colours.tPalette.m3primary;
        return Colours.tPalette.m3onSurfaceVariant;
    }
    readonly property color dotColour: root.isFailed ? Colours.tPalette.m3error : Colours.tPalette.m3primary
    readonly property bool dotLit: root.isRunning || root.isFailed
    // Read here, not inside the ShapePath: path elements have no screen, and the config tokens
    // warn when they are read without one.
    readonly property real outlineDashLength: Tokens.spacing.extraSmall

    // Nerd Font glyphs live in their own family: the Material Symbols ligature names used by
    // iconFont "material" do not exist there. Resolved by family name, as the mono token does,
    // instead of a font file path that only exists in one distro's layout.
    readonly property string nerdIconFamily: "CaskaydiaCove Nerd Font"
    // One step below the Material path's icon.medium: Nerd glyphs fill their em more than Material
    // Symbols do, so at icon.medium the ink still overflowed the 22 px icon slot for some glyphs.
    // icon.small is the smallest icon token, so the last step down is derived from it rather than
    // written as a bare point size: deriving keeps appearance.font.scale working, which a literal
    // number would silently ignore.
    readonly property int nerdIconPointSize: Math.round(Tokens.font.icon.small.pointSize * 0.85)

    function stateLabel(value: string): string {
        if (value === "running")
            return Tr.tr("Running");
        if (value === "stopped")
            return Tr.tr("Stopped");
        if (value === "failed")
            return Tr.tr("Failed");
        if (value === "checking")
            return Tr.tr("Checking…");
        return Tr.tr("Unknown");
    }

    function formatDuration(timestamp: string): string {
        if (!timestamp || timestamp.length === 0)
            return "—";

        // systemd writes ActiveEnterTimestamp as "Tue 2026-10-07 10:23:45 CEST". The numeric fields
        // are enough: systemd prints local time, which is the timezone the Date is built in here.
        const fields = /(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})/.exec(timestamp);
        if (!fields)
            return "—";

        const startedAt = new Date(Number(fields[1]), Number(fields[2]) - 1, Number(fields[3]), Number(fields[4]), Number(fields[5]), Number(fields[6]));
        const seconds = Math.floor((Date.now() - startedAt.getTime()) / 1000);
        if (!isFinite(seconds) || seconds < 0)
            return "—";

        const days = Math.floor(seconds / 86400);
        const hours = Math.floor(seconds / 3600) % 24;
        const minutes = Math.floor(seconds / 60) % 60;

        if (days > 0)
            return `${days}d ${hours}h`;
        if (hours > 0)
            return `${hours}h ${minutes}m`;
        if (minutes > 0)
            return `${minutes}m`;
        return `${seconds}s`;
    }

    function formatBytes(bytes: var): string {
        if (typeof bytes !== "number" || !isFinite(bytes) || bytes < 0)
            return "—";

        if (bytes < 1024)
            return `${Math.round(bytes)} B`;
        if (bytes < 1024 * 1024)
            return `${Math.round(bytes / 1024)} KB`;
        if (bytes < 1024 * 1024 * 1024)
            return `${Math.round(bytes / (1024 * 1024))} MB`;
        return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
    }

    function formatPercent(value: var): string {
        if (typeof value !== "number" || !isFinite(value))
            return "—";
        if (value < 0.05)
            return "0%";

        return `${value.toFixed(1)}%`;
    }

    function triggerPrimaryAction(): void {
        if (root.isBusy || !root.canPrimary)
            return;

        if (root.isRunning)
            ServiceOrchestrator.stopServiceById(root.modelData?.id ?? "");
        else
            ServiceOrchestrator.startServiceById(root.modelData?.id ?? "");
    }

    radius: Tokens.rounding.medium
    color: hoverHandler.hovered ? root.hoverColour : root.cardColour
    // Stopped carries no solid border: the dashed outline below draws it instead.
    border.width: root.isStopped ? 0 : 1
    border.color: root.borderColour
    // No implicit size: the grid cell sets the width through the anchors and the delegate binds the
    // height, so the card fills the 179x179 cell it is given.
    anchors.left: parent?.left
    anchors.right: parent?.right

    Behavior on border.color {
        CAnim {}
    }

    HoverHandler {
        id: hoverHandler
    }

    // The sunken stopped state is outlined in dashes. A Rectangle border is solid only, so the
    // outline is a stroked rounded-rect path, inset by half a stroke to stay inside the card.
    Shape {
        id: outline

        // Path elements cannot see properties declared on their ShapePath, so the geometry they
        // need is published here and reached through the Shape's id.
        readonly property real corner: Math.min(root.radius, Math.min(outline.width, outline.height) / 2)

        anchors.fill: parent
        anchors.margins: 0.5
        visible: root.isStopped

        ShapePath {
            strokeWidth: 1
            strokeColor: Colours.tPalette.m3outlineVariant
            strokeStyle: ShapePath.DashLine
            dashPattern: [root.outlineDashLength, root.outlineDashLength]
            fillColor: "transparent"
            startX: outline.corner
            startY: 0

            PathLine {
                relativeX: outline.width - outline.corner * 2
                relativeY: 0
            }
            PathArc {
                relativeX: outline.corner
                relativeY: outline.corner
                radiusX: outline.corner
                radiusY: outline.corner
                direction: PathArc.Clockwise
            }
            PathLine {
                relativeX: 0
                relativeY: outline.height - outline.corner * 2
            }
            PathArc {
                relativeX: -outline.corner
                relativeY: outline.corner
                radiusX: outline.corner
                radiusY: outline.corner
                direction: PathArc.Clockwise
            }
            PathLine {
                relativeX: -(outline.width - outline.corner * 2)
                relativeY: 0
            }
            PathArc {
                relativeX: -outline.corner
                relativeY: -outline.corner
                radiusX: outline.corner
                radiusY: outline.corner
                direction: PathArc.Clockwise
            }
            PathLine {
                relativeX: 0
                relativeY: -(outline.height - outline.corner * 2)
            }
            PathArc {
                relativeX: outline.corner
                relativeY: -outline.corner
                radiusX: outline.corner
                radiusY: outline.corner
                direction: PathArc.Clockwise
            }
        }
    }

    // The content column is clipped as a safety net: the cell height is frozen at 179 px, so a font
    // scale above 1 would otherwise draw the action row over the card below.
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.extraSmall
        clip: true

        // Header: icon and state label on the left, neon status dot on the right.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 22

            Item {
                id: iconSlot

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 22
                implicitHeight: 22
                opacity: root.isStopped ? 0.55 : 1

                MaterialIcon {
                    anchors.centerIn: parent
                    opacity: root.isBusy ? 0.3 : 1
                    visible: root.modelData?.iconFont !== "nerd"
                    text: root.modelData?.icon ?? "deployed_code"
                    fontStyle: Tokens.font.icon.medium
                    color: root.iconColour
                }

                Loader {
                    anchors.centerIn: parent
                    opacity: root.isBusy ? 0.3 : 1
                    active: root.modelData?.iconFont === "nerd"
                    visible: active

                    sourceComponent: Text {
                        text: root.modelData?.icon ?? ""
                        font.family: root.nerdIconFamily
                        font.pointSize: root.nerdIconPointSize
                        color: root.iconColour
                        renderType: Text.NativeRendering
                    }
                }

                CircularIndicator {
                    anchors.centerIn: parent
                    implicitWidth: 20
                    implicitHeight: 20
                    running: root.isBusy
                    visible: root.isBusy
                }
            }

            StyledText {
                anchors.left: iconSlot.right
                anchors.leftMargin: Tokens.spacing.small
                anchors.right: dotSlot.left
                anchors.rightMargin: Tokens.spacing.small
                anchors.verticalCenter: parent.verticalCenter

                text: root.stateLabel(root.serviceState)
                font: Tokens.font.label.small
                color: root.detailColour
                elide: Text.ElideRight
            }

            Item {
                id: dotSlot

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 22
                implicitHeight: 22

                // The glow is a blurred copy behind the dot, following the Workspaces.qml pattern.
                // The blur is only enabled for the two lit states, so unlit cards never pay for it.
                StyledRect {
                    anchors.centerIn: parent
                    implicitWidth: 22
                    implicitHeight: 22
                    radius: Tokens.rounding.full
                    color: root.dotColour
                    opacity: root.dotLit ? 0.7 : 0
                    layer.enabled: root.dotLit
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 1
                        blurMax: 8
                    }
                }

                StyledRect {
                    anchors.centerIn: parent
                    implicitWidth: Tokens.spacing.small
                    implicitHeight: Tokens.spacing.small
                    radius: Tokens.rounding.full
                    color: root.dotLit ? root.dotColour : Colours.tPalette.m3outlineVariant
                }
            }
        }

        // Clamped to the measured 18 px of an 11 pt line, so a slightly taller line box cannot push
        // the action row out of the cell.
        StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: 18
            text: root.modelData?.name ?? ""
            font: Tokens.font.label.builders.small.weight(Font.Medium).build()
            color: root.titleColour
            elide: Text.ElideRight
        }

        // The four metrics in a 2x2 block: label above value, which needs half the height of four
        // stacked rows. The block absorbs whatever height is left in the column.
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            opacity: root.isStopped ? 0.7 : 1
            columns: 2
            columnSpacing: Tokens.spacing.small
            rowSpacing: Tokens.spacing.extraSmall

            Repeater {
                model: [
                    { label: Tr.tr("Uptime"), value: root.uptimeText },
                    { label: Tr.tr("Restarts"), value: root.restartsText },
                    { label: Tr.tr("Memory"), value: root.memoryText },
                    { label: Tr.tr("CPU"), value: root.cpuText }
                ]

                delegate: ColumnLayout {
                    id: metric

                    required property var modelData

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: metric.modelData.label
                        font: Tokens.font.label.small
                        color: root.detailColour
                        opacity: 0.7
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: metric.modelData.value
                        font: Tokens.font.label.builders.small.weight(Font.Medium).build()
                        color: root.titleColour
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // Actions, always visible (S6): start/stop, restart, autostart, logs and a single-service
        // re-probe. Hidden when the mapping's capabilities cannot perform them.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 24
            spacing: Tokens.spacing.small

            IconButton {
                visible: root.canPrimary
                implicitWidth: 24
                implicitHeight: 24
                isRound: true
                disabled: root.isBusy
                font: Tokens.font.icon.small
                icon: root.isRunning ? "stop" : "play_arrow"
                inactiveColour: root.isRunning ? Colours.tPalette.m3error : Colours.tPalette.m3primary
                inactiveOnColour: root.isRunning ? Colours.tPalette.m3onError : Colours.tPalette.m3onPrimary
                onClicked: root.triggerPrimaryAction()
            }

            IconButton {
                visible: root.canRestart
                implicitWidth: 24
                implicitHeight: 24
                isRound: true
                disabled: root.isBusy
                font: Tokens.font.icon.small
                type: IconButton.Text
                icon: "restart_alt"
                onClicked: ServiceOrchestrator.restartServiceById(root.modelData?.id ?? "")
            }

            // The button is a projection of the model, not a self-toggling control: `isToggle`
            // would leave it showing a state the unit is not in when the action fails.
            IconButton {
                visible: root.canAutostart
                implicitWidth: 24
                implicitHeight: 24
                isRound: true
                disabled: root.isBusy
                font: Tokens.font.icon.small
                type: IconButton.Text
                icon: root.autostartOn ? "toggle_on" : "toggle_off"
                inactiveOnColour: root.autostartOn ? Colours.tPalette.m3primary : Colours.tPalette.m3onSurfaceVariant
                onClicked: ServiceOrchestrator.setAutostartById(root.modelData?.id ?? "", !root.autostartOn)
            }

            IconButton {
                implicitWidth: 24
                implicitHeight: 24
                isRound: true
                disabled: root.isBusy
                font: Tokens.font.icon.small
                type: IconButton.Text
                icon: "terminal"
                onClicked: ServiceOrchestrator.openLogsById(root.modelData?.id ?? "")
            }

            IconButton {
                implicitWidth: 24
                implicitHeight: 24
                isRound: true
                disabled: root.isBusy
                font: Tokens.font.icon.small
                type: IconButton.Text
                icon: "refresh"
                onClicked: ServiceOrchestrator.probeServiceById(root.modelData?.id ?? "")
            }
        }
    }
}
