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
    property var screenState: null
    required property var onDragCommit

    readonly property string address: window?.address ?? ""
    readonly property int sourceWorkspaceId: window?.workspace?.id ?? -1
    readonly property string sourceWorkspaceName: window?.workspace?.name ?? ""
    readonly property bool isActiveWindow: Hypr.activeToplevel?.address === root.address
    readonly property string appClass: window?.lastIpcObject?.class || window?.title || qsTr("Window")

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
    border.width: (isActiveWindow || dragHandler.active) ? 2 : 1
    border.color: isActiveWindow ? Colours.tPalette.m3primary : (dragHandler.active ? Colours.tPalette.m3secondary : Colours.tPalette.m3outlineVariant)
    clip: true
    implicitHeight: 70
    implicitWidth: 104

    Drag.active: dragHandler.active
    Drag.source: root
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2
    Drag.keys: ["workspace-overlay-window"]

    x: dragHandler.active ? dragX : 0
    y: dragHandler.active ? dragY : 0
    z: dragHandler.active ? 100 : 1
    scale: dragHandler.active ? 0.92 : (hoverHandler.hovered ? 1.03 : 1.0)

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

    // App Class / Title Banner at the bottom
    StyledRect {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 20
        radius: 0
        color: Qt.alpha(Colours.palette.m3scrim, 0.72)

        StyledText {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.small
            anchors.rightMargin: Tokens.padding.small
            verticalAlignment: Text.AlignVCenter
            text: root.appClass
            elide: Text.ElideRight
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurface
        }
    }

    Loader {
        anchors.centerIn: parent
        active: !root.window

        sourceComponent: MaterialIcon {
            text: "web_asset_off"
            color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.55)
            fontStyle: Tokens.font.icon.large
        }
    }

    HoverHandler {
        id: hoverHandler

        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: {
            if (root.address) {
                const cleanAddr = root.address.replace(/^0x/, "");
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ window = "address:0x${cleanAddr}" })` : `focuswindow address:0x${cleanAddr}`);
                if (root.screenState)
                    root.screenState.workspaceOverlay = false;
            }
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
