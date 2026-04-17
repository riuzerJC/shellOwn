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
<<<<<<< HEAD
<<<<<<< HEAD
=======
>>>>>>> fdf21b58 (feat: refine workspace overlay styling and behavior)
    readonly property color idleColor: isSpecial ? Qt.alpha(Colours.palette.m3surfaceContainer, 0.46) : Colours.tPalette.m3surfaceContainer
    readonly property color idleBorderColor: isSpecial ? Qt.alpha(Colours.palette.m3outlineVariant, 0.72) : Colours.tPalette.m3outlineVariant
    readonly property color previewBgColor: isSpecial ? Qt.alpha(Colours.palette.m3surfaceContainerLow, 0.5) : Colours.tPalette.m3surfaceContainerLow
    readonly property color previewBorderColor: isSpecial ? Qt.alpha(Colours.palette.m3outlineVariant, 0.64) : Colours.tPalette.m3outlineVariant
    // end-4 parity: both normal and special tiles share size
    readonly property int tileWidth: 244
    readonly property int tileHeight: 170
    readonly property int previewHeight: 124
<<<<<<< HEAD

    radius: Tokens.rounding.normal
    color: dropActive ? (canDrop ? Colours.tPalette.m3secondaryContainer : Colours.tPalette.m3errorContainer) : idleColor
    border.width: 1
    border.color: dropActive ? (canDrop ? Colours.tPalette.m3secondary : Colours.tPalette.m3error) : idleBorderColor
=======
    readonly property bool compactSpecial: isSpecial
=======
>>>>>>> fdf21b58 (feat: refine workspace overlay styling and behavior)

    radius: Tokens.rounding.normal
    color: dropActive ? (canDrop ? Colours.tPalette.m3secondaryContainer : Colours.tPalette.m3errorContainer) : idleColor
    border.width: 1
<<<<<<< HEAD
    border.color: dropActive ? (canDrop ? Qt.rgba(0.6, 0.75, 1, 0.95) : Qt.rgba(1, 0.45, 0.45, 0.95)) : Qt.rgba(1, 1, 1, 0.12)
>>>>>>> 372bdb2c (feat: refactor workspace overlay into preview tile grids)
=======
    border.color: dropActive ? (canDrop ? Colours.tPalette.m3secondary : Colours.tPalette.m3error) : idleBorderColor
>>>>>>> fdf21b58 (feat: refine workspace overlay styling and behavior)
    clip: true

    readonly property int previewColumns: 3
    readonly property int previewRows: 2
    readonly property int previewCapacity: previewColumns * previewRows

<<<<<<< HEAD
<<<<<<< HEAD
    implicitHeight: tileHeight
    implicitWidth: tileWidth

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4
=======
    implicitHeight: compactSpecial ? 120 : 174
    implicitWidth: compactSpecial ? 220 : 248

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: Tokens.spacing.small
>>>>>>> 372bdb2c (feat: refactor workspace overlay into preview tile grids)
=======
    implicitHeight: tileHeight
    implicitWidth: tileWidth

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4
>>>>>>> fdf21b58 (feat: refine workspace overlay styling and behavior)

        RowLayout {
            id: header

            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: root.isSpecial ? root.wsName : qsTr("Workspace %1").arg(root.wsId)
                font.pointSize: Tokens.font.size.normal
<<<<<<< HEAD
<<<<<<< HEAD
                font.weight: 600
                color: Colours.tPalette.m3onSurface
=======
>>>>>>> 372bdb2c (feat: refactor workspace overlay into preview tile grids)
=======
                font.weight: 600
                color: Colours.tPalette.m3onSurface
>>>>>>> fdf21b58 (feat: refine workspace overlay styling and behavior)
            }

            StyledText {
                text: qsTr("%1 windows").arg(root.windows.length)
<<<<<<< HEAD
<<<<<<< HEAD
                color: Colours.tPalette.m3onSurfaceVariant
=======
                color: Qt.rgba(1, 1, 1, 0.72)
>>>>>>> 372bdb2c (feat: refactor workspace overlay into preview tile grids)
=======
                color: Colours.tPalette.m3onSurfaceVariant
>>>>>>> fdf21b58 (feat: refine workspace overlay styling and behavior)
                font.pointSize: Tokens.font.size.small
            }
        }

        Item {
            id: previewFrame

            Layout.fillWidth: true
<<<<<<< HEAD
<<<<<<< HEAD
            Layout.preferredHeight: root.previewHeight
=======
            Layout.preferredHeight: compactSpecial ? 70 : 106
>>>>>>> 372bdb2c (feat: refactor workspace overlay into preview tile grids)
=======
            Layout.preferredHeight: root.previewHeight
>>>>>>> fdf21b58 (feat: refine workspace overlay styling and behavior)

            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.small
<<<<<<< HEAD
<<<<<<< HEAD
                color: previewBgColor
                border.width: 1
                border.color: previewBorderColor

                GridLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    columns: root.previewColumns
                    columnSpacing: 4
                    rowSpacing: 4
=======
                color: Qt.rgba(0.08, 0.08, 0.12, 0.9)
=======
                color: previewBgColor
>>>>>>> fdf21b58 (feat: refine workspace overlay styling and behavior)
                border.width: 1
                border.color: previewBorderColor

                GridLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    columns: root.previewColumns
<<<<<<< HEAD
                    columnSpacing: 6
                    rowSpacing: 6
>>>>>>> 372bdb2c (feat: refactor workspace overlay into preview tile grids)
=======
                    columnSpacing: 4
                    rowSpacing: 4
>>>>>>> fdf21b58 (feat: refine workspace overlay styling and behavior)

                    Repeater {
                        model: Math.min(root.windows.length, root.previewCapacity)

                        WindowChip {
                            required property int index

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            window: root.windows[index]
                            sourceToken: root.targetToken
<<<<<<< HEAD
<<<<<<< HEAD
                            monitorName: ""
=======
                            monitorName: root.workspace?.monitor?.name ?? ""
>>>>>>> 372bdb2c (feat: refactor workspace overlay into preview tile grids)
=======
                            monitorName: ""
>>>>>>> fdf21b58 (feat: refine workspace overlay styling and behavior)
                            onDragCommit: payload => root.onDragCommit(payload, root.hoveredTarget)
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.windows.length === 0
<<<<<<< HEAD
<<<<<<< HEAD
                    text: qsTr("Drop window here")
                    color: Colours.tPalette.m3onSurfaceVariant
=======
                    text: root.isSpecial ? qsTr("Empty") : qsTr("Drop window here")
                    color: Qt.rgba(1, 1, 1, 0.5)
>>>>>>> 372bdb2c (feat: refactor workspace overlay into preview tile grids)
=======
                    text: qsTr("Drop window here")
                    color: Colours.tPalette.m3onSurfaceVariant
>>>>>>> fdf21b58 (feat: refine workspace overlay styling and behavior)
                    font.pointSize: Tokens.font.size.small
                }
            }
        }

        Repeater {
            model: Object.keys(root.inFlightByAddress)

            delegate: StyledText {
                required property string modelData

                visible: root.inFlightByAddress[modelData]?.targetToken === root.targetToken
                text: qsTr("Moving 0x%1…").arg(modelData)
<<<<<<< HEAD
<<<<<<< HEAD
                color: Colours.tPalette.m3onSurfaceVariant
=======
                color: Qt.rgba(1, 1, 1, 0.62)
>>>>>>> 372bdb2c (feat: refactor workspace overlay into preview tile grids)
=======
                color: Colours.tPalette.m3onSurfaceVariant
>>>>>>> fdf21b58 (feat: refine workspace overlay styling and behavior)
                font.pointSize: Tokens.font.size.small
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
