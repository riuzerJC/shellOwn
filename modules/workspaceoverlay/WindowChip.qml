pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

StyledRect {
    id: root

    required property var window
    required property string sourceToken
    required property string monitorName
    required property var onDragCommit

    readonly property string address: window?.address ?? ""
    readonly property int sourceWorkspaceId: window?.workspace?.id ?? -1
    readonly property string sourceWorkspaceName: window?.workspace?.name ?? ""

    readonly property var dragPayload: ({
            address: address,
            sourceWorkspaceId: sourceWorkspaceId,
            sourceWorkspaceName: sourceWorkspaceName,
            sourceToken: sourceToken,
            monitorName: monitorName
        })

    property real dragX: 0
    property real dragY: 0

    radius: Tokens.rounding.large
    color: dragHandler.active ? Colours.tPalette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh
    border.width: 2
    border.color: Colours.tPalette.m3outlineVariant

    implicitHeight: content.implicitHeight + Tokens.padding.large * 2
    implicitWidth: Math.max(240, content.implicitWidth + Tokens.padding.normal * 2)

    Drag.active: dragHandler.active
    Drag.source: root
    Drag.hotSpot.x: dragHandler.centroid.position.x
    Drag.hotSpot.y: dragHandler.centroid.position.y
    Drag.keys: ["workspace-overlay-window"]

    x: dragHandler.active ? dragX : 0
    y: dragHandler.active ? dragY : 0
    z: dragHandler.active ? 20 : 1
    scale: dragHandler.active ? 0.96 : 1

    Behavior on scale {
        Anim {}
    }

    Row {
        id: content

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Tokens.padding.large
        anchors.right: parent.right
        anchors.rightMargin: Tokens.padding.large
        spacing: Tokens.spacing.normal

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: Icons.getAppCategoryIcon(root.window?.lastIpcObject?.class, "terminal")
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x
            text: root.window?.title || root.window?.lastIpcObject?.class || qsTr("Unknown window")
            elide: Text.ElideRight
            font.pointSize: Tokens.font.size.normal
        }
    }

    DragHandler {
        id: dragHandler

        target: null
        grabPermissions: PointerHandler.CanTakeOverFromItems
            | PointerHandler.CanTakeOverFromHandlersOfSameType
            | PointerHandler.CanTakeOverFromHandlersOfDifferentType

        xAxis.onActiveValueChanged: {
            root.dragX = xAxis.activeValue;
        }

        yAxis.onActiveValueChanged: {
            root.dragY = yAxis.activeValue;
        }

        onActiveChanged: {
            if (!active) {
                const payload = root.dragPayload;
                root.dragX = 0;
                root.dragY = 0;
                root.onDragCommit(payload);
            }
        }
    }
}
