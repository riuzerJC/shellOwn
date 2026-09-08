pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    readonly property real cardWidth: Tokens.sizes.dashboard.perfHeroCardWidth
    readonly property real paneWidth: cardWidth * 2 + Tokens.spacing.large
    property int view: 0 // 0 = usage, 1 = accounts
    property string keyEditingFor: "" // provider id with inline API-key editor open

    implicitWidth: paneWidth
    implicitHeight: column.implicitHeight

    Component.onCompleted: CodexBar.reload()

    ColumnLayout {
        id: column

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Subscriptions")
                font: Tokens.font.title.medium
                color: Colours.palette.m3onSurface
            }

            StyledText {
                visible: CodexBar.lastUpdated.getTime() > 0
                text: visible ? qsTr("Updated %1").arg(Qt.formatDateTime(CodexBar.lastUpdated, "hh:mm")) : ""
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }

            IconButton {
                icon: "refresh"
                enabled: !CodexBar.fetching
                onClicked: CodexBar.reload()
            }
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Colours.palette.m3outlineVariant
        }

        RowLayout {
            spacing: Tokens.spacing.small

            TextButton {
                text: qsTr("Usage")
                isToggle: true
                checked: root.view === 0
                onClicked: root.view = 0
            }

            TextButton {
                text: qsTr("Accounts")
                isToggle: true
                checked: root.view === 1
                onClicked: root.view = 1
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: !CodexBar.available
            text: qsTr("CodexBar not found (install the codexbar CLI)")
            font: Tokens.font.body.small
            color: Colours.palette.m3error
            wrapMode: Text.WordWrap
        }

        // Usage view — 2-column grid, authenticated providers only
        GridLayout {
            Layout.fillWidth: true
            visible: root.view === 0 && CodexBar.available
            columns: 2
            columnSpacing: Tokens.spacing.large
            rowSpacing: Tokens.spacing.medium

            StyledText {
                Layout.fillWidth: true
                Layout.columnSpan: 2
                visible: root.view === 0 && CodexBar.available && CodexBar.fetching && CodexBar.providers.length === 0
                text: qsTr("Loading subscriptions...")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                Layout.columnSpan: 2
                visible: root.view === 0 && CodexBar.available && !CodexBar.fetching && CodexBar.providers.every(p => p.state !== "ok")
                text: qsTr("No authenticated subscriptions — see the Accounts view")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: CodexBar.providers.filter(p => p.state === "ok")

                delegate: StyledRect {
                    id: card

                    required property var modelData

                    readonly property bool failed: modelData.state !== "ok"
                    readonly property bool authFailed: modelData.state === "authError"

                    Layout.preferredWidth: root.cardWidth
                    implicitHeight: content.implicitHeight + Tokens.padding.large * 2

                    color: Colours.tPalette.m3surfaceContainer
                    radius: Tokens.rounding.medium
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    ColumnLayout {
                        id: content

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.large
                        spacing: Tokens.spacing.small

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                text: card.failed ? (card.authFailed ? "lock_clock" : "error") : "subscriptions"
                                color: card.failed ? (card.authFailed ? Colours.palette.m3tertiary : Colours.palette.m3error) : Colours.palette.m3primary
                                fontStyle: Tokens.font.icon.medium
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: card.modelData.name
                                    font: Tokens.font.title.small
                                    color: Colours.palette.m3onSurface
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: card.modelData.accountEmail.length > 0
                                    text: card.modelData.accountEmail
                                    font: Tokens.font.body.small
                                    color: Colours.palette.m3onSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }

                            // plan / state chip
                            StyledRect {
                                visible: card.modelData.plan.length > 0 || (card.failed && card.authFailed)
                                radius: Tokens.rounding.full
                                implicitWidth: chipLabel.implicitWidth + Tokens.padding.medium * 2
                                implicitHeight: chipLabel.implicitHeight + Tokens.padding.extraSmall

                                color: card.failed ? Colours.tPalette.m3tertiaryContainer : Colours.tPalette.m3secondaryContainer

                                StyledText {
                                    id: chipLabel

                                    anchors.centerIn: parent
                                    text: card.failed ? qsTr("Auth") : card.modelData.plan
                                    font: Tokens.font.label.small
                                    color: card.failed ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSecondaryContainer
                                }
                            }
                        }

                        // Auth error banner
                        StyledRect {
                            Layout.fillWidth: true
                            visible: card.failed
                            implicitHeight: banner.implicitHeight + Tokens.padding.medium * 2
                            radius: Tokens.rounding.small

                            color: card.authFailed ? Colours.tPalette.m3tertiaryContainer : Colours.tPalette.m3errorContainer

                            RowLayout {
                                id: banner

                                anchors.fill: parent
                                anchors.margins: Tokens.padding.medium
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: card.authFailed ? "key_off" : "info"
                                    color: card.authFailed ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onErrorContainer
                                    fontStyle: Tokens.font.icon.small
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: card.modelData.errorText
                                    font: Tokens.font.body.small
                                    color: card.authFailed ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onErrorContainer
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                }

                                IconTextButton {
                                    visible: card.authFailed
                                    icon: "autorenew"
                                    text: qsTr("Renew")
                                    onClicked: CodexBar.renew(card.modelData.id)
                                }
                            }
                        }

                        // Usage bars
                        Repeater {
                            model: [{
                                    "window": card.modelData.primary,
                                    "isPrimary": true
                                }, {
                                    "window": card.modelData.secondary,
                                    "isPrimary": false
                                }].filter(e => e.window)

                            delegate: ColumnLayout {
                                required property var modelData

                                readonly property var win: modelData.window

                                Layout.fillWidth: true
                                spacing: Tokens.spacing.extraSmall

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.spacing.extraSmall

                                    MaterialIcon {
                                        text: win.isPrimary ? "schedule" : "date_range"
                                        color: Colours.palette.m3onSurfaceVariant
                                        fontStyle: Tokens.font.icon.small
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: `${Math.round(win.usedPercent)}%`
                                        font: Tokens.font.label.medium
                                        color: Colours.palette.m3onSurface
                                    }

                                    StyledText {
                                        visible: win.resetsAt.length > 0
                                        text: visible ? Qt.formatDateTime(new Date(win.resetsAt), "ddd hh:mm") : ""
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3onSurfaceVariant
                                    }
                                }

                                StyledProgressBar {
                                    Layout.fillWidth: true
                                    implicitHeight: Tokens.padding.small
                                    value: win.usedPercent / 100
                                    fgColour: win.usedPercent >= 80 ? Colours.palette.m3error : Colours.palette.m3primary
                                }
                            }
                        }

                        // Credits + pace footer
                        RowLayout {
                            Layout.fillWidth: true
                            visible: card.modelData.credits !== null || card.modelData.pace.length > 0
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                visible: card.modelData.credits !== null
                                text: "toll"
                                color: Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.small
                            }

                            StyledText {
                                visible: card.modelData.credits !== null
                                text: visible ? qsTr("%1 credits").arg(card.modelData.credits) : ""
                                font: Tokens.font.label.medium
                                color: Colours.palette.m3onSurfaceVariant
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: card.modelData.pace.length > 0
                                text: card.modelData.pace
                                horizontalAlignment: Text.AlignRight
                                font: Tokens.font.label.small
                                color: Colours.palette.m3onSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        // Accounts view
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.view === 1 && CodexBar.available
            spacing: Tokens.spacing.medium

            Repeater {
                model: CodexBar.providers

                delegate: StyledRect {
                    id: accountRow

                    required property var modelData
                    property string keyResult: ""

                    Layout.fillWidth: true
                    implicitHeight: rowContent.implicitHeight + Tokens.padding.large * 2

                    color: Colours.tPalette.m3surfaceContainer
                    radius: Tokens.rounding.medium
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    ColumnLayout {
                        id: rowContent

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.large
                        spacing: Tokens.spacing.small

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                text: accountRow.modelData.state === "ok" ? "check_circle" : accountRow.modelData.state === "authError" ? "lock_clock" : "error"
                                color: accountRow.modelData.state === "ok" ? Colours.palette.m3primary : accountRow.modelData.state === "authError" ? Colours.palette.m3tertiary : Colours.palette.m3error
                                fontStyle: Tokens.font.icon.medium
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: accountRow.modelData.name
                                    font: Tokens.font.title.small
                                    color: Colours.palette.m3onSurface
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: accountRow.modelData.accountEmail.length > 0 ? accountRow.modelData.accountEmail : qsTr("No account signed in")
                                    font: Tokens.font.body.small
                                    color: Colours.palette.m3onSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }

                            IconButton {
                                visible: accountRow.modelData.authCommand.length > 0
                                icon: "autorenew"
                                onClicked: CodexBar.renew(accountRow.modelData.id)
                            }

                            IconButton {
                                icon: "key"
                                visible: CodexBar.supportsApiKey(accountRow.modelData.id)
                                checked: root.keyEditingFor === accountRow.modelData.id
                                isToggle: true
                                onClicked: root.keyEditingFor = root.keyEditingFor === accountRow.modelData.id ? "" : accountRow.modelData.id
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: accountRow.modelData.errorText.length > 0
                            text: accountRow.modelData.errorText
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        // Inline API-key editor (no dialog framework)
                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.keyEditingFor === accountRow.modelData.id
                            spacing: Tokens.spacing.small

                            StyledTextField {
                                id: keyField

                                Layout.fillWidth: true
                                placeholderText: qsTr("API key")
                                echoMode: TextInput.Password
                                emptyIsValid: false

                                onVisibleChanged: if (visible)
                                    forceActiveFocus()

                                // Explicit clipboard shortcuts: layer-shell surfaces don't always
                                // deliver TextField's built-in Control+V/X/C/A bindings.
                                Keys.onPressed: event => {
                                    if (!(event.modifiers & Qt.ControlModifier))
                                        return;
                                    if (event.key === Qt.Key_V) {
                                        keyField.paste();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_X) {
                                        keyField.cut();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_C) {
                                        keyField.copy();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_A) {
                                        keyField.selectAll();
                                        event.accepted = true;
                                    }
                                }

                                onAccepted: keyConfirm.clicked()

                                // Terminal-style paste: middle or right click
                                TapHandler {
                                    acceptedButtons: Qt.RightButton | Qt.MiddleButton
                                    onTapped: keyField.paste()
                                }
                            }

                            IconButton {
                                id: keyConfirm

                                icon: "check"
                                enabled: keyField.valid
                                onClicked: {
                                    CodexBar.setApiKey(accountRow.modelData.id, keyField.text, ok => {
                                        keyField.text = "";
                                        root.keyEditingFor = "";
                                        accountRow.keyResult = ok ? qsTr("API key updated") : qsTr("Failed to set API key");
                                        keyResultReset.restart();
                                    });
                                }
                            }

                            IconButton {
                                icon: "close"
                                onClicked: {
                                    keyField.text = "";
                                    root.keyEditingFor = "";
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: accountRow.keyResult.length > 0
                            text: accountRow.keyResult
                            font: Tokens.font.label.medium
                            color: accountRow.keyResult.startsWith(qsTr("Failed")) ? Colours.palette.m3error : Colours.palette.m3primary
                        }

                        Timer {
                            id: keyResultReset

                            interval: 4000
                            onTriggered: accountRow.keyResult = ""
                        }
                    }
                }
            }
        }
    }
}
