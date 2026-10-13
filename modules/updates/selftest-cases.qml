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
            name: "flake.lock exposes the remote branch of a github input",
            run: function () {
                cases.expectEqual(PendingUpdates.flakeRemoteRef(cases.lockText, "nixpkgs"), {
                    url: "https://github.com/NixOS/nixpkgs",
                    ref: "refs/heads/nixos-unstable"
                }, "remote ref")
            }
        },
        {
            name: "a fully qualified tag ref stays a tag",
            run: function () {
                cases.expectEqual(PendingUpdates.flakeRemoteRef(cases.lockText, "flake-utils"), {
                    url: "https://github.com/numtide/flake-utils",
                    ref: "refs/tags/v1.2.3"
                }, "tag ref")
            }
        },
        {
            name: "no remote ref is derived when the lock cannot pin one",
            run: function () {
                cases.expectEqual(PendingUpdates.flakeRemoteRef(cases.lockText, "revonly"), null, "rev only")
                cases.expectEqual(PendingUpdates.flakeRemoteRef(cases.lockText, "quickshell"), null, "non github type")
                cases.expectEqual(PendingUpdates.flakeRemoteRef(cases.lockText, "missing"), null, "absent input")
                cases.expectEqual(PendingUpdates.flakeRemoteRef("{ not json", "nixpkgs"), null, "malformed lock")
            }
        },
        {
            name: "git ls-remote output is reduced to the revision of the requested ref",
            run: function () {
                const branch = "1111111111111111111111111111111111111111\trefs/heads/main\n"
                cases.expectEqual(PendingUpdates.parseLsRemote(branch, "refs/heads/main"), "1111111111111111111111111111111111111111", "branch")
                const tagged = "2222222222222222222222222222222222222222\trefs/tags/v1\n3333333333333333333333333333333333333333\trefs/tags/v1^{}\n"
                cases.expectEqual(PendingUpdates.parseLsRemote(tagged, "refs/tags/v1"), "3333333333333333333333333333333333333333", "peeled tag")
                cases.expectEqual(PendingUpdates.parseLsRemote("", "refs/heads/main"), "", "no output")
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
            name: "the in-shell apply script enters the flake directory and quotes it",
            run: function () {
                const command = Actions.buildCommand("nixFlakeUpdate", { flakePath: "/etc/nixos" })
                cases.expectEqual(Actions.shellCommand(command), "cd /etc/nixos && nix flake update", "script")
                const spaced = Actions.buildCommand("nixFlakeUpdate", { flakePath: "work dir" })
                cases.expectContains(Actions.shellCommand(spaced), "cd 'work dir' &&", "quoted directory")
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
        },
        {
            name: "the terminal resolves from config, then the environment, then the default",
            run: function () {
                cases.expectEqual(Actions.resolveTerminal("kitty", "foot"), "kitty", "configured wins")
                cases.expectEqual(Actions.resolveTerminal("", "alacritty"), "alacritty", "environment second")
                cases.expectEqual(Actions.resolveTerminal("", ""), "foot", "default last")
                cases.expectEqual(Actions.resolveTerminal(undefined, undefined), "foot", "absent values")
            }
        },
        {
            name: "the apply plan keeps the Arch steps in order",
            run: function () {
                const plan = Actions.applyPlan(["pacman", "yay"], cases.context)
                cases.expectEqual(plan.map(function (step) { return step.action }), ["pacman", "yay"], "action order")
                cases.expectEqual(plan.map(function (step) { return step.argv.join(" ") }), ["sudo pacman -Syu", "yay -Syu"], "argv order")
            }
        },
        {
            name: "the apply plan keeps nix flake update before exactly one rebuild",
            run: function () {
                const plan = Actions.applyPlan(["nixFlakeUpdate", "nixosRebuild"], cases.context)
                cases.expectEqual(plan.length, 2, "step count")
                cases.expectEqual(plan[0].action, "nixFlakeUpdate", "first step")
                cases.expectEqual(plan[1].action, "nixosRebuild", "second step")
                cases.expectEqual(plan[0].needsTerminal, false, "flake update stays in-shell")
                cases.expectEqual(plan[1].needsTerminal, true, "rebuild needs a terminal")
            }
        },
        {
            name: "the apply plan drops unknown actions and keeps the known order",
            run: function () {
                const plan = Actions.applyPlan(["bogus", "pacman", "constructor", "yay"], cases.context)
                cases.expectEqual(plan.map(function (step) { return step.action }), ["pacman", "yay"], "known actions only")
            }
        },
        {
            name: "chainCommands runs the steps in order and stops at the first failure",
            run: function () {
                const plan = Actions.applyPlan(["pacman", "yay"], cases.context)
                cases.expectEqual(Actions.chainCommands(plan), "sudo pacman -Syu && yay -Syu", "chained script")
                const nix = Actions.applyPlan(["nixFlakeUpdate", "nixosRebuild"], cases.context)
                cases.expectContains(Actions.chainCommands(nix), "cd /etc/nixos && nix flake update && cd /etc/nixos && sudo nixos-rebuild switch --flake .", "per-step working directory")
            }
        },
        {
            name: "a built script is wrapped in the same terminal hold tail",
            run: function () {
                const script = Actions.chainCommands(Actions.applyPlan(["pacman", "yay"], cases.context))
                const wrapper = Actions.terminalScript("foot", script, true)
                cases.expectEqual(wrapper[0], "foot", "terminal")
                const body = wrapper[wrapper.length - 1]
                cases.expectContains(body, "sudo pacman -Syu && yay -Syu", "chained commands kept")
                cases.expectContains(body, "read ", "hold tail")
                const quick = Actions.terminalScript("foot", script, false)
                cases.expectTrue(quick[quick.length - 1].indexOf("read ") === -1, "no hold when not asked")
            }
        }
    ]

    // Shaped after the real flake.lock files on this machine (the shell's own and its dependencies):
    // a github input carries owner, repo and an optional ref, a rev-only input has no ref, and a
    // git input has a url instead of owner/repo.
    property string lockText: `{
  "nodes": {
    "flake-utils": {
      "locked": {
        "lastModified": 1740000000,
        "narHash": "sha256-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=",
        "owner": "numtide",
        "repo": "flake-utils",
        "rev": "1111111111111111111111111111111111111111",
        "type": "github"
      },
      "original": {
        "owner": "numtide",
        "ref": "refs/tags/v1.2.3",
        "repo": "flake-utils",
        "type": "github"
      }
    },
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
        "ref": "nixos-unstable",
        "repo": "nixpkgs",
        "type": "github"
      }
    },
    "quickshell": {
      "locked": {
        "lastModified": 1791448974,
        "narHash": "sha256-lPbqsyAD5ZoGFMZ1eqAlTULfeP5Nwhy+XvOowF7BE+E=",
        "ref": "refs/heads/master",
        "rev": "4f508be500dea6e5732cc3d50382a0048b17e7b1",
        "type": "git",
        "url": "https://git.outfoxxed.me/outfoxxed/quickshell"
      },
      "original": {
        "type": "git",
        "url": "https://git.outfoxxed.me/outfoxxed/quickshell"
      }
    },
    "revonly": {
      "locked": {
        "lastModified": 1787906858,
        "narHash": "sha256-YZelgEZflFNwGutX4/tIzBdbOeghJgE2oDw0uWYGxns=",
        "owner": "soramanew",
        "repo": "m3shapes",
        "rev": "32ad9ce328bb77ed349b40a3be10ee9ea610b8ab",
        "type": "github"
      },
      "original": {
        "owner": "soramanew",
        "repo": "m3shapes",
        "rev": "32ad9ce328bb77ed349b40a3be10ee9ea610b8ab",
        "type": "github"
      }
    },
    "root": {
      "inputs": {
        "flake-utils": "flake-utils",
        "nixpkgs": "nixpkgs",
        "quickshell": "quickshell",
        "revonly": "revonly"
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
