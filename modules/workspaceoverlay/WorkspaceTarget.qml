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
    readonly property bool compactSpecial: isSpecial

    radius: Tokens.rounding.normal
    color: dropActive ? (canDrop ? Qt.rgba(0.4, 0.6, 1, 0.22) : Qt.rgba(1, 0.3, 0.3, 0.24)) : Qt.rgba(0.14, 0.14, 0.18, 0.96)
    border.width: 1
    border.color: dropActive ? (canDrop ? Qt.rgba(0.6, 0.75, 1, 0.95) : Qt.rgba(1, 0.45, 0.45, 0.95)) : Qt.rgba(1, 1, 1, 0.12)
    clip: true

    readonly property int previewColumns: 3
    readonly property int previewRows: 2
    readonly property int previewCapacity: previewColumns * previewRows

    implicitHeight: compactSpecial ? 120 : 174
    implicitWidth: compactSpecial ? 220 : 248

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: Tokens.spacing.small

        RowLayout {
            id: header

            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: root.isSpecial ? root.wsName : qsTr("Workspace %1").arg(root.wsId)
                font.pointSize: Tokens.font.size.normal
            }

            StyledText {
                text: qsTr("%1 windows").arg(root.windows.length)
                color: Qt.rgba(1, 1, 1, 0.72)
                font.pointSize: Tokens.font.size.small
            }
        }

        Item {
            id: previewFrame

            Layout.fillWidth: true
            Layout.preferredHeight: compactSpecial ? 70 : 106

            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.small
                color: Qt.rgba(0.08, 0.08, 0.12, 0.9)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)

                GridLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    columns: root.previewColumns
                    columnSpacing: 6
                    rowSpacing: 6

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
                    text: root.isSpecial ? qsTr("Empty") : qsTr("Drop window here")
                    color: Qt.rgba(1, 1, 1, 0.5)
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
                color: Qt.rgba(1, 1, 1, 0.62)
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
