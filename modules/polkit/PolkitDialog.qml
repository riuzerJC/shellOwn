pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services

PanelWindow {
    id: root

    required property ShellScreen screen

    readonly property bool isAuthActive: PolkitAgent.active

    color: "transparent"
    visible: isAuthActive

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: isAuthActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Scrim Darkened Backdrop
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Colours.palette.m3scrim, 0.65)
        opacity: root.isAuthActive ? 1 : 0

        Behavior on opacity {
            Anim {
                type: Anim.Standard
            }
        }

        TapHandler {
            onTapped: PolkitAgent.cancel()
        }
    }

    // Centered Authentication Card
    StyledRect {
        id: dialogCard

        anchors.centerIn: parent
        implicitWidth: Math.min(480, root.width - Tokens.padding.large * 2)
        implicitHeight: contentLayout.implicitHeight + Tokens.padding.large * 2

        radius: Tokens.rounding.large
        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)
        border.width: 1
        border.color: Colours.tPalette.m3outlineVariant
        clip: true

        scale: root.isAuthActive ? 1 : 0.94
        opacity: root.isAuthActive ? 1 : 0

        Behavior on scale {
            Anim {
                type: Anim.DefaultSpatial
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.Standard
            }
        }

        ColumnLayout {
            id: contentLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            // Header: Lock icon + Title
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                StyledRect {
                    radius: Tokens.rounding.full
                    color: Colours.tPalette.m3primaryContainer
                    implicitWidth: 40
                    implicitHeight: 40

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "lock"
                        fontStyle: Tokens.font.icon.medium
                        color: Colours.tPalette.m3onPrimaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Authentication Required")
                        font: Tokens.font.title.builders.small.weight(Font.Bold).build()
                        color: Colours.tPalette.m3onSurface
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: PolkitAgent.identity ? Tr.tr("Authenticating as %1").arg(PolkitAgent.identity) : Tr.tr("Administrative privileges required")
                        font: Tokens.font.label.small
                        color: Colours.tPalette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
            }

            // Description Message
            StyledText {
                Layout.fillWidth: true
                text: PolkitAgent.message || Tr.tr("An application is attempting to perform an action that requires root authorization.")
                font: Tokens.font.body.medium
                color: Colours.tPalette.m3onSurface
                wrapMode: Text.WordWrap
            }

            // Action identifier badge
            StyledRect {
                visible: PolkitAgent.actionId.length > 0
                Layout.fillWidth: true
                radius: Tokens.rounding.small
                color: Colours.tPalette.m3surfaceContainerLow
                implicitHeight: actionText.implicitHeight + Tokens.padding.small * 2

                StyledText {
                    id: actionText

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    text: Tr.tr("Action: %1").arg(PolkitAgent.actionId)
                    font: Tokens.font.label.small
                    color: Colours.tPalette.m3outline
                    elide: Text.ElideMiddle
                }
            }

            // Password Field
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: PolkitAgent.prompt || Tr.tr("Password")
                    font: Tokens.font.label.medium
                    color: Colours.tPalette.m3onSurfaceVariant
                }

                StyledTextField {
                    id: passwordField

                    Layout.fillWidth: true
                    echoMode: PolkitAgent.echo ? TextInput.Normal : TextInput.Password
                    placeholderText: Tr.tr("Enter password…")
                    enabled: !PolkitAgent.isBusy
                    focus: root.isAuthActive

                    onAccepted: {
                        if (text.length > 0) {
                            PolkitAgent.submitResponse(text);
                            text = "";
                        }
                    }

                    Keys.onEscapePressed: PolkitAgent.cancel()

                    Connections {
                        function onActiveChanged(): void {
                            if (PolkitAgent.active) {
                                passwordField.text = "";
                                passwordField.forceActiveFocus();
                            }
                        }

                        target: PolkitAgent
                    }
                }
            }

            // Error feedback
            StyledText {
                visible: PolkitAgent.error.length > 0
                Layout.fillWidth: true
                text: PolkitAgent.error
                font: Tokens.font.label.small
                color: Colours.tPalette.m3error
                wrapMode: Text.WordWrap
            }

            // Bottom Actions: Cancel & Authenticate
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                spacing: Tokens.spacing.medium

                Item {
                    Layout.fillWidth: true
                }

                // Cancel Button
                StyledRect {
                    radius: Tokens.rounding.full
                    color: cancelHover.hovered ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainerHigh
                    implicitWidth: cancelLabel.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: 36

                    StyledText {
                        id: cancelLabel

                        anchors.centerIn: parent
                        text: Tr.tr("Cancel")
                        font: Tokens.font.label.large
                        color: Colours.tPalette.m3onSurface
                    }

                    HoverHandler {
                        id: cancelHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: PolkitAgent.cancel()
                    }
                }

                // Authenticate Button
                StyledRect {
                    radius: Tokens.rounding.full
                    color: authHover.hovered ? Colours.tPalette.m3primary : Colours.tPalette.m3primary
                    opacity: authHover.hovered ? 0.9 : 1.0
                    implicitWidth: authRow.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: 36

                    RowLayout {
                        id: authRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.small

                        CircularIndicator {
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 16
                            running: PolkitAgent.isBusy
                            visible: PolkitAgent.isBusy
                        }

                        StyledText {
                            text: Tr.tr("Authenticate")
                            font: Tokens.font.label.large
                            color: Colours.tPalette.m3onPrimary
                        }
                    }

                    HoverHandler {
                        id: authHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: {
                            if (passwordField.text.length > 0) {
                                PolkitAgent.submitResponse(passwordField.text);
                                passwordField.text = "";
                            }
                        }
                    }
                }
            }
        }
    }
}
