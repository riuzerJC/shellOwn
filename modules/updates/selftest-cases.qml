// Cases for the update detection logic, loaded by modules/updates/selftest.qml.
//
// Fixtures are the real output captured on this machine, quoted verbatim in
// odd/tasks/package-updates-indicator.md (Evidence). The commands asserted here are the ones the
// user named in S5 and S6.

import QtQuick
import "core/Actions.js" as Actions
import "core/PendingUpdates.js" as PendingUpdates

QtObject {
    id: cases

    property var context: ({
        flakePath: "/etc/nixos",
        terminal: "foot"
    })

    property var entries: [
        {
            name: "pacman -Qu parses a localized ignored upgrade",
            run: function () {
                cases.expectEqual(PendingUpdates.parsePacmanQu("linux-cachyos 7.0.8-1 -> 7.2.9-1 [ignorado]\n"), [{
                    name: "linux-cachyos",
                    from: "7.0.8-1",
                    to: "7.2.9-1",
                    ignored: true
                }], "entries")
            }
        },
        {
            name: "pacman -Qu does not depend on the localized marker text",
            run: function () {
                cases.expectEqual(PendingUpdates.parsePacmanQu("linux-cachyos 7.0.8-1 -> 7.2.9-1 [ignored]"), [{
                    name: "linux-cachyos",
                    from: "7.0.8-1",
                    to: "7.2.9-1",
                    ignored: true
                }], "entries")
            }
        },
        {
            name: "checkupdates parses an official upgrade as actionable",
            run: function () {
                cases.expectEqual(PendingUpdates.parseCheckupdates("7zip 26.03-1 -> 26.04-1\n"), [{
                    name: "7zip",
                    from: "26.03-1",
                    to: "26.04-1",
                    ignored: false
                }], "entries")
            }
        },
        {
            name: "yay -Qua keeps the age marker out of the new version",
            run: function () {
                cases.expectEqual(PendingUpdates.parseYayQua("sddm-silent-theme 1.5.0-1 -> 1.5.1-1 [6h26m]\n"), [{
                    name: "sddm-silent-theme",
                    from: "1.5.0-1",
                    to: "1.5.1-1",
                    ignored: false
                }], "entries")
            }
        },
        {
            name: "several lines are parsed in order and empty output yields nothing",
            run: function () {
                const many = "7zip 26.03-1 -> 26.04-1\nadwaita-cursors 50.0-1 -> 51.0-1\n"
                cases.expectEqual(PendingUpdates.parseCheckupdates(many).length, 2, "entry count")
                cases.expectEqual(PendingUpdates.parseCheckupdates(""), [], "entries")
            }
        },
        {
            name: "flake.lock exposes the locked revision of a named input",
            run: function () {
                cases.expectEqual(PendingUpdates.flakeLockedRev(cases.lockText, "nixpkgs"), "0f2e1a9c4b3d5e6f708192a3b4c5d6e7f8091a2b", "locked rev")
            }
        },
        {
            name: "a flake input counts as stale only when the remote revision differs",
            run: function () {
                cases.expectEqual(PendingUpdates.flakeIsStale("abc123", "abc123"), false, "same revision")
                cases.expectEqual(PendingUpdates.flakeIsStale("abc123", "def456"), true, "different revision")
            }
        },
        {
            name: "pacman upgrades through sudo, in a terminal",
            run: function () {
                const command = Actions.buildCommand("pacman", cases.context)
                cases.expectEqual(command.argv, ["sudo", "pacman", "-Syu"], "argv")
                cases.expectEqual(command.needsTerminal, true, "needsTerminal")
            }
        },
        {
            name: "yay is never wrapped in sudo because it refuses to build as root",
            run: function () {
                const command = Actions.buildCommand("yay", cases.context)
                cases.expectEqual(command.argv, ["yay", "-Syu"], "argv")
                cases.expectEqual(command.needsTerminal, true, "needsTerminal")
            }
        },
        {
            name: "nix flake update keeps the command the user typed and runs in-shell",
            run: function () {
                const command = Actions.buildCommand("nixFlakeUpdate", cases.context)
                cases.expectEqual(command.argv, ["nix", "flake", "update"], "argv")
                cases.expectEqual(command.cwd, "/etc/nixos", "working directory")
                cases.expectEqual(command.needsTerminal, false, "needsTerminal")
            }
        },
        {
            name: "the rebuild actions keep --flake . and run inside the configured flake",
            run: function () {
                const rebuild = Actions.buildCommand("nixosRebuild", cases.context)
                cases.expectEqual(rebuild.argv, ["sudo", "nixos-rebuild", "switch", "--flake", "."], "nixos argv")
                cases.expectEqual(rebuild.cwd, "/etc/nixos", "nixos working directory")
                cases.expectEqual(rebuild.needsTerminal, true, "nixos needsTerminal")
                const home = Actions.buildCommand("homeManager", cases.context)
                cases.expectEqual(home.argv, ["home-manager", "switch", "--flake", "."], "home-manager argv")
                cases.expectEqual(home.cwd, "/etc/nixos", "home-manager working directory")
                cases.expectEqual(home.needsTerminal, true, "home-manager needsTerminal")
            }
        },
        {
            name: "the flake path defaults to the current directory and an unknown action yields nothing",
            run: function () {
                cases.expectEqual(Actions.buildCommand("nixosRebuild", {}).cwd, ".", "default working directory")
                cases.expectEqual(Actions.buildCommand("bogus", cases.context), null, "unknown action")
                cases.expectEqual(Actions.buildCommand("constructor", cases.context), null, "inherited name")
            }
        },
        {
            name: "the terminal enters the working directory, quotes it and holds the window open",
            run: function () {
                const wrapper = Actions.terminalCommand("foot", ["sudo", "pacman", "-Syu"], "workdir with space", true)
                cases.expectEqual(wrapper[0], "foot", "terminal")
                const script = wrapper[wrapper.length - 1]
                cases.expectContains(script, "'workdir with space'", "quoted working directory")
                cases.expectContains(script, "sudo pacman -Syu", "command")
                cases.expectContains(script, "read ", "hold")
                const quick = Actions.terminalCommand("foot", ["yay", "-Syu"], "", false)
                cases.expectTrue(quick[quick.length - 1].indexOf("read ") === -1, "no hold when not asked")
            }
        }
    ]

    property string lockText: `{
  "nodes": {
    "nixpkgs": {
      "locked": {
        "lastModified": 1745395812,
        "narHash": "sha256-9Bbl2t2vhLdrJfQrBU4lAUBLDgIfnAXYFBvXGWK2YfA=",
        "owner": "NixOS",
        "repo": "nixpkgs",
        "rev": "0f2e1a9c4b3d5e6f708192a3b4c5d6e7f8091a2b",
        "type": "github"
      },
      "original": {
        "owner": "NixOS",
        "repo": "nixpkgs",
        "type": "github"
      }
    },
    "root": {
      "inputs": {
        "nixpkgs": "nixpkgs"
      }
    }
  },
  "root": "root",
  "version": 7
}`

    function expectEqual(actual, expected, label) {
        const got = JSON.stringify(actual)
        const want = JSON.stringify(expected)
        if (got !== want)
            throw new Error(label + ": expected " + want + ", got " + got)
    }

    function expectTrue(value, label) {
        if (value !== true)
            throw new Error(label + ": expected true, got " + JSON.stringify(value))
    }

    function expectContains(haystack, needle, label) {
        if (String(haystack).indexOf(needle) === -1)
            throw new Error(label + ": expected to contain " + JSON.stringify(needle) + ", got " + JSON.stringify(haystack))
    }
}
