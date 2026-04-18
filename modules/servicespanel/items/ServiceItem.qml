import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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

    StateLayer {
        function onClicked(): void {
            root.triggerPrimaryAction();
        }

        radius: Tokens.rounding.normal
        disabled: root.modelData?.busy ?? false
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.larger
        anchors.rightMargin: Tokens.padding.larger
        anchors.margins: Tokens.padding.smaller

        spacing: Tokens.spacing.normal

        MaterialIcon {
            text: root.modelData?.icon ?? "deployed_code"
            font.pointSize: Tokens.font.size.extraLarge
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.modelData?.name ?? ""
                font.pointSize: Tokens.font.size.normal
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: root.modelData?.lastError?.length > 0 ? root.modelData.lastError : (root.modelData?.description ?? "")
                font.pointSize: Tokens.font.size.small
                color: root.modelData?.lastError?.length > 0 ? Colours.palette.m3error : Colours.palette.m3outline
                elide: Text.ElideRight
            }
        }

        StyledRect {
            radius: Tokens.rounding.full
            color: root.stateColor(root.modelData?.state ?? "unknown")
            implicitWidth: stateText.implicitWidth + Tokens.padding.normal * 2
            implicitHeight: stateText.implicitHeight + Tokens.padding.small * 2
            Layout.alignment: Qt.AlignVCenter

            StyledText {
                id: stateText

                anchors.centerIn: parent
                text: root.stateLabel(root.modelData?.state ?? "unknown")
                color: root.stateTextColor(root.modelData?.state ?? "unknown")
                font.pointSize: Tokens.font.size.small
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.spacing.small

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
            font.pointSize: Tokens.font.size.large

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
