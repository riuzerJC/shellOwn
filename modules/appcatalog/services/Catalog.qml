pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    readonly property string userManifestPath: `${Paths.config}/app-catalog.json`
    readonly property string bundledManifestPath: Paths.toLocalFile(Qt.resolvedUrl("../manifest.json"))

    property bool loaded
    property bool resolvingInstalled
    property string sourcePath
    property string errorText
    property string warningText
    property string searchText
    property string typeFilter: "all"
    property string statusFilter: "all"
    property var tagFilters: []
    property var entries: []
    property var invalidEntries: []
    property var filteredEntries: []
    property var installedCache: ({})
    property int manifestGeneration
    property var activeProcesses: []

    readonly property int totalCount: entries.length
    readonly property int invalidCount: invalidEntries.length
    readonly property list<string> typeFilters: ["all", "gui", "tui", "cli"]
    readonly property list<string> statusFilters: ["all", "installed", "missing", "unknown"]
    readonly property Component commandProcessFactory: Component {
        CommandProcess {}
    }

    function reload(): void {
        userManifest.reload();
    }

    function setFilters(search: string, type: string, status: string, tags: var): void {
        searchText = search ?? "";
        typeFilter = typeFilters.includes(type) ? type : "all";
        statusFilter = statusFilters.includes(status) ? status : "all";
        tagFilters = Array.isArray(tags) ? tags : [];
    }

    function statusFor(entry: var): string {
        return installedCache[entry.id] ?? "unknown";
    }

    function loadManifest(data: string, path: string, fallbackWarning: string, fallbackError: string, allowBundledFallback: bool): void {
        manifestGeneration++;
        installedCache = ({});
        const valid = [];
        const invalid = [];
        let parsed;

        try {
            parsed = JSON.parse(data);
        } catch (e) {
            if (allowBundledFallback) {
                fallbackManifest.reloadWithWarning(`Failed to parse app-catalog.json (${String(e)}); using bundled catalog.`, `User app catalog is invalid: ${String(e)}`);
                return;
            }

            loaded = true;
            entries = [];
            invalidEntries = [];
            filteredEntries = [];
            sourcePath = path;
            errorText = `Failed to parse app catalog manifest: ${String(e)}`;
            warningText = fallbackWarning ?? "";
            return;
        }

        const rawEntries = Array.isArray(parsed) ? parsed : parsed?.entries;
        if (!Array.isArray(rawEntries)) {
            if (allowBundledFallback) {
                fallbackManifest.reloadWithWarning("Invalid app-catalog.json: expected an `entries` array; using bundled catalog.", "User app catalog is invalid: expected an `entries` array.");
                return;
            }

            loaded = true;
            entries = [];
            invalidEntries = [];
            filteredEntries = [];
            sourcePath = path;
            errorText = "Invalid app catalog manifest: expected an `entries` array.";
            warningText = fallbackWarning ?? "";
            return;
        }

        for (const [index, raw] of rawEntries.entries()) {
            const result = validateEntry(raw, index);
            if (result.valid)
                valid.push(result.entry);
            else
                invalid.push(result.error);
        }

        loaded = true;
        sourcePath = path;
        entries = valid;
        invalidEntries = invalid;
        errorText = fallbackError ?? "";
        warningText = fallbackWarning ?? "";
        updateFilteredEntries();
        resolveInstalledStates();
    }

    function validateEntry(raw: var, index: int): var {
        if (!raw || typeof raw !== "object")
            return invalidEntry(index, "entry must be an object");

        const type = String(raw.type ?? "").toLowerCase();
        if (!raw.id || !raw.name || !raw.description)
            return invalidEntry(index, "missing id, name, or description");
        if (!["gui", "tui", "cli"].includes(type))
            return invalidEntry(index, `unsupported type: ${raw.type}`);
        if (!raw.desktopId && !raw.binary && !raw.command && !raw.packages && !raw.examples)
            return invalidEntry(index, "missing launch or metadata field");

        return {
            valid: true,
            entry: {
                id: String(raw.id),
                name: String(raw.name),
                description: String(raw.description),
                type,
                tags: normaliseStringList(raw.tags),
                icon: raw.icon ? String(raw.icon) : "apps",
                desktopId: raw.desktopId ? String(raw.desktopId) : "",
                binary: raw.binary ? String(raw.binary) : "",
                command: normaliseCommand(raw.command),
                terminal: raw.terminal ?? type !== "gui",
                packages: normalisePackages(raw.packages),
                examples: normaliseStringList(raw.examples),
                searchText: searchTextFor(raw, type)
            }
        };
    }

    function invalidEntry(index: int, reason: string): var {
        return {
            index,
            reason
        };
    }

    function normaliseStringList(value: var): list<string> {
        if (!Array.isArray(value))
            return [];
        return value.filter(v => v !== undefined && v !== null).map(v => String(v));
    }

    function normaliseCommand(value: var): list<string> {
        if (Array.isArray(value))
            return value.filter(v => v !== undefined && v !== null).map(v => String(v));
        if (typeof value === "string" && value.trim())
            return value.trim().split(/\s+/);
        return [];
    }

    function normalisePackages(value: var): var {
        if (!value || typeof value !== "object")
            return {};
        return {
            arch: normaliseStringList(value.arch),
            nixos: normaliseStringList(value.nixos)
        };
    }

    function searchTextFor(raw: var, type: string): string {
        const packages = normalisePackages(raw.packages);
        return [
            raw.id,
            raw.name,
            raw.description,
            type,
            raw.desktopId,
            raw.binary,
            ...normaliseCommand(raw.command),
            ...normaliseStringList(raw.tags),
            ...packages.arch,
            ...packages.nixos
        ].filter(v => v !== undefined && v !== null && String(v).length > 0).join(" ").toLowerCase();
    }

    function updateFilteredEntries(): void {
        const needle = searchText.trim().toLowerCase();
        const tags = Array.isArray(tagFilters) ? tagFilters.map(t => String(t).toLowerCase()) : [];
        filteredEntries = entries.filter(entry => {
            if (typeFilter !== "all" && entry.type !== typeFilter)
                return false;
            if (statusFilter !== "all" && statusFor(entry) !== statusFilter)
                return false;
            if (tags.length > 0 && !tags.every(tag => entry.tags.map(t => t.toLowerCase()).includes(tag)))
                return false;
            return !needle || entry.searchText.includes(needle);
        });
    }

    function resolveInstalledStates(): void {
        resolvingInstalled = true;
        const cache = Object.assign({}, installedCache);
        const desktopIds = buildDesktopIdSet();
        for (const entry of entries) {
            if (cache[entry.id])
                continue;

            if (entry.desktopId && desktopIds[entry.desktopId]) {
                cache[entry.id] = "installed";
            } else if (entry.binary) {
                cache[entry.id] = "unknown";
                queueBinaryCheck(entry.id, entry.binary, manifestGeneration);
            } else {
                cache[entry.id] = "unknown";
            }
        }
        installedCache = cache;
        resolvingInstalled = activeProcesses.length > 0;
    }

    function buildDesktopIdSet(): var {
        const ids = {};
        for (const entry of DesktopEntries.applications.values) {
            ids[entry.id] = true;
            if (entry.id.endsWith(".desktop"))
                ids[entry.id.slice(0, -8)] = true;
        }
        return ids;
    }

    function queueBinaryCheck(entryId: string, binary: string, generation: int): void {
        const proc = commandProcessFactory.createObject(root, {
            entryId,
            generation,
            cmdArgs: ["sh", "-c", `command -v -- '${binary.replace(/'/g, "'\\''")}' >/dev/null 2>&1`]
        });
        activeProcesses.push(proc);
        proc.processFinished.connect(() => {
            const index = activeProcesses.indexOf(proc);
            if (index >= 0)
                activeProcesses.splice(index, 1);
            resolvingInstalled = activeProcesses.length > 0;
            proc.destroy();
        });
        Qt.callLater(() => {
            proc.command = proc.cmdArgs;
            proc.running = true;
        });
    }

    onSearchTextChanged: updateFilteredEntries()
    onTypeFilterChanged: updateFilteredEntries()
    onStatusFilterChanged: updateFilteredEntries()
    onTagFiltersChanged: updateFilteredEntries()
    onInstalledCacheChanged: scheduleFilterUpdate()

    property bool filterUpdatePending
    function scheduleFilterUpdate(): void {
        if (!filterUpdatePending) {
            filterUpdatePending = true;
            Qt.callLater(() => {
                filterUpdatePending = false;
                updateFilteredEntries();
            });
        }
    }

    FileView {
        id: userManifest

        path: root.userManifestPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.loadManifest(text(), path, "", "", true)
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                fallbackManifest.reload();
            } else {
                fallbackManifest.reloadWithWarning(`Failed to read app-catalog.json (${String(err)}); using bundled catalog.`, "");
            }
        }
    }

    FileView {
        id: fallbackManifest

        property string pendingWarning
        property string pendingError

        function reloadWithWarning(warning: string, error: string): void {
            pendingWarning = warning;
            pendingError = error;
            reload();
        }

        path: root.bundledManifestPath
        printErrors: false
        onLoaded: {
            root.loadManifest(text(), path, pendingWarning, pendingError, false);
            pendingWarning = "";
            pendingError = "";
        }
        onLoadFailed: err => {
            root.loaded = true;
            root.entries = [];
            root.invalidEntries = [];
            root.filteredEntries = [];
            root.sourcePath = path;
            root.errorText = `Failed to read bundled app catalog (${String(err)}).`;
            root.warningText = pendingWarning;
            pendingWarning = "";
            pendingError = "";
        }
    }

    component CommandProcess: Process {
        id: process

        property string entryId
        property int generation
        property list<string> cmdArgs: []

        signal processFinished

        onExited: code => { // qmllint disable signal-handler-parameters
            if (generation === root.manifestGeneration) {
                const cache = Object.assign({}, root.installedCache);
                cache[entryId] = code === 0 ? "installed" : "missing";
                root.installedCache = cache;
            }
            processFinished();
        }
    }
}
