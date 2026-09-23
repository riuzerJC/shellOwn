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
    property list<QtObject> activeProcesses: []
    readonly property int commandStartTimeoutMs: 3000

    function normalizeError(rawResult: var): var {
        if (!rawResult)
            return {
                ok: false,
                message: Tr.tr("Docker command failed."),
                detail: ""
            };

        return {
            ok: rawResult.ok ?? rawResult.success ?? false,
            state: rawResult.state ?? "unknown",
            message: rawResult.message ?? rawResult.error ?? Tr.tr("Docker command failed."),
            detail: rawResult.detail ?? rawResult.output ?? ""
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
        runProbeFallback(buildProbeCommands(serviceConfig), 0, [], callback);
    }

    function start(serviceConfig: var, callback: var): void {
        runStartFallback(buildStartCommands(serviceConfig), 0, [], callback);
    }

    function stop(serviceConfig: var, callback: var): void {
        runStopFallback(buildStopCommands(serviceConfig), 0, [], callback);
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
