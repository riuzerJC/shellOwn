pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import "../../updates/core/Actions.js" as Actions

// The popout behind the `updates` bar entry (S1). It only lists what the detection service has
// already found; it never applies anything on its own. Applying is a deliberate, confirmed act whose
// commands are built by the pure `Actions.buildCommand` and run through a terminal when they are
// privileged or interactive, so the log stays visible (S6, S7).
Item {
    id: root

    readonly property string terminal: Actions.resolveTerminal(GlobalConfig.updates.terminal, Quickshell.env("TERMINAL"))
    readonly property bool checking: Updates.state === "checking"
    // Cap for the list so a stale local database (hundreds of rows) does not stretch the popout.
    readonly property int maxListHeight: 320
    readonly property var targets: root.buildTargets()
    readonly property var rows: root.buildRows()
    property bool confirming

    function buildTargets(): var {
        const actions = [];
        let hasActionableOfficial = false;
        for (let i = 0; i < Updates.official.length; ++i) {
            if (!Updates.official[i].ignored) {
                hasActionableOfficial = true;
                break;
            }
        }
        if (hasActionableOfficial)
            actions.push("pacman");
        if (Updates.aur.length > 0)
            actions.push("yay");
        return actions;
    }

    // Flattens the two groups into one list so the popout has a single scroll area, with a header row
    // introducing each group and ignored entries marked separately because they are not actionable.
    function buildRows(): var {
        const rows = [];
        if (Updates.official.length > 0) {
            rows.push({ kind: "header", label: Tr.tr("Official repositories"), count: Updates.official.length });
            for (let i = 0; i < Updates.official.length; ++i) {
                const entry = Updates.official[i];
                rows.push({ kind: "entry", name: entry.name, from: entry.from, to: entry.to, ignored: entry.ignored });
            }
        }
        if (Updates.aur.length > 0) {
            rows.push({ kind: "header", label: Tr.tr("AUR"), count: Updates.aur.length });
            for (let i = 0; i < Updates.aur.length; ++i) {
                const entry = Updates.aur[i];
                rows.push({ kind: "entry", name: entry.name, from: entry.from, to: entry.to, ignored: false });
            }
        }
        return rows;
    }

    function commandPreview(action): string {
        const command = Actions.buildCommand(action, { flakePath: GlobalConfig.updates.flakePath });
        return command ? command.argv.join(" ") : "";
    }

    function inShellScript(command): string {
        const parts = [];
        if (command.cwd)
            parts.push("cd " + Actions.shellQuote(command.cwd));
        parts.push(command.argv.map(arg => Actions.shellQuote(arg)).join(" "));
        return parts.join(" && ");
    }

    function applyUpdates(): void {
        const flakePath = GlobalConfig.updates.flakePath;
        for (let i = 0; i < root.targets.length; ++i) {
            const command = Actions.buildCommand(root.targets[i], { flakePath: flakePath });
            if (!command)
                continue;
            if (command.needsTerminal)
                // Privileged or interactive: a terminal keeps the confirmation prompt and the log
                // visible instead of running silently (S6, S7).
                Quickshell.execDetached(Actions.terminalCommand(root.terminal, command.argv, command.cwd, true));
            else
                // No privileges and no interaction needed: run it in the shell (S6).
                Quickshell.execDetached(["sh", "-c", root.inShellScript(command)]);
        }
        root.confirming = false;
    }

    implicitWidth: Tokens.sizes.bar.audioWidth
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("Updates")
                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
            }

            CircularIndicator {
                visible: root.checking
                running: root.checking
                implicitSize: Tokens.font.body.medium.pointSize * 2
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: {
                if (Updates.state === "error")
                    return Tr.tr("Could not check for updates");
                if (Updates.state === "idle" || root.checking)
                    return Tr.tr("Checking for updates...");
                if (Updates.actionableCount === 0)
                    return Updates.ignoredCount > 0 ? Tr.tr("Everything is up to date (ignored packages excluded)") : Tr.tr("Everything is up to date");
                return Tr.trN("%n actionable update", "%n actionable updates", Updates.actionableCount);
            }
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }

        StyledRect {
            visible: Updates.state === "error"
            Layout.fillWidth: true
            implicitHeight: errorColumn.implicitHeight + Tokens.padding.medium * 2
            color: Colours.tPalette.m3errorContainer
            radius: Tokens.rounding.large

            ColumnLayout {
                id: errorColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Could not check for updates")
                    color: Colours.palette.m3onErrorContainer
                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                }

                // Technical diagnostics from the service; shown as they are, never translated.
                StyledText {
                    Layout.fillWidth: true
                    text: Updates.error
                    color: Colours.palette.m3onErrorContainer
                    font: Tokens.font.body.small
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                TextButton {
                    Layout.alignment: Qt.AlignRight
                    text: Tr.tr("Retry")
                    type: TextButton.Text
                    onClicked: Updates.check()
                }
            }
        }

        ListView {
            id: list

            visible: root.rows.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, root.maxListHeight)
            clip: true
            spacing: Tokens.spacing.extraSmall
            boundsBehavior: Flickable.StopAtBounds

            model: ScriptModel {
                values: root.rows
            }

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: list
            }

            delegate: Item {
                id: row

                required property var modelData

                width: list.width
                implicitHeight: modelData.kind === "header" ? headerText.implicitHeight + Tokens.spacing.small : entryRow.implicitHeight

                StyledText {
                    id: headerText

                    visible: row.modelData.kind === "header"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: visible ? Tr.trN("%1 (%n)", "%1 (%n)", row.modelData.count).arg(row.modelData.label) : ""
                    color: Colours.palette.m3primary
                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                }

                RowLayout {
                    id: entryRow

                    visible: row.modelData.kind === "entry"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.kind === "entry" ? row.modelData.name : ""
                        color: row.modelData.ignored ? Colours.palette.m3outline : Colours.palette.m3onSurface
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: row.modelData.kind === "entry" ? row.modelData.from + " -> " + row.modelData.to : ""
                        color: row.modelData.ignored ? Colours.palette.m3outline : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }

                    StyledText {
                        visible: row.modelData.kind === "entry" && row.modelData.ignored
                        text: Tr.tr("ignored")
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.small
                    }
                }
            }
        }

        IconTextButton {
            Layout.fillWidth: true
            icon: "refresh"
            text: root.checking ? Tr.tr("Refreshing... (contacts the mirrors)") : Tr.tr("Refresh now (checkupdates)")
            disabled: root.checking
            onClicked: Updates.refresh()
        }

        StyledText {
            visible: root.checking
            Layout.fillWidth: true
            text: Tr.tr("The manual refresh talks to the mirrors, so it is slower than the instant check")
            color: Colours.palette.m3outline
            font: Tokens.font.body.small
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }

        IconTextButton {
            visible: !root.confirming && root.targets.length > 0
            Layout.fillWidth: true
            icon: "system_update_alt"
            // TRANSLATORS: opens a confirmation listing the exact commands before anything runs
            text: Tr.tr("Apply updates...")
            onClicked: root.confirming = true
        }

        StyledRect {
            visible: root.confirming
            Layout.fillWidth: true
            implicitHeight: confirmColumn.implicitHeight + Tokens.padding.medium * 2
            color: Colours.tPalette.m3surfaceContainer
            radius: Tokens.rounding.large

            ColumnLayout {
                id: confirmColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    // TRANSLATORS: confirmation heading shown above the exact commands
                    text: Tr.tr("Apply these updates?")
                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                }

                Repeater {
                    model: root.targets

                    StyledText {
                        required property string modelData

                        Layout.fillWidth: true
                        text: "$ " + root.commandPreview(modelData)
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Each command opens in a terminal so the log stays visible")
                    color: Colours.palette.m3outline
                    font: Tokens.font.body.small
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    Layout.topMargin: Tokens.spacing.small
                    spacing: Tokens.spacing.medium

                    TextButton {
                        text: Tr.trCtx("Cancel", "button")
                        type: TextButton.Text
                        onClicked: root.confirming = false
                    }

                    TextButton {
                        text: Tr.trCtx("Apply", "button")
                        type: TextButton.Text
                        onClicked: root.applyUpdates()
                    }
                }
            }
        }
    }
}
