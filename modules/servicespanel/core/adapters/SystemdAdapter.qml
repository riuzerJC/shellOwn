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
    property list<QtObject> activeProcesses: []
    readonly property int commandStartTimeoutMs: 3000

    function normalizeError(rawResult: var): var {
        if (!rawResult)
            return {
                ok: false,
                message: Tr.tr("Service command failed."),
                detail: ""
            };

        return {
            ok: rawResult.ok ?? rawResult.success ?? false,
            state: rawResult.state ?? "unknown",
            message: rawResult.message ?? rawResult.error ?? Tr.tr("Service command failed."),
            detail: rawResult.detail ?? rawResult.output ?? ""
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
        const command = isUser ? ["systemctl", "--user", "is-active", unit] : ["systemctl", "is-active", unit];

        runCommand(command, result => {
            const output = `${result.output ?? ""}\n${result.error ?? ""}`.toLowerCase();
            if (output.includes("failed")) {
                callback({
                    ok: true,
                    state: "failed",
                    message: Tr.tr("Service has failed."),
                    detail: output.trim()
                });
                return;
            }

            if (result.success && output.includes("active")) {
                callback({
                    ok: true,
                    state: "running",
                    message: Tr.tr("Service is running."),
                    detail: output.trim()
                });
                return;
            }

            if (output.includes("inactive") || output.includes("dead")) {
                callback({
                    ok: true,
                    state: "stopped",
                    message: Tr.tr("Service is stopped."),
                    detail: output.trim()
                });
                return;
            }

            callback({
                ok: false,
                state: "unknown",
                message: Tr.tr("Unable to determine service status."),
                detail: output.trim()
            });
        });
    }

    function start(serviceConfig: var, callback: var): void {
        runAction(serviceConfig, "start", callback);
    }

    function stop(serviceConfig: var, callback: var): void {
        runAction(serviceConfig, "stop", callback);
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
