// Cases for the update detection logic, loaded by modules/updates/selftest.qml.
//
// Fixtures are the real output captured on this machine, quoted verbatim in
// odd/tasks/package-updates-indicator.md (Evidence).

import QtQuick
import "core/PendingUpdates.js" as PendingUpdates

QtObject {
    id: cases

    function expectEqual(actual, expected, label) {
        const got = JSON.stringify(actual)
        const want = JSON.stringify(expected)
        if (got !== want)
            throw new Error(label + ": expected " + want + ", got " + got)
    }

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
}
