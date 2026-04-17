pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

StyledRect {
    id: root

    required property var window
    required property string sourceToken
    property string monitorName: ""
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

    radius: Tokens.rounding.small
    color: dragHandler.active ? Colours.tPalette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh
    border.width: 1
    border.color: dragHandler.active ? Colours.tPalette.m3secondary : Colours.tPalette.m3outlineVariant

    implicitHeight: 58
    implicitWidth: 96

    Drag.active: dragHandler.active
    Drag.source: root
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2
    Drag.keys: ["workspace-overlay-window"]

    x: dragHandler.active ? dragX : 0
    y: dragHandler.active ? dragY : 0
    z: dragHandler.active ? 20 : 1
    scale: dragHandler.active ? 0.94 : 1

    Behavior on scale {
        Anim {
            type: Anim.Standard
        }
    }

    ScreencopyView {
        id: preview

        anchors.fill: parent
        anchors.margins: 1
        captureSource: root.window?.wayland ?? root.window ?? null
        live: true
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 1
        height: 18
        radius: root.radius - 1
        color: Qt.rgba(0, 0, 0, 0.5)

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.small
            anchors.right: parent.right
            anchors.rightMargin: Tokens.padding.small
            text: root.window?.lastIpcObject?.class || root.window?.title || qsTr("Window")
            elide: Text.ElideRight
            font.pointSize: Tokens.font.size.smaller
            color: Qt.rgba(1, 1, 1, 0.9)
        }
    }

    Loader {
        anchors.centerIn: parent
        active: !root.window

        sourceComponent: MaterialIcon {
            text: "web_asset_off"
            color: Qt.rgba(1, 1, 1, 0.45)
            font.pointSize: Tokens.font.size.large
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
