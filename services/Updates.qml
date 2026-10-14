pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import "../modules/updates/core/Actions.js" as Actions
import "../modules/updates/core/PendingUpdates.js" as PendingUpdates

// Detects pending updates without ever mutating the system. The path is chosen by tool presence:
// when `nix` is installed the NixOS/home-manager path runs and the machine never reaches the
// pacman commands; otherwise `pacman -Qu` and `yay -Qua` are the instant, offline paths and
// `checkupdates` is the slower, accurate path behind the manual refresh. Tool presence is probed
// once so a machine without a given tool settles quietly instead of reporting a failure for a
// command that was never expected to exist.
//
// The Nix check cannot use `nix flake update --dry-run` (NixOS/nix#7227), so it compares the
// revision `flake.lock` pins against the revision the remote advertises. It only reads and queries:
// it never writes the flake and never runs anything privileged.
Singleton {
    id: root

    property string state: "idle"
    property list<var> official: []
    property list<var> aur: []
    property string error: ""

    readonly property int ignoredCount: official.filter(entry => entry.ignored).length
    readonly property int actionableCount: official.filter(entry => !entry.ignored).length + aur.length
    readonly property bool hasUpdates: actionableCount > 0 || nixStale
    // Read defensively and floored. `GlobalConfig.updates` does not exist when the plugin predates this
    // section, and an unguarded binding threw, which left the timer at its one second default and
    // polled the package managers once a second. A missing configuration must degrade, never spin.
    readonly property int pollIntervalMs: {
        let seconds = 0;
        try {
            seconds = GlobalConfig.updates.checkInterval;
        } catch (e) {
            seconds = 0;
        }
        return Actions.pollIntervalMs(seconds);
    }

    property bool toolsProbed: false
    property bool hasPacman: false
    property bool hasYay: false
    property bool hasCheckupdates: false
    property bool hasNix: false
    property bool hasGit: false
    property bool hasNixosRebuild: false
    property bool hasHomeManager: false
    property bool refreshQueued: false
    property bool busy: false

    // The Nix outcome, false whenever it cannot be determined: no nix, no flake path, unreadable
    // lock, missing git, absent input, no remote ref, or a remote query that did not succeed.
    property bool nixStale: false
    property string nixLockedRev: ""
    property var nixRemote: null

    // The instant path: pacman first, then yay once it finishes. Kept as a guard against overlapping
    // polls and against a check that lands before the one-time presence probe has reported.
    function check(): void {
        if (busy)
            return;
        if (!toolsProbed) {
            probe();
            return;
        }
        if (hasNix) {
            checkNix();
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
        if (hasNix) {
            // Nix has no separate accurate refresh: re-running the check re-queries the remote.
            check();
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
        hasNix = tools.indexOf("nix") !== -1;
        hasGit = tools.indexOf("git") !== -1;
        hasNixosRebuild = tools.indexOf("nixos-rebuild") !== -1;
        hasHomeManager = tools.indexOf("home-manager") !== -1;
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

    // The Nix path: read the lock, resolve what `nixpkgs` tracks, ask the remote for its current
    // revision and compare. A non-zero remote exit is unknown, never stale.
    function checkNix(): void {
        busy = true;
        error = "";
        state = "checking";
        nixStale = false;
        const base = String(GlobalConfig.updates.flakePath ?? "");
        if (!hasGit || base === "") {
            finishNix();
            return;
        }
        const lockPath = base.endsWith("/") ? base + "flake.lock" : base + "/flake.lock";
        lockProc.command = ["cat", lockPath];
        lockProc.running = true;
    }

    function lsRemoteCommand(remote): var {
        const patterns = [remote.ref];
        // An annotated tag is advertised as both the tag object and its peeled commit; the lock
        // stores the commit, so the peeled ref is requested too or a tag pin would always look stale.
        if (remote.ref.indexOf("refs/tags/") === 0)
            patterns.push(remote.ref + "^{}");
        return ["git", "ls-remote", remote.url].concat(patterns);
    }

    function onLockExited(exitCode): void {
        if (exitCode !== 0) {
            finishNix();
            return;
        }
        const lockText = lockStdout.text ?? "";
        const lockedRev = PendingUpdates.flakeLockedRev(lockText, "nixpkgs");
        const remote = PendingUpdates.flakeRemoteRef(lockText, "nixpkgs");
        if (lockedRev === "" || remote === null) {
            finishNix();
            return;
        }
        nixLockedRev = lockedRev;
        nixRemote = remote;
        remoteProc.command = lsRemoteCommand(remote);
        remoteProc.running = true;
    }

    function onNixRemoteExited(exitCode): void {
        if (exitCode !== 0) {
            finishNix();
            return;
        }
        const remoteRev = PendingUpdates.parseLsRemote(remoteStdout.text ?? "", nixRemote ? nixRemote.ref : "");
        nixStale = PendingUpdates.flakeIsStale(nixLockedRev, remoteRev);
        finishNix();
    }

    function finishNix(): void {
        busy = false;
        error = "";
        state = hasUpdates ? "updates" : "none";
    }

    Component.onCompleted: root.check()

    Timer {
        id: checkTimer

        running: true
        interval: root.pollIntervalMs
        repeat: true
        onTriggered: root.check()
    }

    Process {
        id: presenceProc

        command: ["sh", "-c", "for tool in pacman yay checkupdates nix nixos-rebuild home-manager git; do command -v \"$tool\" >/dev/null 2>&1 && echo \"$tool\"; done"]
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

    Process {
        id: lockProc

        stdout: StdioCollector {
            id: lockStdout
        }
        stderr: StdioCollector {}
        onExited: code => root.onLockExited(code)
    }

    Process {
        id: remoteProc

        stdout: StdioCollector {
            id: remoteStdout
        }
        stderr: StdioCollector {}
        onExited: code => root.onNixRemoteExited(code)
    }
}
