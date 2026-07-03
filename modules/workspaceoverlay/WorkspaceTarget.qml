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
    readonly property color idleColor: isSpecial ? Colours.tPalette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainer
    readonly property color idleBorderColor: isSpecial ? Colours.tPalette.m3outline : Colours.tPalette.m3outlineVariant
    readonly property color previewBgColor: Colours.tPalette.m3surfaceContainerLow
    readonly property color previewBorderColor: isSpecial ? Colours.tPalette.m3outline : Colours.tPalette.m3outlineVariant
    // end-4 parity: both normal and special tiles share size
    readonly property int tileWidth: 244
    readonly property int tileHeight: 170
    readonly property int previewHeight: 124

    radius: Tokens.rounding.medium
    color: dropActive ? (canDrop ? Colours.tPalette.m3secondaryContainer : Colours.tPalette.m3errorContainer) : idleColor
    border.width: 1
    border.color: dropActive ? (canDrop ? Colours.tPalette.m3secondary : Colours.tPalette.m3error) : idleBorderColor
    clip: true

    readonly property int previewColumns: 3
    readonly property int previewRows: 2
    readonly property int previewCapacity: previewColumns * previewRows

    implicitHeight: tileHeight
    implicitWidth: tileWidth

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        RowLayout {
            id: header

            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: root.isSpecial ? root.wsName : qsTr("Workspace %1").arg(root.wsId)
                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                color: Colours.tPalette.m3onSurface
            }

            StyledText {
                text: qsTr("%1 windows").arg(root.windows.length)
                color: Colours.tPalette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
        }

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
                            monitorName: root.workspace?.monitor?.name ?? ""
                            onDragCommit: payload => root.onDragCommit(payload, root.hoveredTarget)
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.windows.length === 0
                    text: qsTr("Drop window here")
                    color: Colours.tPalette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }
        }

        Repeater {
            model: Object.keys(root.inFlightByAddress)

            delegate: StyledText {
                required property string modelData

                visible: root.inFlightByAddress[modelData]?.targetToken === root.targetToken
                text: qsTr("Moving 0x%1…").arg(modelData)
                color: Colours.tPalette.m3onSurfaceVariant
                font: Tokens.font.body.small
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
