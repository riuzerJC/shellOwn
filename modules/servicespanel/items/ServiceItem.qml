pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.servicespanel.core

StyledRect {
    id: root

    required property var modelData
    required property var list

    readonly property bool isRunning: modelData?.state === "running"
    readonly property bool isStopped: modelData?.state === "stopped"
    readonly property bool isFailed: modelData?.state === "failed"
    readonly property bool isBusy: modelData?.busy ?? false

    function stateLabel(state: string): string {
        if (state === "running")
            return Tr.tr("Running");
        if (state === "stopped")
            return Tr.tr("Stopped");
        if (state === "failed")
            return Tr.tr("Failed");
        return Tr.tr("Checking…");
    }

    function stateColor(state: string): color {
        if (state === "running")
            return Colours.tPalette.m3primaryContainer;
        if (state === "failed")
            return Colours.tPalette.m3errorContainer;
        if (state === "stopped")
            return Colours.tPalette.m3surfaceContainerHigh;
        return Colours.tPalette.m3surfaceContainerLowest;
    }

    function stateTextColor(state: string): color {
        if (state === "running")
            return Colours.tPalette.m3onPrimaryContainer;
        if (state === "failed")
            return Colours.tPalette.m3onErrorContainer;
        if (state === "stopped")
            return Colours.tPalette.m3onSurfaceVariant;
        return Colours.tPalette.m3outline;
    }

    function triggerPrimaryAction(): void {
        if (root.isBusy)
            return;

        if (root.isRunning && (root.modelData?.capabilities?.stop ?? false))
            ServiceOrchestrator.stopServiceById(root.modelData.id);
        else
            ServiceOrchestrator.startServiceById(root.modelData?.id ?? "");
    }

    radius: Tokens.rounding.medium
    color: hoverHandler.hovered ? Colours.tPalette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainer
    border.width: 1
    border.color: isRunning ? Colours.tPalette.m3primary : (isFailed ? Colours.tPalette.m3error : Colours.tPalette.m3outlineVariant)
    implicitHeight: 64
    anchors.left: parent?.left
    anchors.right: parent?.right

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
    }

    FontLoader {
        id: nerdFontLoader

        source: "file:///usr/share/fonts/TTF/CaskaydiaCoveNerdFont-Regular.ttf"
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        // Left Icon
        Item {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32

            MaterialIcon {
                anchors.centerIn: parent
                visible: root.modelData?.iconFont !== "nerd"
                text: root.modelData?.icon ?? "deployed_code"
                fontStyle: Tokens.font.icon.extraLarge
                color: root.isRunning ? Colours.tPalette.m3primary : Colours.tPalette.m3onSurface
            }

            Loader {
                anchors.centerIn: parent
                active: root.modelData?.iconFont === "nerd"
                visible: active

                sourceComponent: Text {
                    text: root.modelData?.icon ?? ""
                    font.family: nerdFontLoader.name
                    font.pointSize: 24
                    color: root.isRunning ? Colours.tPalette.m3primary : Colours.tPalette.m3onSurface
                    renderType: Text.NativeRendering
                }
            }
        }

        // Center Information (Title + Description)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: root.modelData?.name ?? ""
                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                color: Colours.tPalette.m3onSurface
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: root.modelData?.lastError?.length > 0 ? root.modelData.lastError : (root.modelData?.description ?? "")
                font: Tokens.font.label.small
                color: root.modelData?.lastError?.length > 0 ? Colours.tPalette.m3error : Colours.tPalette.m3onSurfaceVariant
                elide: Text.ElideRight
            }
        }

        // Right Controls: State Badge + Action Buttons
        RowLayout {
            spacing: Tokens.spacing.small

            // State Badge Pill
            StyledRect {
                radius: Tokens.rounding.full
                color: root.stateColor(root.modelData?.state ?? "unknown")
                implicitWidth: stateText.implicitWidth + Tokens.padding.small * 2 + 8
                implicitHeight: 22

                StyledText {
                    id: stateText

                    anchors.centerIn: parent
                    text: root.stateLabel(root.modelData?.state ?? "unknown")
                    color: root.stateTextColor(root.modelData?.state ?? "unknown")
                    font: Tokens.font.label.small
                }
            }

            // Quick Play/Stop Action Button
            StyledRect {
                radius: Tokens.rounding.full
                color: actionHover.hovered ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainerLow
                implicitWidth: 32
                implicitHeight: 32
                visible: !root.isBusy

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.isRunning ? "stop" : "play_arrow"
                    fontStyle: Tokens.font.icon.medium
                    color: root.isRunning ? Colours.tPalette.m3error : Colours.tPalette.m3primary
                }

                HoverHandler {
                    id: actionHover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: root.triggerPrimaryAction()
                }
            }

            // Refresh Single Service Icon
            StyledRect {
                radius: Tokens.rounding.full
                color: refreshHover.hovered ? Colours.tPalette.m3surfaceContainerHighest : "transparent"
                implicitWidth: 28
                implicitHeight: 28
                visible: !root.isBusy

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "refresh"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.tPalette.m3onSurfaceVariant
                }

                HoverHandler {
                    id: refreshHover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: ServiceOrchestrator.probeServiceById(root.modelData?.id ?? "")
                }
            }

            CircularIndicator {
                implicitWidth: 20
                implicitHeight: 20
                running: root.isBusy
                visible: root.isBusy
            }
        }
    }
}
