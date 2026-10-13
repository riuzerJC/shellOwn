pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import "../modules/updates/core/PendingUpdates.js" as PendingUpdates

// Detects pending Arch updates without ever mutating the system. `pacman -Qu` and `yay -Qua` are
// the instant, offline paths; `checkupdates` is the slower, accurate path behind the manual
// refresh. Tool presence is probed once so a machine without pacman (the NixOS target) settles
// quietly instead of reporting a failure for a command that was never expected to exist.
Singleton {
    id: root

    property string state: "idle"
    property list<var> official: []
    property list<var> aur: []
    property string error: ""

    readonly property int ignoredCount: official.filter(entry => entry.ignored).length
    readonly property int actionableCount: official.filter(entry => !entry.ignored).length + aur.length
    readonly property bool hasUpdates: actionableCount > 0

    property bool toolsProbed: false
    property bool hasPacman: false
    property bool hasYay: false
    property bool hasCheckupdates: false
    property bool refreshQueued: false
    property bool busy: false

    // The instant path: pacman first, then yay once it finishes. Kept as a guard against overlapping
    // polls and against a check that lands before the one-time presence probe has reported.
    function check(): void {
        if (busy)
            return;
        if (!toolsProbed) {
            probe();
            return;
        }
        if (!hasPacman) {
            settleQuietly();
            return;
        }
        busy = true;
        error = "";
        state = "checking";
        pacmanProc.running = true;
    }

    // The accurate path: checkupdates syncs a temporary copy of the databases, so it needs network
    // and is slower, but it reflects the real repositories. It replaces the pacman result only.
    function refresh(): void {
        if (busy)
            return;
        if (!toolsProbed) {
            refreshQueued = true;
            probe();
            return;
        }
        if (!hasCheckupdates) {
            fail("checkupdates not found");
            return;
        }
        busy = true;
        error = "";
        state = "checking";
        checkupdatesProc.running = true;
    }

    function probe(): void {
        if (!presenceProc.running)
            presenceProc.running = true;
    }

    function handlePresence(output): void {
        const tools = output.split("\n").map(line => line.trim()).filter(line => line.length > 0);
        hasPacman = tools.indexOf("pacman") !== -1;
        hasYay = tools.indexOf("yay") !== -1;
        hasCheckupdates = tools.indexOf("checkupdates") !== -1;
        toolsProbed = true;
        if (refreshQueued) {
            refreshQueued = false;
            refresh();
        } else {
            check();
        }
    }

    // "The command ran and produced nothing" is not an error: the commands signal an empty result
    // with a dedicated exit code. Only an unexpected exit code, or successful output the parser
    // cannot read, is a genuine failure.
    function parseEntries(exitCode, noResultsCode, output, parser) {
        if (exitCode !== 0 && exitCode !== noResultsCode)
            return null;
        const entries = parser(output);
        if (exitCode === 0 && output.trim() !== "" && entries.length === 0)
            return null;
        return entries;
    }

    function onPacmanExited(exitCode): void {
        const entries = parseEntries(exitCode, 1, pacmanStdout.text ?? "", PendingUpdates.parsePacmanQu);
        if (entries === null) {
            fail("pacman -Qu exited " + exitCode);
            return;
        }
        official = entries;
        if (!hasYay) {
            busy = false;
            finishState();
            return;
        }
        yayProc.running = true;
    }

    function onYayExited(exitCode): void {
        const entries = parseEntries(exitCode, 1, yayStdout.text ?? "", PendingUpdates.parseYayQua);
        busy = false;
        if (entries === null) {
            fail("yay -Qua exited " + exitCode);
            return;
        }
        aur = entries;
        finishState();
    }

    function onCheckupdatesExited(exitCode): void {
        const entries = parseEntries(exitCode, 2, checkupdatesStdout.text ?? "", PendingUpdates.parseCheckupdates);
        busy = false;
        if (entries === null) {
            fail("checkupdates exited " + exitCode);
            return;
        }
        official = entries;
        finishState();
    }

    function finishState(): void {
        error = "";
        state = hasUpdates ? "updates" : "none";
    }

    function settleQuietly(): void {
        busy = false;
        official = [];
        aur = [];
        error = "";
        state = "none";
    }

    function fail(message): void {
        busy = false;
        error = message;
        state = "error";
    }

    Component.onCompleted: root.check()

    Timer {
        id: checkTimer

        running: true
        interval: Math.max(1, GlobalConfig.updates.checkInterval) * 1000
        repeat: true
        onTriggered: root.check()
    }

    Process {
        id: presenceProc

        command: ["sh", "-c", "for tool in pacman yay checkupdates; do command -v \"$tool\" >/dev/null 2>&1 && echo \"$tool\"; done"]
        stdout: StdioCollector {
            id: presenceStdout
        }
        stderr: StdioCollector {}
        onExited: root.handlePresence(presenceStdout.text ?? "") // qmllint disable signal-handler-parameters
    }

    Process {
        id: pacmanProc

        command: ["pacman", "-Qu"]
        stdout: StdioCollector {
            id: pacmanStdout
        }
        stderr: StdioCollector {}
        onExited: code => root.onPacmanExited(code)
    }

    Process {
        id: yayProc

        command: ["yay", "-Qua"]
        stdout: StdioCollector {
            id: yayStdout
        }
        stderr: StdioCollector {}
        onExited: code => root.onYayExited(code)
    }

    Process {
        id: checkupdatesProc

        command: ["checkupdates"]
        stdout: StdioCollector {
            id: checkupdatesStdout
        }
        stderr: StdioCollector {}
        onExited: code => root.onCheckupdatesExited(code)
    }
}
