import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property string adapterId: "docker"
    property string displayName: qsTr("Docker")
    property bool canStart: true
    property bool canStop: true
    property list<QtObject> activeProcesses: []

    function normalizeError(rawResult: var): var {
        if (!rawResult)
            return {
                ok: false,
                message: qsTr("Docker command failed."),
                detail: ""
            };

        return {
            ok: rawResult.ok ?? rawResult.success ?? false,
            state: rawResult.state ?? "unknown",
            message: rawResult.message ?? rawResult.error ?? qsTr("Docker command failed."),
            detail: rawResult.detail ?? rawResult.output ?? ""
        };
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

        if (mode === "cli-only")
            return [["docker", "info"]];

        return [
            ["systemctl", "is-active", "docker"],
            ["service", "docker", "status"],
            ["docker", "info"]
        ];
    }

    function buildStartCommands(serviceConfig: var): var {
        const preference = serviceConfig?.params?.startCommandPreference ?? ["systemctl", "service"];
        const commands = [];

        for (const strategy of preference) {
            if (strategy === "systemctl")
                commands.push(["systemctl", "start", "docker"]);
            else if (strategy === "service")
                commands.push(["service", "docker", "start"]);
            else if (strategy === "rc-service")
                commands.push(["rc-service", "docker", "start"]);
        }

        if (commands.length === 0)
            commands.push(["systemctl", "start", "docker"]);

        return commands;
    }

    function buildStopCommands(serviceConfig: var): var {
        const preference = serviceConfig?.params?.stopCommandPreference ?? ["systemctl", "service"];
        const commands = [];

        for (const strategy of preference) {
            if (strategy === "systemctl")
                commands.push(["systemctl", "stop", "docker"]);
            else if (strategy === "service")
                commands.push(["service", "docker", "stop"]);
            else if (strategy === "rc-service")
                commands.push(["rc-service", "docker", "stop"]);
        }

        if (commands.length === 0)
            commands.push(["systemctl", "stop", "docker"]);

        return commands;
    }

    function runProbeFallback(candidates: var, index: int, trace: var, callback: var): void {
        if (index >= candidates.length) {
            callback({
                ok: false,
                state: "unknown",
                message: qsTr("Unable to determine Docker status."),
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
                message: qsTr("Unable to start Docker with known commands."),
                detail: trace.join("\n")
            });
            return;
        }

        const command = candidates[index];
        runCommand(command, result => {
            const commandLabel = commandToString(command);
            const detail = result.error || result.output || qsTr("No output");
            trace.push(`${commandLabel}: ${detail}`);

            if (result.success) {
                callback({
                    ok: true,
                    message: qsTr("Docker start command executed."),
                    detail: `${commandLabel}: ${result.output || qsTr("ok")}`
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
                message: qsTr("Unable to stop Docker with known commands."),
                detail: trace.join("\n")
            });
            return;
        }

        const command = candidates[index];
        runCommand(command, result => {
            const commandLabel = commandToString(command);
            const detail = result.error || result.output || qsTr("No output");
            trace.push(`${commandLabel}: ${detail}`);

            if (result.success) {
                callback({
                    ok: true,
                    message: qsTr("Docker stop command executed."),
                    detail: `${commandLabel}: ${result.output || qsTr("ok")}`
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

        if (success && (output.includes("running") || output.includes("active"))) {
            return {
                resolved: true,
                trace: `${cmdLabel}: running`,
                result: {
                    ok: true,
                    state: "running",
                    message: qsTr("Docker is running.")
                }
            };
        }

        if (output.includes("inactive") || output.includes("failed") || output.includes("stopped") || output.includes("not running") || output.includes("dead")) {
            return {
                resolved: true,
                trace: `${cmdLabel}: stopped`,
                result: {
                    ok: true,
                    state: "stopped",
                    message: qsTr("Docker is stopped.")
                }
            };
        }

        if (success && command[0] === "docker" && command[1] === "info") {
            return {
                resolved: true,
                trace: `${cmdLabel}: running (docker info)`,
                result: {
                    ok: true,
                    state: "running",
                    message: qsTr("Docker is responding.")
                }
            };
        }

        return {
            resolved: false,
            trace: `${cmdLabel}: ${result.error || result.output || qsTr("probe failed")}`
        };
    }

    function commandToString(command: var): string {
        return command.join(" ");
    }

    function runCommand(command: var, callback: var): void {
        const proc = commandProcessFactory.createObject(root, {
            cmdArgs: command,
            callback: callback
        });
        activeProcesses.push(proc);

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

        signal processFinished

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

        onExited: code => { // qmllint disable signal-handler-parameters
            const output = stdoutCollector?.text ?? "";
            const error = stderrCollector?.text ?? "";

            if (callback) {
                callback({
                    success: code === 0,
                    exitCode: code,
                    output: output.trim(),
                    error: error.trim()
                });
            }

            processFinished();
        }
    }

    readonly property Component commandProcessFactory: Component {
        CommandProcess {}
    }
}
