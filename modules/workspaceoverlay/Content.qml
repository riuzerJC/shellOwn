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
    required property ScreenState screenState

    readonly property bool perMonitorWorkspaces: GlobalConfig.bar.workspaces.perMonitorWorkspaces
    readonly property var monitor: Hypr.monitorFor(screen)
    readonly property var workspaceGroups: WorkspaceModel.collectWorkspaces(Hypr.workspaces.values, monitor, perMonitorWorkspaces)
    readonly property var windowsByWorkspace: WorkspaceModel.groupWindowsByWorkspace(Hypr.toplevels.values, workspaceGroups)
    readonly property int shownCount: 10
    readonly property int sectionColumns: 5
    readonly property int sectionPadding: Tokens.padding.medium
    readonly property int sectionGap: Tokens.spacing.medium
    readonly property int sectionHeaderHeight: 36
    readonly property int targetHeight: 176
    readonly property int targetColumnGap: Tokens.spacing.small
    readonly property int targetRowGap: Tokens.spacing.small
    readonly property int targetWidth: Math.max(160, Math.floor((implicitWidth - Tokens.padding.large * 2 - sectionPadding * 2 - targetColumnGap * (sectionColumns - 1)) / sectionColumns))
    readonly property int normalSectionRows: 2
    readonly property int specialSectionRows: 1
    readonly property int normalSectionHeight: sectionHeightForRows(normalSectionRows)
    readonly property int specialSectionHeight: sectionHeightForRows(specialSectionRows)
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

    function sectionHeightForRows(rowCount: int): int {
        return sectionPadding * 2 + sectionHeaderHeight + sectionGap + targetHeight * rowCount + targetRowGap * Math.max(0, rowCount - 1);
    }

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

    color: Colours.tPalette.m3surfaceContainerLow
    border.width: 1
    border.color: Colours.tPalette.m3outlineVariant
    radius: Tokens.rounding.extraLarge
    implicitWidth: Math.min(screen.width - Tokens.padding.large * 2, 1360)
    implicitHeight: Math.min(screen.height - Tokens.padding.large * 2, normalSectionHeight + specialSectionHeight + sectionGap + Tokens.padding.large * 2)

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
        anchors.margins: Tokens.padding.large
        spacing: root.sectionGap

        StyledRect {
            id: normalContainer

            Layout.fillWidth: true
            Layout.minimumHeight: root.normalSectionHeight
            Layout.preferredHeight: root.normalSectionHeight

            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer
            border.width: 1
            border.color: Colours.tPalette.m3outlineVariant

            ColumnLayout {
                id: normalSection

                anchors.fill: parent
                anchors.margins: root.sectionPadding
                spacing: root.sectionGap

                StyledText {
                    text: qsTr("Workspaces")
                    font: Tokens.font.title.builders.small.weight(Font.Medium).build()
                    color: Colours.tPalette.m3onSurface
                    Layout.fillWidth: true
                    Layout.topMargin: root.sectionPadding / 2
                    Layout.bottomMargin: Tokens.spacing.extraSmall
                    elide: Text.ElideRight
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: root.sectionColumns
                    columnSpacing: root.targetColumnGap
                    rowSpacing: root.targetRowGap
                    uniformCellWidths: true
                    uniformCellHeights: true

                    Repeater {
                        model: root.normalWorkspaces.slice(0, 10)

                        WorkspaceTarget {
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: root.targetWidth
                            Layout.preferredHeight: root.targetHeight
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
            Layout.minimumHeight: root.specialSectionHeight
            Layout.preferredHeight: root.specialSectionHeight

            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer
            border.width: 1
            border.color: Colours.tPalette.m3outlineVariant

            ColumnLayout {
                id: specialSection

                anchors.fill: parent
                anchors.margins: root.sectionPadding
                spacing: root.sectionGap

                StyledText {
                    text: qsTr("Special workspaces")
                    font: Tokens.font.title.builders.small.weight(Font.Medium).build()
                    color: Colours.tPalette.m3onSurface
                    Layout.fillWidth: true
                    Layout.topMargin: root.sectionPadding / 2
                    Layout.bottomMargin: Tokens.spacing.extraSmall
                    elide: Text.ElideRight
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: root.sectionColumns
                    columnSpacing: root.targetColumnGap
                    rowSpacing: root.targetRowGap
                    uniformCellWidths: true
                    uniformCellHeights: true

                    Repeater {
                        model: root.specialWorkspaces.slice(0, 5)

                        WorkspaceTarget {
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: root.targetWidth
                            Layout.preferredHeight: root.targetHeight
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
