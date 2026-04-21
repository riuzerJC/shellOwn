import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property string adapterId: "systemd"
    property string displayName: qsTr("Systemd")
    property bool canStart: true
    property bool canStop: true
    property list<QtObject> activeProcesses: []

    function normalizeError(rawResult: var): var {
        if (!rawResult)
            return {
                ok: false,
                message: qsTr("Service command failed."),
                detail: ""
            };

        return {
            ok: rawResult.ok ?? rawResult.success ?? false,
            state: rawResult.state ?? "unknown",
            message: rawResult.message ?? rawResult.error ?? qsTr("Service command failed."),
            detail: rawResult.detail ?? rawResult.output ?? ""
        };
    }

    function resolveUnit(serviceConfig: var): string {
        const unit = String(serviceConfig?.params?.unit ?? serviceConfig?.id ?? "").trim();
        if (!unit)
            return "";
        return unit.includes(".") ? unit : `${unit}.service`;
    }

    function probe(serviceConfig: var, callback: var): void {
        const unit = resolveUnit(serviceConfig);
        if (!unit) {
            callback({
                ok: false,
                state: "unknown",
                message: qsTr("Missing systemd unit in service mapping."),
                detail: ""
            });
            return;
        }

        runCommand(["systemctl", "is-active", unit], result => {
            const output = `${result.output ?? ""}\n${result.error ?? ""}`.toLowerCase();
            if (result.success && output.includes("active")) {
                callback({
                    ok: true,
                    state: "running",
                    message: qsTr("Service is running."),
                    detail: output.trim()
                });
                return;
            }

            if (output.includes("inactive") || output.includes("failed") || output.includes("dead")) {
                callback({
                    ok: true,
                    state: "stopped",
                    message: qsTr("Service is stopped."),
                    detail: output.trim()
                });
                return;
            }

            callback({
                ok: false,
                state: "unknown",
                message: qsTr("Unable to determine service status."),
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
                message: qsTr("Missing systemd unit in service mapping."),
                detail: ""
            });
            return;
        }

        const command = serviceConfig?.params?.noPkexec === true ? ["systemctl", action, unit] : ["pkexec", "systemctl", action, unit];
        runCommand(command, result => {
            if (result.success) {
                callback({
                    ok: true,
                    message: qsTr("Service %1 command executed.").arg(action),
                    detail: result.output ?? ""
                });
                return;
            }

            const detail = result.error || result.output || qsTr("No output");
            callback({
                ok: false,
                message: qsTr("Failed to %1 service.").arg(action),
                detail
            });
        });
    }

    function runCommand(command: var, callback: var): void {
        const proc = commandProcessFactory.createObject(root, {
            cmdArgs: command,
            callback
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
        property list<string> cmdArgs: []
        property var callback: null

        signal processFinished

        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })

        stdout: StdioCollector { id: stdoutCollector }
        stderr: StdioCollector { id: stderrCollector }

        onExited: code => {
            if (callback) {
                callback({
                    success: code === 0,
                    exitCode: code,
                    output: (stdoutCollector?.text ?? "").trim(),
                    error: (stderrCollector?.text ?? "").trim()
                });
            }
            processFinished();
        }
    }

    readonly property Component commandProcessFactory: Component {
        CommandProcess {}
    }
}
