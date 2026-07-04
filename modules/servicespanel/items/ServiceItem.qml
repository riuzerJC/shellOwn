import QtQuick
import QtQuick.Controls
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.servicespanel.core

Item {
    id: root

    required property var modelData
    required property var list

    function stateLabel(state: string): string {
        if (state === "running")
            return qsTr("Running");
        if (state === "stopped")
            return qsTr("Stopped");
        return qsTr("Unknown");
    }

    function stateColor(state: string): color {
        if (state === "running")
            return Colours.palette.m3tertiaryContainer;
        if (state === "stopped")
            return Colours.palette.m3errorContainer;
        return Colours.palette.m3surfaceContainerHigh;
    }

    function stateTextColor(state: string): color {
        if (state === "running")
            return Colours.palette.m3onTertiaryContainer;
        if (state === "stopped")
            return Colours.palette.m3onErrorContainer;
        return Colours.palette.m3onSurfaceVariant;
    }

    function triggerPrimaryAction(): void {
        if (root.modelData?.busy)
            return;

        if (root.modelData?.state === "running" && (root.modelData?.capabilities?.stop ?? false))
            ServiceOrchestrator.stopServiceById(root.modelData.id);
        else
            ServiceOrchestrator.startServiceById(root.modelData?.id ?? "");
    }

    implicitHeight: Tokens.sizes.launcher.itemHeight
    anchors.left: parent?.left
    anchors.right: parent?.right

    FontLoader {
        id: nerdFontLoader
        source: "/usr/share/fonts/TTF/CaskaydiaCoveNerdFont-Regular.ttf"
    }

    StateLayer {
        function onClicked(): void {
            root.triggerPrimaryAction();
        }

        radius: Tokens.rounding.large
        disabled: root.modelData?.busy ?? false
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        // Service icon (left)
        MaterialIcon {
            id: icon

            text: root.modelData?.icon ?? "deployed_code"
            fontStyle: Tokens.font.icon.extraLarge
            color: Colours.palette.m3onSurface
            anchors.verticalCenter: parent.verticalCenter
            visible: root.modelData?.iconFont !== "nerd"
        }

        Loader {
            id: nerdIconLoader

            anchors.verticalCenter: parent.verticalCenter
            active: root.modelData?.iconFont === "nerd"
            visible: active
            sourceComponent: Component {
                Text {
                    text: root.modelData?.icon ?? ""
                    font.family: nerdFontLoader.name
                    font.pointSize: 32
                    color: Colours.palette.m3onSurface
                    renderType: Text.NativeRendering
                }
            }
        }

        // Right-side group: state badge + action icons
        Row {
            id: rightGroup

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.spacing.small

            StyledRect {
                radius: Tokens.rounding.full
                color: root.stateColor(root.modelData?.state ?? "unknown")
                implicitWidth: stateText.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: stateText.implicitHeight + Tokens.padding.small * 2

                StyledText {
                    id: stateText

                    anchors.centerIn: parent
                    text: root.stateLabel(root.modelData?.state ?? "unknown")
                    color: root.stateTextColor(root.modelData?.state ?? "unknown")
                    font: Tokens.font.label.small
                }
            }

            ActionIcon {
                iconName: "refresh"
                tooltipText: qsTr("Refresh status")
                enabled: !(root.modelData?.busy ?? false)
                onTriggered: ServiceOrchestrator.probeServiceById(root.modelData?.id ?? "")
            }

            ActionIcon {
                iconName: "play_arrow"
                tooltipText: qsTr("Start")
                enabled: !(root.modelData?.busy ?? false) && (root.modelData?.capabilities?.start ?? true) && (root.modelData?.state !== "running")
                onTriggered: ServiceOrchestrator.startServiceById(root.modelData?.id ?? "")
            }

            ActionIcon {
                iconName: "stop"
                tooltipText: qsTr("Stop")
                enabled: !(root.modelData?.busy ?? false) && (root.modelData?.capabilities?.stop ?? false) && (root.modelData?.state !== "stopped")
                onTriggered: ServiceOrchestrator.stopServiceById(root.modelData?.id ?? "")
            }

            CircularIndicator {
                implicitWidth: 18
                implicitHeight: 18
                running: root.modelData?.busy ?? false
            }
        }

        // Text area (fills space between icon and rightGroup)
        Item {
            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.right: rightGroup.left
            anchors.rightMargin: Tokens.spacing.medium
            anchors.verticalCenter: icon.verticalCenter

            implicitHeight: name.implicitHeight + description.implicitHeight

            StyledText {
                id: name

                anchors.left: parent.left
                anchors.right: parent.right
                text: root.modelData?.name ?? ""
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            StyledText {
                id: description

                anchors.top: name.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                text: root.modelData?.lastError?.length > 0 ? root.modelData.lastError : (root.modelData?.description ?? "")
                font: Tokens.font.body.small
                color: root.modelData?.lastError?.length > 0 ? Colours.palette.m3error : Colours.palette.m3outline
                elide: Text.ElideRight
            }
        }
    }

    component ActionIcon: Item {
        id: iconRoot

        required property string iconName
        required property string tooltipText
        required property bool enabled
        signal triggered

        implicitWidth: icon.implicitWidth
        implicitHeight: icon.implicitHeight

        MaterialIcon {
            id: icon

            text: iconRoot.iconName
            color: iconRoot.enabled ? Colours.palette.m3onSurfaceVariant : Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.3)
            fontStyle: Tokens.font.icon.large

            ToolTip.visible: mouse.containsMouse
            ToolTip.text: iconRoot.tooltipText

            MouseArea {
                id: mouse

                anchors.fill: parent
                enabled: iconRoot.enabled
                hoverEnabled: true
                cursorShape: iconRoot.enabled ? Qt.PointingHandCursor : undefined
                onClicked: iconRoot.triggered()
            }
        }
    }
}
