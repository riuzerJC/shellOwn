pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    required property var workspace
    required property string kind
    required property var windows
    required property var inFlightByAddress
    required property var hoveredTarget
    required property var setHoveredTarget
    required property var clearHoveredTarget
    required property var onDragCommit
    property var screenState: null

    readonly property int wsId: workspace?.id ?? -1
    readonly property string wsName: workspace?.name ?? ""
    readonly property bool isSpecial: kind === "special"
    readonly property string targetToken: isSpecial ? wsName : String(wsId)
    readonly property bool isActiveWs: isSpecial ? (Hypr.activeWorkspace?.name === wsName) : (Hypr.activeWorkspace?.id === wsId)
    readonly property bool dropActive: hoveredTarget?.targetToken === targetToken
    readonly property bool canDrop: {
        const payload = dropArea.drag.source?.dragPayload;
        if (!payload || !payload.address)
            return dropActive;
        return payload.sourceToken !== targetToken;
    }

    readonly property string cleanSpecialName: {
        if (!isSpecial)
            return "";
        const raw = wsName.replace(/^special:/, "");
        return raw.charAt(0).toUpperCase() + raw.slice(1);
    }

    readonly property string specialIcon: {
        if (!isSpecial)
            return "grid_view";
        const lower = wsName.toLowerCase();
        if (lower.includes("music") || lower.includes("spotify") || lower.includes("audio"))
            return "music_note";
        if (lower.includes("term") || lower.includes("console") || lower.includes("cli"))
            return "terminal";
        if (lower.includes("chat") || lower.includes("discord") || lower.includes("social"))
            return "forum";
        if (lower.includes("file") || lower.includes("doc"))
            return "folder";
        if (lower.includes("web") || lower.includes("browser"))
            return "language";
        return "auto_awesome";
    }

    readonly property color idleColor: isSpecial ? Colours.tPalette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainer
    readonly property color idleBorderColor: isSpecial ? Colours.tPalette.m3outline : Colours.tPalette.m3outlineVariant
    readonly property color previewBgColor: Colours.tPalette.m3surfaceContainerLow
    readonly property color previewBorderColor: isSpecial ? Colours.tPalette.m3outline : Colours.tPalette.m3outlineVariant

    // Native 16:10 aspect ratio tile proportions
    readonly property int tileWidth: 236
    readonly property int tileHeight: 160
    readonly property int previewHeight: 114
    readonly property int previewColumns: 3
    readonly property int previewRows: 2
    readonly property int previewCapacity: previewColumns * previewRows

    radius: Tokens.rounding.medium
    color: dropActive ? (canDrop ? Colours.tPalette.m3secondaryContainer : Colours.tPalette.m3errorContainer) : (hoverHandler.hovered ? Colours.tPalette.m3surfaceContainerHigh : idleColor)
    border.width: (isActiveWs || dropActive) ? 2 : 1
    border.color: isActiveWs ? Colours.tPalette.m3primary : (dropActive ? (canDrop ? Colours.tPalette.m3secondary : Colours.tPalette.m3error) : (hoverHandler.hovered ? Colours.tPalette.m3primary : idleBorderColor))
    clip: true
    implicitHeight: tileHeight
    implicitWidth: tileWidth

    Behavior on color {
        ColorAnimation {
            duration: 150
        }
    }

    Behavior on border.color {
        ColorAnimation {
            duration: 150
        }
    }

    HoverHandler {
        id: hoverHandler

        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: {
            if (root.isSpecial) {
                const specialName = root.wsName.replace(/^special:/, "");
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.workspace.toggle_special("${specialName}")` : `togglespecialworkspace ${specialName}`);
            } else if (root.wsId > 0) {
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = ${root.wsId} })` : `workspace ${root.wsId}`);
            }
            if (root.screenState)
                root.screenState.workspaceOverlay = false;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.small
        spacing: Tokens.spacing.extraSmall

        // Header Row
        RowLayout {
            id: header

            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                visible: root.isSpecial
                text: root.specialIcon
                fontStyle: Tokens.font.icon.small
                color: root.isActiveWs ? Colours.tPalette.m3primary : Colours.tPalette.m3onSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: root.isSpecial ? root.cleanSpecialName : qsTr("Workspace %1").arg(root.wsId)
                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                color: root.isActiveWs ? Colours.tPalette.m3primary : Colours.tPalette.m3onSurface
                elide: Text.ElideRight
            }

            StyledRect {
                visible: root.isActiveWs
                radius: Tokens.rounding.full
                color: Colours.tPalette.m3primary
                implicitHeight: 18
                implicitWidth: activeText.implicitWidth + 12

                StyledText {
                    id: activeText

                    anchors.centerIn: parent
                    text: qsTr("Active")
                    font: Tokens.font.label.small
                    color: Colours.tPalette.m3onPrimary
                }
            }

            StyledText {
                text: qsTr("%1").arg(root.windows.length)
                color: Colours.tPalette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }

        // Preview Window Grid Frame
        Item {
            id: previewFrame

            Layout.fillWidth: true
            Layout.preferredHeight: root.previewHeight

            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.small
                color: previewBgColor
                border.width: 1
                border.color: previewBorderColor

                GridLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    columns: root.previewColumns
                    columnSpacing: 4
                    rowSpacing: 4

                    Repeater {
                        model: Math.min(root.windows.length, root.previewCapacity)

                        WindowChip {
                            required property int index

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            window: root.windows[index]
                            sourceToken: root.targetToken
                            monitorName: ""
                            screenState: root.screenState
                            onDragCommit: payload => root.onDragCommit(payload, root.hoveredTarget)
                        }
                    }
                }

                // Empty state watermark
                StyledText {
                    anchors.centerIn: parent
                    visible: root.windows.length === 0
                    text: root.isSpecial ? root.cleanSpecialName : String(root.wsId)
                    color: Qt.alpha(Colours.tPalette.m3onSurfaceVariant, 0.22)
                    font: Tokens.font.title.builders.large.size(36).weight(Font.Bold).build()
                }
            }
        }

        // Moving in-flight feedback indicator
        Repeater {
            model: Object.keys(root.inFlightByAddress)

            delegate: StyledText {
                required property string modelData

                visible: root.inFlightByAddress[modelData]?.targetToken === root.targetToken
                text: qsTr("Moving window…")
                color: Colours.tPalette.m3primary
                font: Tokens.font.label.small
            }
        }
    }

    DropArea {
        id: dropArea

        anchors.fill: parent
        keys: ["workspace-overlay-window"]

        onEntered: drag => {
            drag.accepted = true;
            root.setHoveredTarget({
                kind: root.kind,
                id: root.wsId,
                name: root.wsName,
                targetToken: root.targetToken
            });
        }

        onExited: {
            root.clearHoveredTarget(root.targetToken);
        }

        onDropped: drop => drop.accepted = true
    }
}
