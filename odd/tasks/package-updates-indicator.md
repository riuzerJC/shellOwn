# Package updates: conditional bar indicator

Detect pending system updates and let the user apply them: official repos and AUR on
Arch/EndeavourOS (pacman, yay), and flake update plus rebuild on NixOS/home-manager. The UI is a bar
entry that only appears when something is pending, next to workspaces, clock and power.

Work branch: `feat/updates-indicator` (created before T1). Detection runs in-shell without
privileges; applying is never executed by an agent — only the exact argv is verified, and a single
consented manual run validates the terminal path.

## Specs

Verbatim from the request and from the user's decisions; wording and typos preserved.

S1. The scope is update-first, not package management: detect pending updates and apply them.
    "Update-first: ver pendientes y aplicarlos" — "Detecta actualizaciones (pacman -Qu, yay -Qu,
    nix) y las aplica con confirmación y log visible."
S2. The UI is a bar entry, not a new panel, and it appears only when something is detected:
    "debera aparecer en la barra donde se ven los workspaces, la fehca, el boton de apagado ahi
    debera aparecer cuando detete algo"
S3. Official repos use both detection paths: instant at start, manual refresh on demand.
    "Los dos: instantáneo + refresco manual" — "Arranca con pacman -Qu y permite refrescar a
    demanda con checkupdates desde el popout."
S4. AUR updates come from yay: "arch/endeavouos(pacman yay)".
S5. Nix means NixOS/home-manager on flakes, where updating is a rebuild, not an install:
    "nix(nixpkgs y la forma normal)" — selected "NixOS / home-manager":
    `nix flake update`, `sudo nixos-rebuild switch --flake .`, `home-manager switch --flake .` —
    "La 'actualización' es rebuild, no install."
S6. Elevation follows the hybrid model: "Híbrido (recomendado)" — "Detección in-shell; nix flake
    update in-shell; pacman/yay/nixos-rebuild/home-manager en foot."
S7. Applying is explicit and visible, never silent: confirmation plus a visible log (S1).
S8. CI is out of scope for this feature: "para mi fork el CI esta desactivado".

## Evidence

Real output captured on this machine, which is what the parser fixtures must reproduce:

    pacman -Qu:     linux-cachyos 7.0.8-1 -> 7.2.9-1 [ignorado]
    checkupdates:   7zip 26.03-1 -> 26.04-1
    yay -Qua:       sddm-silent-theme 1.5.0-1 -> 1.5.1-1 [6h26m]

Traps that the parsers must handle:

- The trailing marker is localized: `[ignorado]` under the local locale, `[ignored]` under
  `LC_ALL=C`. Match a generic trailing bracket, never the literal string.
- `yay -Qua` appends an age marker `[6h26m]` that is not an ignored marker.
- On this machine the local sync DB is stale: `pacman -Qu` reports 2 (both ignored) while
  `checkupdates` reports dozens. The stale-DB case is the normal case, not the exception.
- `nix flake update --dry-run` does not exist (NixOS/nix#7227 is still open), so flake staleness has
  to be derived from `flake.lock` plus the remote revision.

Environment: EndeavourOS; `pacman`, `yay`, `paru`, `checkupdates`, `pkexec`, `sudo`, `foot` and
`quickshell` are present; `nix`, `home-manager` and `nixos-rebuild` are absent; sudo is not
passwordless; `polkit-gnome-authentication-agent-1` is already running.

Verification mechanism: this repo has no test runner, but `quickshell -p <file.qml>` executes an
arbitrary QML file. The pure logic therefore gets a self-test harness that prints one `ok`/`not ok`
line per case. quickshell cannot exit with a status, so `scripts/updates-selftest.py` runs the
harness and owns the exit code.

## Tasks

- [x] T1 — Self-test harness: the entry `modules/updates/selftest.qml` prints one `ok`/`not ok` line
      per case, `modules/updates/selftest-cases.qml` holds the cases, and
      `scripts/updates-selftest.py` launches the entry through `quickshell -p` and exits non-zero
      when any case fails. S3-S5. Route: inline.
      Commit: `e847312b` `test(updates): add a quickshell self-test harness`
- [x] T2 — Pure parsers in `modules/updates/core/PendingUpdates.js` (`.pragma library`): parse
      `pacman -Qu`, `checkupdates` and `yay -Qua` into `[{name, from, to, ignored}]`, plus the
      `flake.lock` staleness comparison. RED first through the T1 harness against the S4 evidence
      fixtures. S3, S4, S5. Route: inline (the parent already held the fixtures and the harness, so a
      worker would have cost more than the work).
      Commit: `7e2760bf` `feat(updates): parse pending updates from pacman, checkupdates and yay`
- [x] T3 — Pure command builder `modules/updates/core/Actions.js`: `buildCommand(action, ctx)`
      returns the exact argv for the pacman/yay/nix-flake-update/rebuild actions plus the working
      directory they need, and states whether they need a terminal. Tested by argv equality, never
      executed. S6, S7. Route: inline (same reason as T2).
      Commit: `d1970086` `feat(updates): build the apply commands as verified argv`
- [x] T4 — Config: new top-level `updates` section (`CONFIG_SUBOBJECT` in
      `plugin/src/Caelestia/Config/rootnodes.hpp` plus its attached getter, mirroring `services`) with
      checkInterval, flakePath and terminal, and a default `{id: "updates"}` entry in
      `barconfig.hpp`. S2, S6. Route: `gentle-ai-worker`, then corrected by the parent after
      verification rejected the delivery (see L10).
      Commit: `feat(updates): add the updates config section`
      Verified: clang-format passes on every touched C++ file, and a runtime probe reads
      `GlobalConfig.updates.checkInterval=1800 flakePath='' terminal=''` and the default `updates`
      entry in `bar.entries` under a virgin config. See L10 and L11.
- [x] T5 — `services/Updates.qml` singleton: exposes a state (idle/checking/none/updates/error),
      polls on `checkInterval`, detects the Arch path only (`pacman -Qu` plus `yay -Qua`), and offers
      a manual `refresh()` that runs `checkupdates`. The Nix detection path is T8, per L12. S1, S3,
      S4. Route: `gentle-ai-worker`, verification reproduced by the parent.
      Commit: `feat(updates): add the update detection service`
      Verified: the parent reproduced the delivered probe values against the real commands on this
      machine, plus the security audit and the exit-code handling. See L13 and L14.
- [ ] T6 — `modules/bar/components/Updates.qml` plus its `DelegateChoice roleValue: "updates"` in
      `modules/bar/Bar.qml`: renders only when updates are pending and occupies no space otherwise.
      S2. Route: `gentle-ai-worker`. Commit: `feat(updates): add the conditional bar indicator`
- [ ] T7 — `modules/bar/popouts/Updates*.qml`: lists pending packages as name, from -> to, marks
      ignored entries, offers the apply action through the terminal, offers the manual `checkupdates`
      refresh, and renders checking/empty/error states. S1, S3, S6, S7. Route: `gentle-ai-worker`.
      Commit: `feat(updates): add the updates popout`
- [ ] T8 — Nix branch end to end: the flake path detection itself (the locked revision from
      `flake.lock` compared against the remote revision, since `nix flake update --dry-run` does not
      exist), `nix flake update` in-shell, rebuild through the terminal. Validated by the user on
      their NixOS machine, because `nix` is absent here. S5. Route: `gentle-ai-worker` plus user
      validation. Commit: `feat(updates): support NixOS and home-manager flake updates`
- [ ] T9 — README section for detection, the hybrid elevation model and the Nix requirement, with
      the manual evidence recorded here; keep the new QML free of added
      `qml-lint-conventions.py` violations. S1-S7. Route: inline.
      Commit: `docs(updates): document detection, elevation and Nix support`

## Log

L1. Original request, verbatim:
    "para mi fork el CI esta desactivado y la nueva funcionalidad sera algo especial para
    arch/endeavouos(pacman yay)/nix(nixpkgs y la forma normal)"
    (preceded by an upstream sync of main, merge 4e8de168, which left the tree buildable)

L2. Decisions taken by the user, verbatim:
    scope: "Update-first: ver pendientes y aplicarlos"
    location: "debera aparecer en la barra donde se ven los workspaces, la fehca, el boton de
    apagado ahi debera aparecer cuando detete algo"
    nix: "NixOS / home-manager"
    elevation: "Híbrido (recomendado)"
    nix verification: "Tengo la máquina NixOS para probar"
    arch detection: "Los dos: instantáneo + refresco manual"

L3. Evidence gathered before writing anything (see the Evidence section): the exact output of
    `pacman -Qu`, `checkupdates` and `yay -Qua`; the localized ignored marker; the stale local DB;
    the absence of `nix` on this machine; the already-running `polkit-gnome` agent; and
    `quickshell -p` as the only available execution harness.

L4. Design decisions taken by the orchestrator:
    - A bar entry with id `updates`, gated by config, rather than a new panel or a servicespanel
      adapter (S2 asks for a bar indicator, so the servicespanel adapter path was rejected).
    - Options live in a new top-level `updates` config section, mirroring the fork's own `services`
      section precedent.
    - Detection and the command builder are pure functions so they are testable through the T1
      harness; execution is not tested by an agent.
    - Arch and Nix paths coexist and are selected by tool presence, so the same build supports both
      machines.

L5. Boundaries:
    - No agent ever runs `pacman -Syu`, `yay -Syu`, `nix flake update` or a rebuild: those mutate
      the system. Only argv equality and the user's consented manual run validate them.
    - Not in scope: install/remove/search of individual packages, flatpak, paru-specific handling,
      and any CI wiring (S8).
    - `paru` is installed but is not part of this feature (S4 names yay only).

L6. Harness constraints discovered while building T1: quickshell exposes no exit API at all
    (`Qt.exit` only emits a signal nothing handles, and `quickshell kill` would also kill unrelated
    instances of the running shell), so the QML harness terminates itself by pid and
    `scripts/updates-selftest.py` owns the exit code. A module under test that does not exist yet
    surfaces as `qrc:/qs-blackhole` rather than as a named missing file, so the harness now labels
    that case. Observed RED: `exit 1` with `not ok 1 - scripts/updates-cases.qml loads`.

L7. Parser decision made before implementing T2: the trailing bracket in `pacman -Qu` is treated as
the ignored marker whatever its text, because `[ignorado]` is localized and any literal match would
break under another locale. A future non-ignored bracket in that position would under-count
actionable updates, which is the safe direction, and the yay parser ignores the bracket entirely.

L8. quickshell sandboxes relative imports to the config root, which is the directory of the entry
    file: an entry under `scripts/` cannot reach `modules/` and resolves to `qrc:/qs-blackhole`. The
    entry and its cases therefore live inside the module tree they test
    (`modules/updates/selftest.qml` and `selftest-cases.qml`, importing `core/PendingUpdates.js`
    downward), and only the runner that owns the exit code stays in `scripts/`.

L9. Command-shape decision for T3: the Nix actions keep the literal forms from S5 (`nix flake
    update` and `--flake .`) and carry the configured flake directory as their working directory
    instead of rewriting the path into `--flake <dir>`, so the shell runs exactly the commands the
    user already runs. The terminal wrapper re-enters that directory itself, so the shape does not
    depend on the spawner honouring a working directory. `yay` is never wrapped in sudo because it
    refuses to build as root and raises its own prompt, and `nix flake update` stays in the shell
    because it needs no privileges.

L10. T4 delivery rejected on first review, then corrected. The worker reported a green build twice,
    but a green build was not enough: it appended `#include "updatesconfig.hpp"` after
    `#include "utilitiesconfig.hpp"`, which breaks the repo's format gate. `.clang-format` uses
    `IncludeBlocks: Regroup` and `SortIncludes: CaseSensitive`, so the violation is reported at the
    first line of the regrouped block rather than at the added line. Proven by comparing
    `git show HEAD:<path> | clang-format --dry-run --Werror --assume-filename=<path>` (exit 0) with
    the working tree (exit 1), using the untouched `serviceconfig.hpp` as a control to confirm the
    local clang-format is a valid gate. Correct order is `tokens.hpp`, `updatesconfig.hpp`,
    `userpaths.hpp`, `utilitiesconfig.hpp`. The fork has CI disabled, so nothing else would have
    caught it.

L11. The default bar entry is correct in code but inert on this machine. Runtime probe, with
    `QML2_IMPORT_PATH=$PWD/build/qml` and `QT_QPA_PLATFORM=offscreen`:
      with the user's config:  bar.entries ends `...statusIcons:true,power:true`
      with an isolated `XDG_CONFIG_HOME` inside the repo: `...statusIcons:true,updates:true,power:true`
    The shell does not materialise a config file by itself (no JSON was written to the isolated
    directory), so the difference proves `~/.config/caelestia/shell.json` pins `bar.entries` and
    overrides the code default. Consequence for S2: the user must add
    `{"id": "updates", "enabled": true}` to that list, and T9 has to document it. The same probe
    also proved the QML read path works at runtime: `checkInterval=1800 flakePath='' terminal=''`.

L12. Task boundary adjusted after L10/L11: T5 owns the state machine, the polling interval, the
    manual `checkupdates` refresh and the Arch detection only. The Nix detection path moves into T8,
    which already owned the Nix branch end to end, because it needs its own decision (comparing the
    locked revision against the remote one) and its own external validation.

L13. T5 verification reproduced independently, not taken from the worker's report. Reference counts
    taken from the same machine: `pacman -Qu` returns 2 rows and `yay -Qua` returns 17. The probe run
    by the parent printed exactly `state=updates official=2 aur=17 ignoredCount=2 actionableCount=17
    hasUpdates=true error=''`. The refresh claim was also reproduced: `checkupdates` returns 267 rows,
    matching the delivered `official=267` after `refresh()`. Security audit of the service: the only
    commands present are the tool presence probe and `pacman -Qu`, `yay -Qua`, `checkupdates`, so
    nothing privileged or mutating is reachable from detection, and a successful run whose output the
    parser cannot read is reported as `error` rather than as "no updates".

L14. The offscreen command prescribed for T5 verification was wrong and is now retracted: importing
    `qs.services` pulls in `services/NotifData.qml:80`, a `PanelWindow`, which the offscreen platform
    plugin cannot provide, so any probe that imports `qs.services` fails at config load no matter what
    the feature does. Runtime probes for the service and for anything under `modules/bar` must run
    under the real Wayland backend, and a probe that only needs `Caelestia.Config` can still use
    offscreen. Separately, the delivered warning that a stale `build/qml/Caelestia/libcaelestiaplugin.so`
    resolves a Config without `updates` did NOT reproduce: a probe importing both `qs.services` and
    `Caelestia.Config` printed `checkInterval=1800`, so `Caelestia.Config` is its own freshly built
    module and no core plugin rebuild is required.
