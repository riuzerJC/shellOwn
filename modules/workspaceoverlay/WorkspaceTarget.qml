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

    readonly property int wsId: workspace?.id ?? -1
    readonly property string wsName: workspace?.name ?? ""
    readonly property bool isSpecial: kind === "special"
    readonly property string targetToken: isSpecial ? wsName : String(wsId)
    readonly property bool dropActive: hoveredTarget?.targetToken === targetToken
    readonly property bool canDrop: {
        const payload = dropArea.drag.source?.dragPayload;
        if (!payload || !payload.address)
            return dropActive;
        return payload.sourceToken !== targetToken;
    }

    radius: Tokens.rounding.large
    color: dropActive ? (canDrop ? Colours.tPalette.m3secondaryContainer : Colours.tPalette.m3errorContainer) : Colours.tPalette.m3surfaceContainer
    border.width: 2
    border.color: dropActive ? (canDrop ? Colours.tPalette.m3secondary : Colours.tPalette.m3error) : Colours.tPalette.m3outlineVariant

    implicitHeight: header.implicitHeight + windowList.implicitHeight + Tokens.padding.large * 2
    implicitWidth: 360

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            id: header

            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: root.isSpecial ? root.wsName : qsTr("Workspace %1").arg(root.wsId)
                font.pointSize: Tokens.font.size.large
            }

            StyledText {
                text: qsTr("%1 windows").arg(root.windows.length)
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Tokens.font.size.normal
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.windows.length === 0
            text: root.isSpecial ? qsTr("Empty special workspace — drop a window here") : qsTr("Drop window here")
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Tokens.font.size.normal
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }

        Column {
            id: windowList

            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Repeater {
                model: root.windows

                WindowChip {
                    required property var modelData

                    width: parent.width
                    window: modelData
                    sourceToken: root.targetToken
                    monitorName: root.workspace?.monitor?.name ?? ""
                    onDragCommit: payload => root.onDragCommit(payload, root.hoveredTarget)
                }
            }

            Repeater {
                model: Object.keys(root.inFlightByAddress)

                delegate: StyledText {
                    required property string modelData

                    visible: root.inFlightByAddress[modelData]?.targetToken === root.targetToken
                    text: qsTr("Moving 0x%1…").arg(modelData)
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Tokens.font.size.small
                }
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
