pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n

QtObject {
    id: root

    property string adapterId: "systemd"
    property string displayName: Tr.tr("Systemd")
    property bool canStart: true
    property bool canStop: true
    property bool canRestart: true
    property bool canAutostart: true
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
                message: Tr.tr("Service command failed."),
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
            message: rawResult.message ?? rawResult.error ?? Tr.tr("Service command failed."),
            detail: rawResult.detail ?? rawResult.output ?? "",
            memoryBytes: rawResult.memoryBytes ?? null,
            cpuUsageNSec: rawResult.cpuUsageNSec ?? 0,
            restarts: rawResult.restarts ?? 0,
            activeSince: rawResult.activeSince ?? "",
            enabled: rawResult.enabled ?? null
        };
    }

    function resolveUnit(serviceConfig: var): string {
        const unit = String(serviceConfig?.params?.unit ?? serviceConfig?.id ?? "").trim();
        if (!unit)
            return "";
        return unit.includes(".") ? unit : `${unit}.service`;
    }

    function isUserUnit(serviceConfig: var): bool {
        return serviceConfig?.params?.userUnit === true || serviceConfig?.params?.user === true;
    }

    function probe(serviceConfig: var, callback: var): void {
        const unit = resolveUnit(serviceConfig);
        if (!unit) {
            callback({
                ok: false,
                state: "unknown",
                message: Tr.tr("Missing systemd unit in service mapping."),
                detail: ""
            });
            return;
        }

        const isUser = isUserUnit(serviceConfig);
        // One `show` call carries the state and every metric: ActiveState/SubState resolve the
        // state the same way `is-active` did, and the remaining properties feed the S8/S9 fields.
        const properties = "ActiveState,SubState,MemoryCurrent,CPUUsageNSec,NRestarts,ActiveEnterTimestamp,UnitFileState";
        const command = isUser ? ["systemctl", "--user", "show", unit, "-p", properties] : ["systemctl", "show", unit, "-p", properties];

        runCommand(command, result => {
            const output = `${result.output ?? ""}\n${result.error ?? ""}`.trim();
            const fields = parseSystemdShow(result.output ?? "");
            const resolved = stateFromActiveState(fields.ActiveState ?? "", fields.SubState ?? "");
            const metrics = metricsFromShow(fields, resolved.state);

            callback({
                ok: resolved.state !== "unknown",
                state: resolved.state,
                message: resolved.message,
                detail: output,
                memoryBytes: metrics.memoryBytes,
                cpuUsageNSec: metrics.cpuUsageNSec,
                restarts: metrics.restarts,
                activeSince: metrics.activeSince,
                enabled: metrics.enabled
            });
        });
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

    // Mirrors the old `is-active` mapping: failed -> failed, active -> running, inactive/dead ->
    // stopped, anything else (activating, reloading, no output at all) -> unknown.
    function stateFromActiveState(activeState: string, subState: string): var {
        const state = String(activeState ?? "").trim().toLowerCase();
        const sub = String(subState ?? "").trim().toLowerCase();

        if (state === "failed")
            return { state: "failed", message: Tr.tr("Service has failed.") };
        if (state === "active")
            return { state: "running", message: Tr.tr("Service is running.") };
        if (state === "inactive" || state === "dead" || sub === "dead")
            return { state: "stopped", message: Tr.tr("Service is stopped.") };

        return { state: "unknown", message: Tr.tr("Unable to determine service status.") };
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

    function start(serviceConfig: var, callback: var): void {
        runAction(serviceConfig, "start", callback);
    }

    function stop(serviceConfig: var, callback: var): void {
        runAction(serviceConfig, "stop", callback);
    }

    function restart(serviceConfig: var, callback: var): void {
        runAction(serviceConfig, "restart", callback);
    }

    // `enable`/`disable` reuse the same command builder as start/stop, so a user unit stays
    // `systemctl --user` and a system unit goes through pkexec unless the mapping opts out.
    function setAutostart(serviceConfig: var, enabled: bool, callback: var): void {
        runAction(serviceConfig, enabled ? "enable" : "disable", callback);
    }

    // Argv for a terminal to follow the unit's journal. `--user` is added for a user unit so the
    // journal matches the unit the probe and the actions address.
    function logsCommand(serviceConfig: var): var {
        const unit = resolveUnit(serviceConfig);
        if (!unit)
            return [];

        return isUserUnit(serviceConfig) ? ["journalctl", "--user", "-u", unit, "-n", "200", "-f"] : ["journalctl", "-u", unit, "-n", "200", "-f"];
    }

    function runAction(serviceConfig: var, action: string, callback: var): void {
        const unit = resolveUnit(serviceConfig);
        if (!unit) {
            callback({
                ok: false,
                message: Tr.tr("Missing systemd unit in service mapping."),
                detail: ""
            });
            return;
        }

        const isUser = isUserUnit(serviceConfig);
        let command = [];
        if (isUser) {
            command = ["systemctl", "--user", action, unit];
        } else if (serviceConfig?.params?.noPkexec === true) {
            command = ["systemctl", action, unit];
        } else {
            command = ["pkexec", "systemctl", action, unit];
        }

        runCommand(command, result => {
            if (result.success) {
                callback({
                    ok: true,
                    message: Tr.tr("Service %1 command executed.").arg(action),
                    detail: result.output ?? ""
                });
                return;
            }

            const detail = result.error || result.output || Tr.tr("No output");
            callback({
                ok: false,
                message: Tr.tr("Failed to %1 service.").arg(action),
                detail
            });
        });
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
            callback
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
        property var callback
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

        stdout: StdioCollector {
            id: stdoutCollector
        }

        stderr: StdioCollector {
            id: stderrCollector
        }

        onExited: exitCode => process.finish(exitCode, (stdoutCollector?.text ?? "").trim(), (stderrCollector?.text ?? "").trim())
    }

    readonly property Component commandProcessFactory: Component { CommandProcess {} }
}
