pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.services
import qs.utils
import "./adapters" as Adapters

QtObject {
    id: root

    property list<QtObject> serviceEntries: []
    property bool panelVisible: false
    property bool periodicRefreshEnabled: true
    property int refreshIntervalMs: 3000
    property bool invalidConfigToastShown: false
    property bool deprecatedConfigToastShown: false
    property list<string> invalidDiagnostics: []
    property var fileMappings: []
    property string mappingFileError: ""

    property var simulatedMappings: undefined
    property var simulatedAdapters: undefined

    readonly property var adapterRegistry: root.buildAdapterRegistry()

    readonly property Timer verificationTimer: Timer {
        interval: 1500
        repeat: false

        property string actionName: ""
        property string successSuffix: ""
        property string verifyFailureSuffix: ""
        property int retries: 0
        property var targetEntry: null

        onTriggered: {
            if (!targetEntry || retries <= 0) {
                const verificationMessage = Tr.tr("Action finished but state verification failed after retries.");
                if (targetEntry) {
                    targetEntry.lastError = verificationMessage;
                    targetEntry.busy = false;
                }
                root.emitToast(Tr.tr("State verification failed"), verificationMessage, "error");
                return;
            }

            retries -= 1;
            root.probeEntry(targetEntry, {
                silent: true,
                allowBusy: true
            }, verifyResult => {
                const expectedState = actionName === "start" ? "running" : "stopped";
                if (verifyResult.ok && verifyResult.state === expectedState) {
                    targetEntry.busy = false;
                    targetEntry.lastError = "";
                    root.emitToast(Tr.tr("%1 %2").arg(targetEntry.name).arg(successSuffix), Tr.tr("Service status confirmed."), "check_circle");
                    return;
                }

                if (verifyResult.state !== expectedState && retries > 0) {
                    restart();
                } else {
                    targetEntry.busy = false;
                    const verificationMessage = verifyResult.message || Tr.tr("Action finished but state verification failed.");
                    targetEntry.lastError = verificationMessage;
                    root.emitToast(Tr.tr("%1 %2").arg(targetEntry.name).arg(verifyFailureSuffix), verificationMessage, "error");
                }
            });
        }
    }

    function setPanelVisible(active: bool): void {
        panelVisible = active;

        if (active)
            refreshVisible();
    }

    function transformSearch(search: string): string {
        return search.trim();
    }

    function emitToast(title: string, message: string, icon: string, toastType: var): void {
        const type = typeof toastType === "number" ? toastType : 0;
        if (typeof Toaster !== "undefined" && Toaster?.toast)
            Toaster.toast(title, message, icon, type, 4000);

        const urgency = type === Toast.Error ? "critical" : (type === Toast.Warning ? "normal" : "low");
        const proc = notifyProcessFactory.createObject(root, {
            cmdArgs: ["notify-send", "-a", "Caelestia Services", "-u", urgency, title, message]
        });
        if (proc) {
            proc.processFinished.connect(() => proc.destroy());
            Qt.callLater(() => {
                proc.command = proc.cmdArgs;
                proc.running = true;
            });
        }
    }

    component NotifyProcess: Process {
        property list<string> cmdArgs: []
        signal processFinished

        onExited: processFinished()
    }

    readonly property Component notifyProcessFactory: Component { NotifyProcess {} }

    function query(search: string): list<QtObject> {
        const filtered = serviceEntries.filter(entry => entry.enabled);
        const normalizedSearch = transformSearch(search).toLowerCase();

        if (!normalizedSearch)
            return filtered;

        return filtered.filter(entry => {
            const haystack = `${entry.id} ${entry.name} ${entry.description}`.toLowerCase();
            return haystack.includes(normalizedSearch);
        });
    }

    function setSimulationHooks(hooks: var): void {
        simulatedMappings = hooks?.mappings;
        simulatedAdapters = hooks?.adapters;
        reload();
    }

    function clearSimulationHooks(): void {
        simulatedMappings = undefined;
        simulatedAdapters = undefined;
        reload();
    }

    function refreshVisible(): void {
        for (const entry of serviceEntries)
            probeEntry(entry, {
                silent: true
            });
    }

    function probeServiceById(serviceId: string): void {
        const entry = findEntryById(serviceId);
        if (!entry)
            return;

        probeEntry(entry, {
            silent: false
        });
    }

    function startServiceById(serviceId: string): void {
        const entry = findEntryById(serviceId);
        if (!entry)
            return;

        startService(entry);
    }

    function stopServiceById(serviceId: string): void {
        const entry = findEntryById(serviceId);
        if (!entry)
            return;

        stopService(entry);
    }

    function restartServiceById(serviceId: string): void {
        const entry = findEntryById(serviceId);
        if (!entry)
            return;

        if (entry.busy)
            return;

        if (!(entry.capabilities?.restart ?? true)) {
            emitToast(Tr.tr("%1 cannot be restarted").arg(entry.name), Tr.tr("This service mapping does not support restart."), "warning");
            return;
        }

        if (entry.probeInFlight) {
            emitToast(Tr.tr("%1 is busy").arg(entry.name), Tr.tr("A status refresh is in progress. Please try again."), "schedule");
            return;
        }

        const adapterAction = entry.adapterRef?.restart;
        if (typeof adapterAction !== "function") {
            emitToast(Tr.tr("Failed to restart %1").arg(entry.name), Tr.tr("Adapter contract error."), "error");
            return;
        }

        entry.busy = true;
        entry.actionToken += 1;
        const currentActionToken = entry.actionToken;

        // restart goes through the adapter's runCommand, so it inherits the start watchdog and the
        // 10 s run timeout: a hung pkexec prompt still resolves instead of leaving the card spinning.
        adapterAction.call(entry.adapterRef, entry.mappingRef, rawActionResult => {
            if (currentActionToken !== entry.actionToken)
                return;

            const actionResult = normalizeActionResult(entry, rawActionResult);
            if (!actionResult.ok) {
                entry.busy = false;
                entry.lastError = actionResult.message;
                emitToast(Tr.tr("Failed to restart %1").arg(entry.name), actionResult.message, "error", Toast.Error);
                return;
            }

            Qt.callLater(() => {
                probeEntry(entry, {
                    silent: true,
                    allowBusy: true
                }, verifyResult => {
                    entry.busy = false;

                    if (verifyResult.ok && verifyResult.state === "running") {
                        entry.lastError = "";
                        emitToast(Tr.tr("%1 Restarted").arg(entry.name), Tr.tr("Service is running again."), "restart_alt", Toast.Success);
                        return;
                    }

                    const verificationMessage = verifyResult.message || Tr.tr("Action finished but state verification failed.");
                    entry.lastError = verificationMessage;
                    emitToast(Tr.tr("%1 restart not confirmed").arg(entry.name), verificationMessage, "error");
                });
            });
        });
    }

    function setAutostartById(serviceId: string, enabled: bool): void {
        const entry = findEntryById(serviceId);
        if (!entry)
            return;

        if (entry.busy)
            return;

        if (!(entry.capabilities?.autostart ?? true)) {
            emitToast(Tr.tr("%1 cannot change autostart").arg(entry.name), Tr.tr("This service mapping does not support autostart."), "warning");
            return;
        }

        const adapterAction = entry.adapterRef?.setAutostart;
        if (typeof adapterAction !== "function") {
            emitToast(Tr.tr("Failed to update autostart for %1").arg(entry.name), Tr.tr("Adapter contract error."), "error");
            return;
        }

        entry.busy = true;
        entry.actionToken += 1;
        const currentActionToken = entry.actionToken;

        // setAutostart reuses the adapter's runCommand for the same watchdog coverage as the other
        // actions; enable/disable can block on a pkexec prompt just like start/stop.
        adapterAction.call(entry.adapterRef, entry.mappingRef, enabled, rawActionResult => {
            if (currentActionToken !== entry.actionToken)
                return;

            const actionResult = normalizeActionResult(entry, rawActionResult);
            if (!actionResult.ok) {
                entry.busy = false;
                entry.lastError = actionResult.message;
                emitToast(Tr.tr("Failed to update autostart for %1").arg(entry.name), actionResult.message, "error", Toast.Error);
                return;
            }

            // Re-probe so the card's autostart badge reflects the unit-file state the action changed.
            Qt.callLater(() => {
                probeEntry(entry, {
                    silent: true,
                    allowBusy: true
                }, verifyResult => {
                    entry.busy = false;

                    if (verifyResult.ok && verifyResult.autostart === enabled) {
                        entry.lastError = "";
                        emitToast(Tr.tr("%1 autostart %2").arg(entry.name).arg(enabled ? Tr.tr("enabled") : Tr.tr("disabled")), Tr.tr("Autostart setting confirmed."), "toggle_on", Toast.Success);
                        return;
                    }

                    const verificationMessage = verifyResult.message || Tr.tr("Action finished but autostart verification failed.");
                    entry.lastError = verificationMessage;
                    emitToast(Tr.tr("%1 autostart not confirmed").arg(entry.name), verificationMessage, "error");
                });
            });
        });
    }

    function openLogsById(serviceId: string): void {
        const entry = findEntryById(serviceId);
        if (!entry)
            return;

        const logsBuilder = entry.adapterRef?.logsCommand;
        if (typeof logsBuilder !== "function") {
            emitToast(Tr.tr("Cannot open logs for %1").arg(entry.name), Tr.tr("Adapter contract error."), "error");
            return;
        }

        const logsCommand = logsBuilder.call(entry.adapterRef, entry.mappingRef);
        if (!Array.isArray(logsCommand) || logsCommand.length === 0) {
            emitToast(Tr.tr("Cannot open logs for %1").arg(entry.name), Tr.tr("No log command available."), "warning");
            return;
        }

        // The terminal comes from the shell's configured applications (general.apps.terminal); foot
        // is the terminal this machine runs, so it is the fallback when the config list is empty.
        const configuredTerminal = GlobalConfig.general.apps.terminal ?? [];
        const terminal = [...configuredTerminal];
        const launcher = terminal.length > 0 ? terminal : ["foot"];

        // Detached on purpose: a `-f` journal is a long-lived interactive viewer, so it must not go
        // through the adapters' runCommand (its 10 s timeout would kill it) and it never sets the
        // card's busy spinner. This is how the rest of the shell opens a terminal.
        Quickshell.execDetached([...launcher, ...logsCommand]);
    }

    function reload(): void {
        clearEntries();
        invalidDiagnostics = [];
        const nextEntries = [];

        if (mappingFileError.length > 0)
            registerInvalidDiagnostic(mappingFileError);

        for (const mapping of resolveMappings()) {
            const validation = validateMapping(mapping);
            if (!validation.ok) {
                registerInvalidDiagnostic(validation.message);
                continue;
            }

            const adapter = adapterRegistry[mapping.adapter];
            const adapterValidation = validateAdapter(mapping.id, adapter);
            if (!adapterValidation.ok) {
                registerInvalidDiagnostic(adapterValidation.message);
                continue;
            }

            nextEntries.push(serviceEntryFactory.createObject(root, {
                id: mapping.id,
                name: mapping.name,
                description: mapping.description ?? Tr.tr("No description"),
                icon: mapping.icon ?? "deployed_code",
                iconFont: normalizeIconFont(mapping.iconFont),
                adapterId: mapping.adapter,
                enabled: mapping.enabled ?? true,
                capabilities: Object.assign({
                    start: true,
                    stop: false,
                    // Restart and autostart default from the adapter. An adapter that does not
                    // implement an action resolves to false, so the card hides it instead of the
                    // mapping being rejected by validateAdapter.
                    restart: adapter.canRestart ?? (typeof adapter.restart === "function"),
                    autostart: adapter.canAutostart ?? (typeof adapter.setAutostart === "function")
                }, mapping.capabilities ?? ({ })),
                mappingRef: mapping,
                adapterRef: adapter
            }));
        }

        serviceEntries = nextEntries;
        maybeReportInvalidConfiguration();

        if (serviceEntries.length > 0 && panelVisible)
            Qt.callLater(() => refreshVisible());
    }

    function resolveMappings(): list<var> {
        if (simulatedMappings !== undefined)
            return Array.isArray(simulatedMappings) ? simulatedMappings : [];

        if (Array.isArray(fileMappings) && fileMappings.length > 0)
            return fileMappings;

        const primary = GlobalConfig.services.panelMappings;
        if (Array.isArray(primary) && primary.length > 0)
            return primary;

        const deprecated = GlobalConfig.launcher.services;
        if (Array.isArray(deprecated) && deprecated.length > 0) {
            maybeReportDeprecatedMappingSource();
            return deprecated;
        }

        return [];
    }

    function maybeReportDeprecatedMappingSource(): void {
        if (deprecatedConfigToastShown)
            return;

        deprecatedConfigToastShown = true;
        console.warn("[services.panel] launcher.services is deprecated. Use services.panelMappings instead.");
        emitToast(Tr.tr("Deprecated services mappings source"), Tr.tr("Use services.panelMappings instead of launcher.services."), "warning");
    }

    function buildAdapterRegistry(): var {
        const resolvedAdapters = simulatedAdapters !== undefined ? simulatedAdapters : [root.dockerAdapter, root.systemdAdapter];
        const registry = ({ });

        if (!Array.isArray(resolvedAdapters))
            return registry;

        for (const adapter of resolvedAdapters) {
            const adapterId = adapter?.adapterId;
            if (!adapter || !adapterId)
                continue;

            registry[adapterId] = adapter;
        }

        return registry;
    }

    function normalizeIconFont(rawFont: var): string {
        return rawFont === "nerd" ? "nerd" : "material";
    }

    function validateMapping(mapping: var): var {
        if (!mapping || typeof mapping !== "object") {
            return {
                ok: false,
                message: Tr.tr("Invalid services.panelMappings entry: expected object.")
            };
        }

        for (const field of ["id", "name", "adapter"])
            if (!mapping[field] || `${mapping[field]}`.length === 0)
                return {
                    ok: false,
                    message: Tr.tr("Skipping service mapping with missing '%1'.").arg(field)
                };

        return {
            ok: true
        };
    }

    function validateAdapter(mappingId: string, adapter: var): var {
        if (!adapter) {
            return {
                ok: false,
                message: Tr.tr("Skipping '%1': adapter not found.").arg(mappingId)
            };
        }

        if (typeof adapter.probe !== "function") {
            return {
                ok: false,
                message: Tr.tr("Skipping '%1': adapter '%2' is missing probe().").arg(mappingId).arg(adapter.adapterId ?? "unknown")
            };
        }

        if ((adapter.canStart ?? true) && typeof adapter.start !== "function") {
            return {
                ok: false,
                message: Tr.tr("Skipping '%1': adapter '%2' is missing start().").arg(mappingId).arg(adapter.adapterId ?? "unknown")
            };
        }

        if ((adapter.canStop ?? false) && typeof adapter.stop !== "function") {
            return {
                ok: false,
                message: Tr.tr("Skipping '%1': adapter '%2' is missing stop().").arg(mappingId).arg(adapter.adapterId ?? "unknown")
            };
        }

        return {
            ok: true
        };
    }

    function findEntryById(serviceId: string): QtObject {
        return serviceEntries.find(entry => entry.id === serviceId) ?? null;
    }

    function clearEntries(): void {
        for (const entry of serviceEntries)
            entry.destroy();

        serviceEntries = [];
    }

    function stateFromRaw(rawState: string): string {
        switch (rawState) {
        case "running":
        case "stopped":
        case "failed":
        case "unknown":
            return rawState;
        default:
            return "unknown";
        }
    }

    function normalizeProbeResult(entry: QtObject, rawResult: var): var {
        const normalizedByAdapter = typeof entry.adapterRef.normalizeError === "function" ? entry.adapterRef.normalizeError(rawResult) : rawResult;
        const fallbackMessage = Tr.tr("Could not read %1 service status.").arg(entry.name);

        return {
            ok: normalizedByAdapter?.ok ?? false,
            state: stateFromRaw(normalizedByAdapter?.state ?? "unknown"),
            message: normalizedByAdapter?.message ?? fallbackMessage,
            detail: normalizedByAdapter?.detail ?? "",
            // The adapters name the autostart flag `enabled`; the entry calls it `autostart` so it
            // does not collide with the mapping's own `enabled` (whether the card is shown at all).
            memoryBytes: normalizedByAdapter?.memoryBytes ?? null,
            cpuUsageNSec: normalizedByAdapter?.cpuUsageNSec ?? 0,
            restarts: normalizedByAdapter?.restarts ?? 0,
            activeSince: normalizedByAdapter?.activeSince ?? "",
            autostart: normalizedByAdapter?.enabled ?? null
        };
    }

    function normalizeActionResult(entry: QtObject, rawResult: var): var {
        const normalizedByAdapter = typeof entry.adapterRef.normalizeError === "function" ? entry.adapterRef.normalizeError(rawResult) : rawResult;
        const fallbackMessage = Tr.tr("Could not complete action for %1.").arg(entry.name);

        return {
            ok: normalizedByAdapter?.ok ?? false,
            message: normalizedByAdapter?.message ?? fallbackMessage,
            detail: normalizedByAdapter?.detail ?? ""
        };
    }

    function probeEntry(entry: QtObject, options: var, done: var): void {
        if (!entry || !entry.adapterRef || typeof entry.adapterRef.probe !== "function") {
            if (done)
                done({
                    ok: false,
                    state: "unknown",
                    message: Tr.tr("Adapter contract error")
                });
            return;
        }

        if (entry.probeInFlight && !options?.allowBusy) {
            if (done)
                done({
                    ok: false,
                    state: entry.state,
                    message: Tr.tr("Probe already running")
                });
            return;
        }

        if (entry.probeInFlight && options?.allowBusy)
            entry.probeToken += 1; // Invalidate older pending probe callback

        entry.probeInFlight = true;
        entry.probeToken += 1;
        const token = entry.probeToken;

        entry.adapterRef.probe(entry.mappingRef, rawProbeResult => {
            if (token !== entry.probeToken)
                return;

            entry.probeInFlight = false;
            const result = normalizeProbeResult(entry, rawProbeResult);

            entry.state = result.state;
            entry.lastUpdatedAt = Date.now();

            // CPU is only meaningful as a delta: the adapters report a cumulative counter, so the
            // percentage comes from two consecutive probes. The first sample after the panel opens
            // reports 0, and a counter that moved backwards means the unit restarted, which also
            // reports 0 for that sample instead of a negative number. The cadence is the existing
            // periodicRefresh, which only runs while the panel is visible. Kept inline rather than
            // extracted because an extra function here would add a section-order violation to a
            // file that already has 39 of them.
            const sampledAt = Date.now();
            const nextNs = Number(result.cpuUsageNSec ?? 0);
            if (entry.cpuSampledAt > 0 && sampledAt > entry.cpuSampledAt && nextNs >= entry.cpuUsageNSec)
                entry.cpuPercent = Math.max(0, (nextNs - entry.cpuUsageNSec) / ((sampledAt - entry.cpuSampledAt) * 1e6) * 100);
            else
                entry.cpuPercent = 0;

            entry.cpuUsageNSec = nextNs;
            entry.cpuSampledAt = sampledAt;
            entry.memoryBytes = result.memoryBytes ?? null;
            entry.restarts = result.restarts ?? 0;
            entry.activeSince = result.activeSince ?? "";
            entry.autostart = result.autostart ?? null;

            if (result.ok && (result.state === "running" || result.state === "stopped")) {
                entry.lastError = "";
            } else if (result.state === "failed" || !result.ok) {
                entry.lastError = result.message;

                if (!result.ok && !options?.silent)
                    emitToast(Tr.tr("%1 status failed").arg(entry.name), result.message, "error");
            }

            if (done)
                done(result);
        });
    }

    function startService(entry: QtObject): void {
        if (!entry || entry.busy)
            return;

        if (entry.state === "running") {
            emitToast(Tr.tr("%1 is already running").arg(entry.name), Tr.tr("No action needed."), "info");
            return;
        }

        if (!(entry.capabilities?.start ?? true)) {
            emitToast(Tr.tr("%1 cannot be started").arg(entry.name), Tr.tr("This service mapping is read-only."), "warning");
            return;
        }

        if (entry.probeInFlight) {
            emitToast(Tr.tr("%1 is busy").arg(entry.name), Tr.tr("A status refresh is in progress. Please try again."), "schedule");
            return;
        }

        runActionWithVerification(entry, "start", Tr.tr("started"), Tr.tr("start not confirmed"));
    }

    function stopService(entry: QtObject): void {
        if (!entry || entry.busy)
            return;

        if (entry.state === "stopped") {
            emitToast(Tr.tr("%1 is already stopped").arg(entry.name), Tr.tr("No action needed."), "info");
            return;
        }

        if (!(entry.capabilities?.stop ?? false)) {
            emitToast(Tr.tr("%1 cannot be stopped").arg(entry.name), Tr.tr("This service mapping does not support stop."), "warning");
            return;
        }

        if (entry.probeInFlight) {
            emitToast(Tr.tr("%1 is busy").arg(entry.name), Tr.tr("A status refresh is in progress. Please try again."), "schedule");
            return;
        }

        runActionWithVerification(entry, "stop", Tr.tr("stopped"), Tr.tr("stop not confirmed"));
    }

    function runActionWithVerification(entry: QtObject, actionName: string, successSuffix: string, verifyFailureSuffix: string): void {
        const adapterAction = entry.adapterRef[actionName];
        if (typeof adapterAction !== "function") {
            emitToast(Tr.tr("Failed to %1 %2").arg(actionName).arg(entry.name), Tr.tr("Adapter contract error."), "error");
            return;
        }

        entry.busy = true;
        entry.actionToken += 1;
        const currentActionToken = entry.actionToken;

        adapterAction.call(entry.adapterRef, entry.mappingRef, rawActionResult => {
            if (currentActionToken !== entry.actionToken)
                return;

            const actionResult = normalizeActionResult(entry, rawActionResult);
            if (!actionResult.ok) {
                entry.busy = false;
                entry.lastError = actionResult.message;
                emitToast(Tr.tr("Failed to %1 %2").arg(actionName).arg(entry.name), actionResult.message, "error", Toast.Error);
                return;
            }

            Qt.callLater(() => {
                probeEntry(entry, {
                    silent: true,
                    allowBusy: true
                }, verifyResult => {
                    entry.busy = false;

                    const expectedState = actionName === "start" ? "running" : "stopped";
                    if (verifyResult.ok && verifyResult.state === expectedState) {
                        entry.lastError = "";
                        const successTitle = actionName === "start" ? Tr.tr("%1 Started").arg(entry.name) : Tr.tr("%1 Stopped").arg(entry.name);
                        const successDesc = actionName === "start" ? Tr.tr("Service is now running successfully.") : Tr.tr("Service has been stopped.");
                        const successIcon = actionName === "start" ? "check_circle" : "stop_circle";
                        emitToast(successTitle, successDesc, successIcon, actionName === "start" ? Toast.Success : Toast.Info);
                        return;
                    }

                    if (verifyResult.state === "running" && actionName === "stop") {
                        verificationTimer.targetEntry = entry;
                        verificationTimer.actionName = actionName;
                        verificationTimer.successSuffix = successSuffix;
                        verificationTimer.verifyFailureSuffix = verifyFailureSuffix;
                        verificationTimer.retries = 3;
                        verificationTimer.restart();
                        return;
                    }

                    const verificationMessage = verifyResult.message || Tr.tr("Action finished but state verification failed.");
                    entry.lastError = verificationMessage;
                    emitToast(Tr.tr("%1 %2").arg(entry.name).arg(verifyFailureSuffix), verificationMessage, "error");
                });
            });
        });
    }

    function registerInvalidDiagnostic(message: string): void {
        invalidDiagnostics.push(message);
        console.warn(`[services.panel] ${message}`);
    }

    function maybeReportInvalidConfiguration(): void {
        if (invalidDiagnostics.length === 0 || invalidConfigToastShown)
            return;

        invalidConfigToastShown = true;
        emitToast(Tr.tr("Some services were skipped"), invalidDiagnostics[0], "warning");
    }

    Component.onCompleted: reload()

    readonly property Connections servicesConfigConnections: Connections {
        function onPanelMappingsChanged(): void {
            root.reload();
        }

        target: GlobalConfig.services
    }

    readonly property Connections launcherConfigConnections: Connections {
        function onServicesChanged(): void {
            root.reload();
        }

        target: GlobalConfig.launcher
    }

    readonly property Timer periodicRefresh: Timer {
        interval: Math.max(3000, root.refreshIntervalMs)
        repeat: true
        running: root.panelVisible && root.periodicRefreshEnabled
        onTriggered: root.refreshVisible()
    }

    readonly property QtObject dockerAdapter: Adapters.DockerAdapter {}
    readonly property QtObject systemdAdapter: Adapters.SystemdAdapter {}

    readonly property FileView mappingsFile: FileView {

        path: `${Paths.config}/services-panel.json`
        watchChanges: true
        printErrors: false

        onFileChanged: reload()

        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (Array.isArray(parsed)) {
                    root.fileMappings = parsed;
                    root.mappingFileError = "";
                } else if (parsed && Array.isArray(parsed.mappings)) {
                    root.fileMappings = parsed.mappings;
                    root.mappingFileError = "";
                } else {
                    root.fileMappings = [];
                    root.mappingFileError = Tr.tr("Invalid services-panel.json: expected `mappings` array.");
                }
            } catch (e) {
                root.fileMappings = [];
                root.mappingFileError = Tr.tr("Failed to parse services-panel.json: %1").arg(String(e));
            }
            root.reload();
        }

        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.fileMappings = [];
                root.mappingFileError = "";
            } else {
                root.fileMappings = [];
                root.mappingFileError = Tr.tr("Failed to read services-panel.json (%1)").arg(String(err));
            }
            root.reload();
        }
    }

    component ServiceEntry: QtObject {
        required property string id
        required property string name
        required property string description
        required property string icon
        required property string iconFont
        required property string adapterId
        required property bool enabled
        required property var capabilities
        required property var mappingRef
        required property var adapterRef

        property string state: "unknown"
        property bool busy: false
        property string lastError: ""
        property double lastUpdatedAt: 0
        property int probeToken: 0
        property int actionToken: 0
        property bool probeInFlight: false

        // Metrics from the last probe. `memoryBytes` is null when the cgroup is gone, `autostart`
        // null when the unit-file state is not one we recognise, and `cpuPercent` is derived from
        // consecutive samples, never taken directly from the adapter.
        property var memoryBytes: null
        property real cpuUsageNSec: 0
        property real cpuPercent: 0
        property int restarts: 0
        property string activeSince: ""
        property var autostart: null
        property double cpuSampledAt: 0
    }

    readonly property Component serviceEntryFactory: Component { ServiceEntry {} }
}
