pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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
    // The ordered plan the confirmation shows and the apply runs. Built through the pure
    // `Actions.applyPlan`, so the order that reaches the shell is the order the user confirmed.
    readonly property var plan: Actions.applyPlan(root.targets, { flakePath: GlobalConfig.updates.flakePath })
    property var pendingSteps: []
    property bool confirming

    function buildTargets(): var {
        const actions = [];
        // The Nix branch: update the lock in-shell, then exactly one rebuild, chosen by the tool that
        // is actually installed. Detection already selected this branch by tool presence.
        if (Updates.nixStale) {
            actions.push("nixFlakeUpdate");
            if (Updates.hasNixosRebuild)
                actions.push("nixosRebuild");
            else if (Updates.hasHomeManager)
                actions.push("homeManager");
            return actions;
        }
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

    // Runs the ordered plan the popout built through the pure `Actions.applyPlan`. Reached only from
    // the Apply button in the confirmation panel, never from a binding or on load.
    function applyUpdates(): void {
        root.confirming = false;
        root.runPlan(root.plan);
    }

    function runPlan(plan): void {
        if (plan.length === 0)
            return;
        if (!plan[0].needsTerminal) {
            // No privileges and no interaction needed: run it in the shell and wait for it before the
            // next step (S6). A non-zero exit stops the sequence instead of letting a rebuild race the
            // lock the update was meant to replace (L19).
            root.pendingSteps = plan.slice(1);
            inShellStep.command = ["sh", "-c", Actions.shellCommand(plan[0])];
            inShellStep.running = true;
            return;
        }
        root.runTerminalSteps(plan);
    }

    function runTerminalSteps(plan): void {
        if (plan.length === 0)
            return;
        // Every step is privileged or interactive, so chain them into one terminal in order (S6, S7):
        // one window, the whole log visible, and never two pacman transactions at once (L19).
        Quickshell.execDetached(Actions.terminalScript(root.terminal, Actions.chainCommands(plan), true));
    }

    implicitWidth: Tokens.sizes.bar.audioWidth
    implicitHeight: layout.implicitHeight

    Process {
        id: inShellStep

        // The in-shell step finished: only a clean exit launches the terminal rebuild (L19).
        onExited: (exitCode, exitStatus) => { // qmllint disable signal-handler-parameters
            const steps = root.pendingSteps;
            root.pendingSteps = [];
            if (exitCode !== 0)
                return;
            root.runTerminalSteps(steps);
        }
    }

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
                    model: root.plan

                    StyledText {
                        required property var modelData

                        Layout.fillWidth: true
                        text: "$ " + modelData.argv.join(" ")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Privileged commands open in a terminal so the log stays visible")
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
