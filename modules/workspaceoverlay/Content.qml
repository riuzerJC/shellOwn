pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import "WorkspaceModel.js" as WorkspaceModel

StyledRect {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities

    readonly property bool perMonitorWorkspaces: GlobalConfig.bar.workspaces.perMonitorWorkspaces
    readonly property var monitor: Hypr.monitorFor(screen)
    readonly property var workspaceGroups: WorkspaceModel.collectWorkspaces(Hypr.workspaces.values, monitor, perMonitorWorkspaces)
    readonly property var windowsByWorkspace: WorkspaceModel.groupWindowsByWorkspace(Hypr.toplevels.values, workspaceGroups)
    readonly property int shownCount: 10
    readonly property int maxExistingWorkspaceId: {
        let maxId = 0;
        for (const ws of workspaceGroups.normal)
            maxId = Math.max(maxId, Number(ws?.id ?? 0));
        return maxId;
    }
    readonly property int normalWorkspaceTargetCount: Math.max(shownCount, maxExistingWorkspaceId + 1)
    readonly property var normalWorkspaceById: {
        const map = ({});
        for (const ws of workspaceGroups.normal) {
            const id = Number(ws?.id ?? 0);
            if (id > 0)
                map[id] = ws;
        }
        return map;
    }
    readonly property var normalWorkspaces: Array.from({
            length: normalWorkspaceTargetCount
        }, (_, index) => {
            const id = index + 1;
            return normalWorkspaceById[id] ?? {
                id,
                name: String(id),
                monitor
            };
        })
    readonly property int specialShownCount: 5
    readonly property var defaultSpecialTargets: ["special:music", "special:chat", "special:term", "special:files", "special:misc"]
    readonly property var specialPreferredNames: {
        const configured = Config.workspaceOverlay?.specialTargets;
        if (Array.isArray(configured) && configured.length > 0) {
            return configured.map(name => {
                const normalized = String(name ?? "").trim();
                if (!normalized)
                    return "";
                return normalized.startsWith("special:") ? normalized : `special:${normalized}`;
            }).filter(Boolean);
        }
        return defaultSpecialTargets;
    }
    readonly property var specialWorkspaceByName: {
        const map = ({});
        for (const ws of workspaceGroups.special) {
            const name = String(ws?.name ?? "");
            if (name)
                map[name] = ws;
        }
        return map;
    }
    readonly property var specialWorkspaceNames: {
        const existing = Object.keys(specialWorkspaceByName).sort((a, b) => a.localeCompare(b));
        const names = [...specialPreferredNames];
        for (const name of existing) {
            if (!names.includes(name))
                names.push(name);
        }
        for (let i = 1; names.length < specialShownCount; i++) {
            const candidate = `special:slot${i}`;
            if (!specialWorkspaceByName[candidate])
                names.push(candidate);
        }
        return names;
    }
    readonly property var specialWorkspaces: specialWorkspaceNames.map(name => specialWorkspaceByName[name] ?? {
            id: -1,
            name,
            monitor
        })

    // Policy decision (Task 1.4):
    // - Overlay follows fullscreen gating (blocked when fullscreen in Shortcuts/Ipc toggle)
    // - Rendering scope follows perMonitorWorkspaces for parity with bar workspace UI

    property var inFlightByAddress: ({})
    property var hoveredTarget: null
    readonly property int moveTimeoutMs: 1500

    function isValidAddress(address: string): bool {
        return Hypr.normalizeWindowAddress(address).length > 0;
    }

    function clearInFlight(address: string): void {
        if (!inFlightByAddress[address])
            return;
        const next = Object.assign({}, inFlightByAddress);
        delete next[address];
        inFlightByAddress = next;
    }

    function markInFlight(payload: var, target: var): void {
        const normalized = Hypr.normalizeWindowAddress(payload.address);
        if (!normalized)
            return;

        const next = Object.assign({}, inFlightByAddress);
        next[normalized] = {
            targetToken: target.targetToken,
            startedAt: Date.now()
        };
        inFlightByAddress = next;
        reconcileTimer.restart();
    }

    function warnMoveFailure(address: string): void {
        Toaster.toast(qsTr("Workspace move pending"), qsTr("Could not confirm move for 0x%1 yet. State was refreshed.").arg(address), "warning");
    }

    function onDropWindow(payload: var, target: var): void {
        const normalizedAddress = Hypr.normalizeWindowAddress(payload.address);
        if (!normalizedAddress)
            return;

        if (!target?.targetToken)
            return;

        if (payload.sourceToken === target.targetToken)
            return;

        markInFlight(payload, target);

        const moved = Hypr.moveWindowToWorkspace(normalizedAddress, {
            kind: target.kind,
            id: target.id,
            name: target.name
        });

        if (!moved) {
            clearInFlight(normalizedAddress);
            Toaster.toast(qsTr("Invalid move target"), qsTr("The selected workspace target is not valid."), "warning");
            return;
        }

        reconcileTimer.restart();
    }

    function commitDraggedWindow(payload: var, target: var): void {
        hoveredTarget = null;
        if (!payload || !target)
            return;

        onDropWindow(payload, target);
    }

    function reconcileInFlight(): void {
        const pendingAddresses = Object.keys(inFlightByAddress);
        if (pendingAddresses.length === 0) {
            reconcileTimer.stop();
            return;
        }

        const now = Date.now();
        const next = Object.assign({}, inFlightByAddress);

        for (const address of pendingAddresses) {
            const entry = inFlightByAddress[address];
            const toplevel = Hypr.toplevels.values.find(t => Hypr.normalizeWindowAddress(t?.address) === address);
            const currentToken = WorkspaceModel.workspaceTokenFromWindow(toplevel);

            if (currentToken && currentToken === entry.targetToken) {
                delete next[address];
                continue;
            }

            if (now - entry.startedAt >= moveTimeoutMs) {
                delete next[address];
                Hypr.forceRefreshState();
                warnMoveFailure(address);
            }
        }

        inFlightByAddress = next;

        if (Object.keys(inFlightByAddress).length === 0)
            reconcileTimer.stop();
    }

    // Glass test: keep root fully transparent so section glass is visible
    color: "transparent"
    border.width: 1
    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.35)
    radius: Tokens.rounding.large
    implicitWidth: Math.min(screen.width - Tokens.padding.large * 2, 1360)
    implicitHeight: Math.min(screen.height - Tokens.padding.large * 2, layoutRoot.implicitHeight + Tokens.padding.normal * 2)

    Component.onCompleted: Hypr.forceRefreshState()

    Timer {
        id: reconcileTimer

        interval: 200
        repeat: true
        running: false
        onTriggered: root.reconcileInFlight()
    }

    ColumnLayout {
        id: layoutRoot

        anchors.fill: parent
        anchors.margins: Tokens.padding.normal
        anchors.topMargin: 10
        spacing: 6

        StyledRect {
            id: normalContainer

            Layout.fillWidth: true
            Layout.preferredHeight: normalSection.implicitHeight + 8

            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainerHigh
            border.width: 1
            border.color: Colours.tPalette.m3outlineVariant

            ColumnLayout {
                id: normalSection

                anchors.fill: parent
                anchors.margins: Tokens.padding.normal
                anchors.topMargin: 2
                spacing: Tokens.spacing.small

                StyledText {
                    text: qsTr("Workspaces")
                    font.pointSize: Tokens.font.size.normal
                    font.weight: 600
                    color: Colours.tPalette.m3onSurface
                    Layout.leftMargin: 6
                    Layout.topMargin: 10
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 5
                    columnSpacing: 6
                    rowSpacing: 6

                    Repeater {
                        model: root.normalWorkspaces.slice(0, 10)

                        WorkspaceTarget {
                            required property var modelData

                            Layout.preferredWidth: 259
                            Layout.preferredHeight: 170
                            workspace: modelData
                            kind: "normal"
                            windows: root.windowsByWorkspace[String(modelData.id)] ?? []
                            inFlightByAddress: root.inFlightByAddress
                            hoveredTarget: root.hoveredTarget
                            setHoveredTarget: target => root.hoveredTarget = target
                            clearHoveredTarget: targetToken => {
                                if (root.hoveredTarget?.targetToken === targetToken)
                                    root.hoveredTarget = null;
                            }
                            onDragCommit: root.commitDraggedWindow
                        }
                    }
                }
            }
        }

        StyledRect {
            id: specialContainer

            Layout.fillWidth: true
            Layout.preferredHeight: specialSection.implicitHeight + 8

            radius: Tokens.rounding.large
            // Glass look relies on compositor blur + low-alpha surface
            color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.42)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.65)

            ColumnLayout {
                id: specialSection

                anchors.fill: parent
                anchors.margins: Tokens.padding.normal
                anchors.topMargin: 2
                spacing: Tokens.spacing.small

                StyledText {
                    text: qsTr("Special workspaces")
                    font.pointSize: Tokens.font.size.normal
                    font.weight: 600
                    color: Colours.tPalette.m3onSurface
                    Layout.leftMargin: 6
                    Layout.topMargin: 10
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 5
                    columnSpacing: 6
                    rowSpacing: 6

                    Repeater {
                        model: root.specialWorkspaces.slice(0, 5)

                        WorkspaceTarget {
                            required property var modelData

                            Layout.preferredWidth: 259
                            Layout.preferredHeight: 170
                            workspace: modelData
                            kind: "special"
                            windows: root.windowsByWorkspace[modelData.name] ?? []
                            inFlightByAddress: root.inFlightByAddress
                            hoveredTarget: root.hoveredTarget
                            setHoveredTarget: target => root.hoveredTarget = target
                            clearHoveredTarget: targetToken => {
                                if (root.hoveredTarget?.targetToken === targetToken)
                                    root.hoveredTarget = null;
                            }
                            onDragCommit: root.commitDraggedWindow
                        }
                    }
                }
            }
        }
    }
}
