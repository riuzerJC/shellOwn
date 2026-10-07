pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n

QtObject {
    id: root

    property string adapterId: "docker"
    property string displayName: Tr.tr("Docker")
    property bool canStart: true
    property bool canStop: true
    property bool canRestart: true
    property bool canAutostart: false
    property list<QtObject> activeProcesses: []
    readonly property int commandStartTimeoutMs: 3000
    // Upper bound so a command that never returns cannot leave the panel spinning forever. Ten
    // seconds is enough for an authentication attempt to resolve once the password is submitted;
    // raise it if it ever cuts off while you are still typing.
    readonly property int commandRunTimeoutMs: 10000

    function normalizeError(rawResult: var): var {
        if (!rawResult)
            return {
                ok: false,
                message: Tr.tr("Docker command failed."),
                detail: "",
                memoryBytes: null,
                cpuUsageNSec: 0,
                restarts: 0,
                activeSince: "",
                enabled: null
            };

        return {
            ok: rawResult.ok ?? rawResult.success ?? false,
            state: rawResult.state ?? "unknown",
            message: rawResult.message ?? rawResult.error ?? Tr.tr("Docker command failed."),
            detail: rawResult.detail ?? rawResult.output ?? "",
            memoryBytes: rawResult.memoryBytes ?? null,
            cpuUsageNSec: rawResult.cpuUsageNSec ?? 0,
            restarts: rawResult.restarts ?? 0,
            activeSince: rawResult.activeSince ?? "",
            enabled: rawResult.enabled ?? null
        };
    }

    function resolveUnit(serviceConfig: var): string {
        const raw = String(serviceConfig?.params?.unit ?? "docker").trim();
        return raw.endsWith(".service") ? raw.slice(0, -".service".length) : raw;
    }

    function resolveUnits(serviceConfig: var): list<string> {
        const unit = resolveUnit(serviceConfig);
        const rawSocket = serviceConfig?.params?.socketUnit;
        let socket = "";
        if (typeof rawSocket === "string")
            socket = rawSocket.trim();
        else if (rawSocket !== false && unit === "docker")
            socket = "docker.socket";

        return socket.length > 0 ? [socket, unit] : [unit];
    }

    function probe(serviceConfig: var, callback: var): void {
        runProbeFallback(buildProbeCommands(serviceConfig), 0, [], result => {
            attachMetrics(serviceConfig, result, callback);
        });
    }

    function start(serviceConfig: var, callback: var): void {
        runStartFallback(buildStartCommands(serviceConfig), 0, [], callback);
    }

    function stop(serviceConfig: var, callback: var): void {
        runStopFallback(buildStopCommands(serviceConfig), 0, [], callback);
    }

    function restart(serviceConfig: var, callback: var): void {
        runRestartFallback(buildRestartCommands(serviceConfig), 0, [], callback);
    }

    // The docker mapping manages the daemon's systemd unit, but autostart is a systemd concept the
    // panel does not own for this adapter: report it instead of failing silently.
    function setAutostart(serviceConfig: var, enabled: bool, callback: var): void {
        callback({
            ok: false,
            message: Tr.tr("Autostart is not supported for Docker mappings."),
            detail: ""
        });
    }

    // Same journal the systemd adapter opens, for the daemon unit this mapping resolves to.
    function logsCommand(serviceConfig: var): var {
        const unit = resolveUnit(serviceConfig);
        if (!unit)
            return [];

        return isUserUnit(serviceConfig) ? ["journalctl", "--user", "-u", unit, "-n", "200", "-f"] : ["journalctl", "-u", unit, "-n", "200", "-f"];
    }

    function buildProbeCommands(serviceConfig: var): var {
        const params = serviceConfig?.params ?? ({ });
        const mode = params.probeMode ?? "systemctl-or-cli";
        const unit = resolveUnit(serviceConfig);

        if (mode === "cli-only")
            return [["docker", "info"]];

        return [
            ["systemctl", "is-active", unit],
            ["service", unit, "status"],
            ["docker", "info"]
        ];
    }

    function buildStartCommands(serviceConfig: var): var {
        const preference = serviceConfig?.params?.startCommandPreference ?? ["systemctl", "service"];
        const usePkexec = serviceConfig?.params?.noPkexec !== true;
        const commands = [];

        for (const strategy of preference) {
            if (strategy === "systemctl")
                commands.push((usePkexec ? ["pkexec", "systemctl"] : ["systemctl"]).concat(["start"], resolveUnits(serviceConfig)));
            else if (strategy === "service")
                commands.push(["service", resolveUnit(serviceConfig), "start"]);
            else if (strategy === "rc-service")
                commands.push(["rc-service", resolveUnit(serviceConfig), "start"]);
        }

        if (commands.length === 0)
            commands.push((usePkexec ? ["pkexec", "systemctl"] : ["systemctl"]).concat(["start"], resolveUnits(serviceConfig)));

        return commands;
    }

    function buildStopCommands(serviceConfig: var): var {
        const preference = serviceConfig?.params?.stopCommandPreference ?? ["systemctl", "service"];
        const usePkexec = serviceConfig?.params?.noPkexec !== true;
        const commands = [];

        for (const strategy of preference) {
            if (strategy === "systemctl")
                commands.push((usePkexec ? ["pkexec", "systemctl"] : ["systemctl"]).concat(["stop"], resolveUnits(serviceConfig)));
            else if (strategy === "service")
                commands.push(["service", resolveUnit(serviceConfig), "stop"]);
            else if (strategy === "rc-service")
                commands.push(["rc-service", resolveUnit(serviceConfig), "stop"]);
        }

        if (commands.length === 0)
            commands.push((usePkexec ? ["pkexec", "systemctl"] : ["systemctl"]).concat(["stop"], resolveUnits(serviceConfig)));

        return commands;
    }

    function runProbeFallback(candidates: var, index: int, trace: var, callback: var): void {
        if (index >= candidates.length) {
            callback({
                ok: false,
                state: "unknown",
                message: Tr.tr("Unable to determine Docker status."),
                detail: trace.join("\n")
            });
            return;
        }

        const command = candidates[index];
        runCommand(command, result => {
            const parsed = parseProbeResult(command, result);
            trace.push(parsed.trace);

            if (parsed.resolved) {
                callback(parsed.result);
                return;
            }

            runProbeFallback(candidates, index + 1, trace, callback);
        });
    }

    function runStartFallback(candidates: var, index: int, trace: var, callback: var): void {
        if (index >= candidates.length) {
            callback({
                ok: false,
                message: Tr.tr("Unable to start Docker with known commands."),
                detail: trace.join("\n")
            });
            return;
        }

        const command = candidates[index];
        runCommand(command, result => {
            const commandLabel = commandToString(command);
            const detail = result.error || result.output || Tr.tr("No output");
            trace.push(`${commandLabel}: ${detail}`);

            if (result.success) {
                callback({
                    ok: true,
                    message: Tr.tr("Docker start command executed."),
                    detail: `${commandLabel}: ${result.output || Tr.tr("ok")}`
                });
                return;
            }

            runStartFallback(candidates, index + 1, trace, callback);
        });
    }

    function runStopFallback(candidates: var, index: int, trace: var, callback: var): void {
        if (index >= candidates.length) {
            callback({
                ok: false,
                message: Tr.tr("Unable to stop Docker with known commands."),
                detail: trace.join("\n")
            });
            return;
        }

        const command = candidates[index];
        runCommand(command, result => {
            const commandLabel = commandToString(command);
            const detail = result.error || result.output || Tr.tr("No output");
            trace.push(`${commandLabel}: ${detail}`);

            if (result.success) {
                callback({
                    ok: true,
                    message: Tr.tr("Docker stop command executed."),
                    detail: `${commandLabel}: ${result.output || Tr.tr("ok")}`
                });
                return;
            }

            runStopFallback(candidates, index + 1, trace, callback);
        });
    }

    // Mirrors the start path so restart inherits the same command preference and pkexec rules.
    function buildRestartCommands(serviceConfig: var): var {
        const preference = serviceConfig?.params?.startCommandPreference ?? ["systemctl", "service"];
        const usePkexec = serviceConfig?.params?.noPkexec !== true;
        const commands = [];

        for (const strategy of preference) {
            if (strategy === "systemctl")
                commands.push((usePkexec ? ["pkexec", "systemctl"] : ["systemctl"]).concat(["restart"], resolveUnits(serviceConfig)));
            else if (strategy === "service")
                commands.push(["service", resolveUnit(serviceConfig), "restart"]);
            else if (strategy === "rc-service")
                commands.push(["rc-service", resolveUnit(serviceConfig), "restart"]);
        }

        if (commands.length === 0)
            commands.push((usePkexec ? ["pkexec", "systemctl"] : ["systemctl"]).concat(["restart"], resolveUnits(serviceConfig)));

        return commands;
    }

    function runRestartFallback(candidates: var, index: int, trace: var, callback: var): void {
        if (index >= candidates.length) {
            callback({
                ok: false,
                message: Tr.tr("Unable to restart Docker with known commands."),
                detail: trace.join("\n")
            });
            return;
        }

        const command = candidates[index];
        runCommand(command, result => {
            const commandLabel = commandToString(command);
            const detail = result.error || result.output || Tr.tr("No output");
            trace.push(`${commandLabel}: ${detail}`);

            if (result.success) {
                callback({
                    ok: true,
                    message: Tr.tr("Docker restart command executed."),
                    detail: `${commandLabel}: ${result.output || Tr.tr("ok")}`
                });
                return;
            }

            runRestartFallback(candidates, index + 1, trace, callback);
        });
    }

    function parseProbeResult(command: var, result: var): var {
        const cmdLabel = commandToString(command);
        const output = `${result.output ?? ""}\n${result.error ?? ""}`.toLowerCase();
        const success = result.success ?? false;

        // systemctl is-active: exit 0 = active, anything else = not active
        if (command.includes("is-active")) {
            if (result.exitCode === 0) {
                return {
                    resolved: true,
                    trace: `${cmdLabel}: running`,
                    result: {
                        ok: true,
                        state: "running",
                        message: Tr.tr("Docker is running.")
                    }
                };
            }

            if (output.includes("failed")) {
                return {
                    resolved: true,
                    trace: `${cmdLabel}: failed (exit ${result.exitCode})`,
                    result: {
                        ok: true,
                        state: "failed",
                        message: Tr.tr("Docker has failed.")
                    }
                };
            }

            return {
                resolved: true,
                trace: `${cmdLabel}: stopped (exit ${result.exitCode})`,
                result: {
                    ok: true,
                    state: "stopped",
                    message: Tr.tr("Docker is stopped.")
                }
            };
        }

        if (command[0] === "docker" && command[1] === "info") {
            if (success) {
                return {
                    resolved: true,
                    trace: `${cmdLabel}: running (docker info)`,
                    result: {
                        ok: true,
                        state: "running",
                        message: Tr.tr("Docker is responding.")
                    }
                };
            }

            // The CLI answered with a failure exit code, so the binary exists but the
            // daemon is not serving us: that is a stopped daemon, not an unknown state.
            if ((result.exitCode ?? 0) > 0) {
                return {
                    resolved: true,
                    trace: `${cmdLabel}: stopped (exit ${result.exitCode})`,
                    result: {
                        ok: true,
                        state: "stopped",
                        message: Tr.tr("Docker is stopped.")
                    }
                };
            }
        }

        return {
            resolved: false,
            trace: `${cmdLabel}: ${result.error || result.output || Tr.tr("probe failed")}`
        };
    }

    function isUserUnit(serviceConfig: var): bool {
        return serviceConfig?.params?.userUnit === true || serviceConfig?.params?.user === true;
    }

    // The metrics come from the systemd unit the mapping manages, read with the same property list
    // the systemd adapter uses so the contract stays identical across both adapters. A
    // container-scoped mapping is out of scope: `docker stats` exposes no cumulative CPU counter
    // (only a percentage), so a real per-container CPUUsageNSec would need a cgroup `cpu.stat`
    // read, which is a separate task.
    function buildMetricsCommand(serviceConfig: var): var {
        const unit = resolveUnit(serviceConfig);
        const properties = "ActiveState,SubState,MemoryCurrent,CPUUsageNSec,NRestarts,ActiveEnterTimestamp,UnitFileState";
        return isUserUnit(serviceConfig) ? ["systemctl", "--user", "show", unit, "-p", properties] : ["systemctl", "show", unit, "-p", properties];
    }

    function parseSystemdShow(rawOutput: string): var {
        const fields = {};
        for (const line of String(rawOutput ?? "").split("\n")) {
            const separator = line.indexOf("=");
            if (separator <= 0)
                continue;
            fields[line.slice(0, separator).trim()] = line.slice(separator + 1).trim();
        }
        return fields;
    }

    function metricsFromShow(fields: var, state: string): var {
        return {
            memoryBytes: memoryBytesFromShow(fields.MemoryCurrent),
            cpuUsageNSec: numericFromShow(fields.CPUUsageNSec),
            restarts: numericFromShow(fields.NRestarts),
            activeSince: state === "running" ? (fields.ActiveEnterTimestamp ?? "") : "",
            enabled: enabledFromUnitFileState(fields.UnitFileState)
        };
    }

    function memoryBytesFromShow(rawValue: string): var {
        const value = String(rawValue ?? "").trim().toLowerCase();
        if (value === "" || value === "[not set]" || value === "infinity")
            return null;

        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : null;
    }

    // `real`, not `int`: CPUUsageNSec routinely exceeds 32 bits.
    function numericFromShow(rawValue: string): real {
        const parsed = Number.parseInt(String(rawValue ?? "").trim(), 10);
        return Number.isNaN(parsed) ? 0 : parsed;
    }

    function enabledFromUnitFileState(rawValue: string): var {
        switch (String(rawValue ?? "").trim()) {
        case "enabled":
        case "enabled-runtime":
        case "static":
        case "alias":
            return true;
        case "disabled":
            return false;
        default:
            return null;
        }
    }

    function applyMetricDefaults(result: var): void {
        result.memoryBytes = null;
        result.cpuUsageNSec = 0;
        result.restarts = 0;
        result.activeSince = "";
        result.enabled = null;
    }

    // Adds the metric contract to an already-derived state with a single `systemctl show` for the
    // mapping's unit. The state path stays untouched; the unit is resolved with the adapter's
    // existing resolveUnit() so the metric command and the state probe agree on it.
    function attachMetrics(serviceConfig: var, result: var, callback: var): void {
        applyMetricDefaults(result);

        const unit = resolveUnit(serviceConfig);
        if (unit.length === 0) {
            callback(result);
            return;
        }

        runCommand(buildMetricsCommand(serviceConfig), rawResult => {
            if (rawResult?.success) {
                const fields = parseSystemdShow(rawResult.output ?? "");
                const metrics = metricsFromShow(fields, result?.state ?? "unknown");
                result.memoryBytes = metrics.memoryBytes;
                result.cpuUsageNSec = metrics.cpuUsageNSec;
                result.restarts = metrics.restarts;
                result.activeSince = metrics.activeSince;
                result.enabled = metrics.enabled;
            }
            callback(result);
        });
    }

    function commandToString(command: var): string {
        return command.join(" ");
    }

    function reapUnstartedCommands(): void {
        if (activeProcesses.length === 0)
            return;

        const now = Date.now();
        for (const proc of activeProcesses.slice()) {
            if (proc.startedFlag || now - proc.queuedAt < root.commandStartTimeoutMs)
                continue;

            proc.finish(-1, "", Tr.tr("Command did not start."));
        }
    }

    readonly property Timer startWatchdog: Timer {
        interval: 1000
        repeat: true
        running: true

        onTriggered: root.reapUnstartedCommands()
    }

    function runCommand(command: var, callback: var): void {
        const proc = commandProcessFactory.createObject(root, {
            cmdArgs: command,
            callback: callback
        });
        activeProcesses.push(proc);
        proc.queuedAt = Date.now();

        proc.processFinished.connect(() => {
            const idx = activeProcesses.indexOf(proc);
            if (idx >= 0)
                activeProcesses.splice(idx, 1);
            proc.destroy();
        });

        Qt.callLater(() => {
            proc.command = proc.cmdArgs;
            proc.running = true;
        });
    }

    component CommandProcess: Process {
        id: process

        property list<string> cmdArgs: []
        property var callback: null
        property bool startedFlag: false
        property double queuedAt: 0
        property bool finished: false
        // pkexec waits on an authentication prompt that a missing or broken agent never answers.
        // Without this the panel would keep spinning instead of reporting the failure. Declared as
        // a property because Process has no default property to nest children in.
        property Timer runWatchdog: Timer {
            running: process.startedFlag && !process.finished
            interval: root.commandRunTimeoutMs

            onTriggered: {
                process.running = false;
                process.finish(-1, (stdoutCollector?.text ?? "").trim(), Tr.tr("Command timed out."));
            }
        }

        signal processFinished

        function finish(exitCode: int, output: string, error: string): void {
            if (finished)
                return;

            finished = true;
            if (callback)
                callback({
                    success: exitCode === 0,
                    exitCode,
                    output,
                    error
                });
            processFinished();
        }

        onStarted: startedFlag = true

        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })

        stdout: StdioCollector {
            id: stdoutCollector
        }

        stderr: StdioCollector {
            id: stderrCollector
        }

        onExited: code => process.finish(code, (stdoutCollector?.text ?? "").trim(), (stderrCollector?.text ?? "").trim())
    }

    readonly property Component commandProcessFactory: Component {
        CommandProcess {}
    }
}
