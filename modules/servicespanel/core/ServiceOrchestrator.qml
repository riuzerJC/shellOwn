pragma Singleton

import QtQuick
import Quickshell.Io
import Caelestia.Config
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

    function setPanelVisible(active: bool): void {
        panelVisible = active;

        if (active)
            refreshVisible();
    }

    function transformSearch(search: string): string {
        return search.trim();
    }

    function emitToast(title: string, message: string, icon: string): void {
        if (typeof Toaster !== "undefined" && Toaster?.toast)
            Toaster.toast(title, message, icon);
        else
            console.warn(`[services.panel] ${title}: ${message}`);
    }

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
                description: mapping.description ?? qsTr("No description"),
                icon: mapping.icon ?? "deployed_code",
                adapterId: mapping.adapter,
                enabled: mapping.enabled ?? true,
                capabilities: mapping.capabilities ?? ({
                        start: true,
                        stop: false
                    }),
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
        emitToast(qsTr("Deprecated services mappings source"), qsTr("Use services.panelMappings instead of launcher.services."), "warning");
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

    function validateMapping(mapping: var): var {
        if (!mapping || typeof mapping !== "object") {
            return {
                ok: false,
                message: qsTr("Invalid services.panelMappings entry: expected object.")
            };
        }

        for (const field of ["id", "name", "adapter"])
            if (!mapping[field] || `${mapping[field]}`.length === 0)
                return {
                    ok: false,
                    message: qsTr("Skipping service mapping with missing '%1'.").arg(field)
                };

        return {
            ok: true
        };
    }

    function validateAdapter(mappingId: string, adapter: var): var {
        if (!adapter) {
            return {
                ok: false,
                message: qsTr("Skipping '%1': adapter not found.").arg(mappingId)
            };
        }

        if (typeof adapter.probe !== "function") {
            return {
                ok: false,
                message: qsTr("Skipping '%1': adapter '%2' is missing probe().").arg(mappingId).arg(adapter.adapterId ?? "unknown")
            };
        }

        if ((adapter.canStart ?? true) && typeof adapter.start !== "function") {
            return {
                ok: false,
                message: qsTr("Skipping '%1': adapter '%2' is missing start().").arg(mappingId).arg(adapter.adapterId ?? "unknown")
            };
        }

        if ((adapter.canStop ?? false) && typeof adapter.stop !== "function") {
            return {
                ok: false,
                message: qsTr("Skipping '%1': adapter '%2' is missing stop().").arg(mappingId).arg(adapter.adapterId ?? "unknown")
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
        case "unknown":
            return rawState;
        default:
            return "unknown";
        }
    }

    function normalizeProbeResult(entry: QtObject, rawResult: var): var {
        const normalizedByAdapter = typeof entry.adapterRef.normalizeError === "function" ? entry.adapterRef.normalizeError(rawResult) : rawResult;
        const fallbackMessage = qsTr("Could not read %1 service status.").arg(entry.name);

        return {
            ok: normalizedByAdapter?.ok ?? false,
            state: stateFromRaw(normalizedByAdapter?.state ?? "unknown"),
            message: normalizedByAdapter?.message ?? fallbackMessage,
            detail: normalizedByAdapter?.detail ?? ""
        };
    }

    function normalizeActionResult(entry: QtObject, rawResult: var): var {
        const normalizedByAdapter = typeof entry.adapterRef.normalizeError === "function" ? entry.adapterRef.normalizeError(rawResult) : rawResult;
        const fallbackMessage = qsTr("Could not complete action for %1.").arg(entry.name);

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
                    message: qsTr("Adapter contract error")
                });
            return;
        }

        if (entry.probeInFlight && !options?.allowBusy) {
            if (done)
                done({
                    ok: false,
                    state: entry.state,
                    message: qsTr("Probe already running")
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

            if (result.ok && result.state === "running") {
                entry.lastError = "";
            } else if (!result.ok) {
                entry.lastError = result.message;

                if (!options?.silent)
                    emitToast(qsTr("%1 status failed").arg(entry.name), result.message, "error");
            }

            if (done)
                done(result);
        });
    }

    function startService(entry: QtObject): void {
        if (!entry || entry.busy)
            return;

        if (entry.state === "running") {
            emitToast(qsTr("%1 is already running").arg(entry.name), qsTr("No action needed."), "info");
            return;
        }

        if (!(entry.capabilities?.start ?? true)) {
            emitToast(qsTr("%1 cannot be started").arg(entry.name), qsTr("This service mapping is read-only."), "warning");
            return;
        }

        if (entry.probeInFlight) {
            emitToast(qsTr("%1 is busy").arg(entry.name), qsTr("A status refresh is in progress. Please try again."), "schedule");
            return;
        }

        runActionWithVerification(entry, "start", qsTr("started"), qsTr("start not confirmed"));
    }

    function stopService(entry: QtObject): void {
        if (!entry || entry.busy)
            return;

        if (entry.state === "stopped") {
            emitToast(qsTr("%1 is already stopped").arg(entry.name), qsTr("No action needed."), "info");
            return;
        }

        if (!(entry.capabilities?.stop ?? false)) {
            emitToast(qsTr("%1 cannot be stopped").arg(entry.name), qsTr("This service mapping does not support stop."), "warning");
            return;
        }

        if (entry.probeInFlight) {
            emitToast(qsTr("%1 is busy").arg(entry.name), qsTr("A status refresh is in progress. Please try again."), "schedule");
            return;
        }

        runActionWithVerification(entry, "stop", qsTr("stopped"), qsTr("stop not confirmed"));
    }

    function runActionWithVerification(entry: QtObject, actionName: string, successSuffix: string, verifyFailureSuffix: string): void {
        const adapterAction = entry.adapterRef[actionName];
        if (typeof adapterAction !== "function") {
            emitToast(qsTr("Failed to %1 %2").arg(actionName).arg(entry.name), qsTr("Adapter contract error."), "error");
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
                emitToast(qsTr("Failed to %1 %2").arg(actionName).arg(entry.name), actionResult.message, "error");
                return;
            }

            probeEntry(entry, {
                silent: true,
                allowBusy: true
            }, verifyResult => {
                entry.busy = false;

                const expectedState = actionName === "start" ? "running" : "stopped";
                if (verifyResult.ok && verifyResult.state === expectedState) {
                    entry.lastError = "";
                    emitToast(qsTr("%1 %2").arg(entry.name).arg(successSuffix), qsTr("Service status confirmed."), "check_circle");
                    return;
                }

                const verificationMessage = verifyResult.message || qsTr("Action finished but state verification failed.");
                entry.lastError = verificationMessage;
                emitToast(qsTr("%1 %2").arg(entry.name).arg(verifyFailureSuffix), verificationMessage, "error");
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
        emitToast(qsTr("Some services were skipped"), invalidDiagnostics[0], "warning");
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
                    root.mappingFileError = qsTr("Invalid services-panel.json: expected `mappings` array.");
                }
            } catch (e) {
                root.fileMappings = [];
                root.mappingFileError = qsTr("Failed to parse services-panel.json: %1").arg(String(e));
            }
            root.reload();
        }

        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.fileMappings = [];
                root.mappingFileError = "";
            } else {
                root.fileMappings = [];
                root.mappingFileError = qsTr("Failed to read services-panel.json (%1)").arg(String(err));
            }
            root.reload();
        }
    }

    component ServiceEntry: QtObject {
        required property string id
        required property string name
        required property string description
        required property string icon
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
    }

    readonly property Component serviceEntryFactory: Component { ServiceEntry {} }
}
