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
- [x] T6 — `modules/bar/components/Updates.qml` plus its `DelegateChoice roleValue: "updates"` in
      `modules/bar/Bar.qml`: renders only when updates are pending and occupies no space otherwise.
      S2. Route: `gentle-ai-worker`, verification reproduced by the parent.
      Commit: `feat(updates): add the conditional bar indicator`
      Verified: lint clean, both visibility gates read `Services.Updates.hasUpdates`, and the parent's
      windowed probe read `indicator=true` with `hasUpdates=true`. See L17, which also corrects the
      probe shape that produced a misleading `visible=false`. Not verified here: the full bar loading at
      runtime and the visual placement, which need the user's eyes.
- [x] T7 — `modules/bar/popouts/Updates.qml` (name `"updates"`), registered in
      `modules/bar/popouts/Content.qml`: lists pending packages as name and from -> to in two groups,
      marks ignored entries, offers the manual `checkupdates` refresh, renders checking/empty/error
      states, and applies only through an explicit two-step confirmation that lists the exact
      commands. Also added the pure `Actions.resolveTerminal`. S1, S3, S6, S7. Route:
      `gentle-ai-worker`, verification reproduced by the parent.
      Commit: `feat(updates): add the updates popout`
      Verified: the parent read the whole component and the registration diff, reproduced the 14/14
      harness and a clean lint, and audited the apply flow. See L15.
- [x] T8 — Nix branch end to end: the flake path detection itself (the locked revision from
      `flake.lock` compared against the remote revision, since `nix flake update --dry-run` does not
      exist), `nix flake update` in-shell, rebuild through the terminal. It also closed T7's in-shell
      gap by extracting `Actions.shellCommand` instead of executing anything. Validated by the user on
      their NixOS machine, because `nix` is absent here. S5. Route: `gentle-ai-worker`, verification
      reproduced by the parent. Commit: `feat(updates): support NixOS and home-manager flake updates`
      Verified: harness 19 of 19, lint clean, every "unknown never stale" exit read in the service, and
      the Arch path re-probed after the change with identical numbers to T5. See L18.
- [x] T10 — Sequence the apply steps, a defect found while verifying T8. `applyUpdates()` fired every
      target with `Quickshell.execDetached`, which does not wait, so two steps ran at once: `pacman`
      and `yay` would fight over the pacman database lock, and `nix flake update` would race the
      rebuild that must see the updated lock. Fixed by building an ordered plan and running it as one
      sequence — a single terminal for the Arch chain, and for Nix a `Process` for the in-shell
      `nix flake update` whose exit launches the rebuild, stopping the sequence when a step fails.
      S1, S6, S7. Route: `gentle-ai-worker`, verification reproduced by the parent.
      Commit: `fix(updates): sequence the apply steps instead of racing them`
      Verified: harness 19 to 24 cases all passing, lint clean, the sequencing read as control flow
      (the rebuild is unreachable unless `nix flake update` exits 0), and the popout loaded through
      the real static module route with `targets=yay plan=yay terminal=foot`. See L20.
- [ ] T9 — README section for detection, the hybrid elevation model and the Nix requirement, with
      the manual evidence recorded here. It must also state the two caveats that need the user: that a
      `shell.json` which pins `bar.entries` has to gain `{"id": "updates", "enabled": true}` by hand,
      and that the installed plugin has to be rebuilt for `GlobalConfig.updates` to exist. It also
      notes that installing `nix` on an Arch machine switches detection to the Nix path exclusively,
      and that a flake input pinned to a tag stored as a bare ref stays "unknown" rather than risk a
      wrong answer. Keep the new QML free of added `qml-lint-conventions.py` violations. S1-S7.
      Route: inline. Commit: `docs(updates): document detection, elevation and Nix support`
- [x] T11 — Independent verification of the whole diff, required because the change builds shell
      commands and alters a shared default. Route: `gentle-ai-verify`, findings dispositioned by the
      parent. Commit: `fix(updates): close the findings from the independent review`
      Verdict: all five questions confirmed against the code, no high or medium finding. Three low
      findings fixed, one refuted by measurement, two recorded. See L22.
- [x] T12 — Harden against a missing config section, a defect found in production use, not by any
      review. With the installed plugin and `updates` enabled in the bar, `GlobalConfig.updates` is
      undefined, and the timer's interval binding threw, leaving the timer at its one second default:
      the shell polled the package managers once a second and hammered the AUR. The popout's `plan`
      also stayed undefined, so apply silently did nothing. Fixed with a pure
      `Actions.pollIntervalMs` (fallback 1800, floor 60), guarded reads in the service and the popout,
      and tolerance for an absent plan, which makes the config section optional rather than required.
      S1, S3, S6. Route: inline. Commit: `fix(updates): never let a missing config section spin the poll`
      Verified: case 26 RED then green, harness 26 of 26, lint clean, a probe without
      `QML2_IMPORT_PATH` printing `terminal='foot' plan=yay` with no TypeError, and ten quiet samples in
      the live shell. See L23.

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

L15. T7 verification reproduced by the parent, not taken from the report. Harness: 14 of 14 passing
    (case 14 pins `resolveTerminal` precedence: configured, then environment, then `foot`, and also
    undefined arguments). Lint: clean for every touched file. Apply-flow audit on the whole component:
    `execDetached` appears only inside `applyUpdates()`, `applyUpdates()` is reachable only from the
    Apply button inside the confirmation panel, and the panel prints the exact argv from
    `Actions.buildCommand`, so the user reads what is going to run before it runs. Nothing privileged
    is spawned by the popout itself: `pacman` is wrapped in a terminal, where the sudo prompt lives.
    The AUR entries appear as a normal entry: no per-package management was added, which keeps S1's
    update-first scope.

L16. Gap handed to T8: the popout's in-shell apply branch (`needsTerminal === false`, which is
    `nix flake update`) calls `inShellScript`, and neither it nor that path is covered by the harness,
    because the target list on an Arch-only machine can only produce `pacman` and `yay`. T8 must
    exercise it, and it is the only task that can.

L17. T6 verification, and a correction to the probe shape prescribed for it. The delivered probe printed
    `visible=false` while `Updates.hasUpdates` was true, which would mean the indicator never appears.
    Settled by evidence rather than by accepting the explanation: the QtQuick type metadata shows
    `Item.visible` has `read: "isVisible"`, so it returns EFFECTIVE visibility, which folds in the
    window. A parentless, windowless item therefore cannot report true once its setter has run. The
    parent then measured both contexts in one probe run:
      no window:   constantTrue=true  indicator=false  parent=null
      in a window: constantTrue=true  indicator=true
    The windowed reading is the one that matters and it is true, so the binding drives the indicator in
    the context the bar puts it in. Warning for future probes: a constant `visible: true` is NOT a valid
    control here, because true is already the default, so the setter early-returns and effective
    visibility is never recomputed; it can read true in the same context where a bound item reads false.
    Measure the component where it is meant to live, and treat a windowless reading as meaningless.
    Also confirmed by reading the imports of `modules/bar/Bar.qml`: it already does `import "components"`
    unqualified and `import qs.services` unqualified, so the bare name `Updates` denotes BOTH the new
    component and the service singleton. The `BarComponents.Updates` and `Services.Updates`
    qualifications are therefore necessary, not redundant.
    Still unverified, and left to the user's manual check: the full bar loading at runtime and the actual
    visual placement in the running bar.

L18. T8 verification by the parent: harness grew from 14 to 19 cases and all pass (reproduced); lint
    clean on all five touched files (reproduced); the pure `flakeRemoteRef`, `parseLsRemote` and
    `shellCommand` read line by line; and every exit of the Nix path checked against the rule that an
    unknown answer is never stale (no git, no flakePath, `cat` failure, unreadable lock, absent
    `nixpkgs` input, no ref, non-zero `git ls-remote`) all end in `nixStale = false`. Two deviations
    from the brief were justified by evidence and accepted: an annotated tag is advertised twice, so
    the service also asks for `<ref>^{}` and `parseLsRemote` prefers the peeled revision (otherwise a
    tag pin would look permanently stale), and a lock that stores a tag as a bare ref cannot be told
    apart from a branch, so it degrades to "unknown" instead of answering wrongly. The parent also
    re-probed the Arch path, because the brief's blanket "never execute pacman/yay" made the worker
    avoid re-exercising it after changing `check()` and the presence probe: the numbers came back
    identical to T5 with `nixStale=false`, so there is no regression. Lesson for future briefs: a
    blanket prohibition on executing a command also blocks the read-only detection that a regression
    check needs; say "never run an apply action" instead.

L19. Defect found during T8 verification, in T7's apply flow and in the design this document pinned for
    it. `applyUpdates()` launches every target with `Quickshell.execDetached`, which returns
    immediately, so the steps are concurrent rather than ordered. Two concrete failure modes: with both
    `pacman` and `yay` as targets — which is the normal state after a `checkupdates` refresh, where
    official actionable updates exist — two terminals start at once and the second blocks or fails on
    the pacman database lock; and for Nix, `nix flake update` races `sudo nixos-rebuild switch --flake .`,
    so the rebuild can run against the lock it was supposed to replace. Neither was caught by the T7 or
    T8 verification because both checked argv equality, and argv equality cannot see execution order.
    T10 fixes it.
    Open product question for the user, not a blocker for T10: `yay -Syu` already upgrades the official
    repositories as well as the AUR, so chaining `sudo pacman -Syu && yay -Syu` is redundant. T10 keeps
    both, in order, because those are the commands S5 and S6 name; dropping the pacman step when AUR
    updates exist is the user's call.

L20. T10 verification by the parent. Harness grew from 19 to 24 cases, all passing (reproduced), and
    lint is clean on all three touched files (reproduced). The new pure functions were read line by
    line, and the extracted `terminalInvocation` removed the duplicated hold tail that T7's review had
    flagged. The sequencing was read as control flow: `runPlan` hands a terminal-free first step to a
    `Process`, `onExited` returns early on any non-zero exit, and only a clean exit reaches
    `runTerminalSteps`, so the rebuild cannot run against a lock that failed to update. The Arch plan
    has no terminal-free step, so it goes straight to one `terminalScript` invocation holding
    `chainCommands`: one window, the whole log in one place, and one pacman transaction at a time. The
    popout's load was reproduced through the real static route `import qs.modules.bar.popouts` with
    `BarPopouts.Updates {}`, the same route `Content.qml` uses, and it built `targets=yay plan=yay
    terminal=foot state=updates`, which is what this machine should produce because both official
    entries are ignored and only the AUR group contributes a target.
    Note: the local `qmllint` is a shim that exits 255 without diagnostics, so it is not a usable gate
    here and the static-route probe replaced it.

L21. Evidence recorded for the feature. Every figure below was produced on this machine, and the
    delegated pieces were reproduced by the parent rather than accepted from a report:
      detection, Arch path:  `state=updates official=2 aur=17 ignoredCount=2 actionableCount=17 nixStale=false`
      config read path:      `GlobalConfig.updates.checkInterval=1800 flakePath='' terminal=''`
      default bar entry:     a virgin config yields `...statusIcons:true,updates:true,power:true`, and a
                             `shell.json` that pins `bar.entries` yields the same list without `updates`
      indicator gate:        windowed probe `indicator=true` with `hasUpdates=true`
      popout:                `rows=21` (2 headers, 2 official, 17 AUR), `terminal=foot`, content loaded
      apply plan:            `targets=yay plan=yay terminal=foot`; the Arch chain is
                             `sudo pacman -Syu && yay -Syu` in ONE terminal; the Nix plan is
                             `nixFlakeUpdate` then `nixosRebuild`, the rebuild gated on exit 0
      harness:               24 cases, all passing
    Deliberately NOT claimed, and left to the user: the rendering of the bar entry and the popout with
    real eyes, and the Nix path end to end on their NixOS machine, where `nix` actually exists. The two
    manual steps from L11 and L14 also stay theirs: adding the `bar.entries` entry, and rebuilding or
    installing the plugin so the configuration section exists in the running session.

L22. Independent verification (T11) and its disposition. `gentle-ai-verify` read `git diff main..HEAD`
    and checked all five questions against the code rather than against this document: the shell
    construction surface (no output-derived value reaches a shell, `flakePath` is quoted at both
    sinks, and `terminal` is safe because `execDetached` runs QProcess without a shell), purely
    additive shared behaviour (all 18 files insert-only, no existing default, property or
    registration altered), the apply sequencing (rebuild gated on a clean exit, Arch in one terminal,
    displayed order equal to executed order, and `applyUpdates` with exactly one caller), the
    unknown-never-stale rule with every exit enumerated, and load safety, including the `Updates` name
    collision, which is safe under Qt's rule that a module import outranks a directory import. No high
    or medium finding.
    Disposition of the nine low and informational findings:
      - FIXED, real: the confirmation printed only `argv`, so the working directory that execution
        prepends was invisible. It now prints `Actions.shellCommand(step)`, the same pure helper the
        run uses, so what is displayed is what runs.
      - FIXED, real: there was no reentrancy guard. Reopening the popout while `nix flake update` was
        still running and confirming again could start a second sequence. An `applying` flag now
        guards `applyUpdates` and `runPlan`, and disables the button until the sequence is over.
      - FIXED, coverage: the single-quote branch of `shellQuote` was untested, as were the
        metacharacters it defends against. Case 25 feeds `'`, `;`, `$` and a backtick through
        `shellQuote` and through `terminalCommand`. This is coverage for existing behaviour rather than
        test-first: the function was already correct and the case passed on its first run.
      - REFUTED by measurement: the claim that gating on `exitCode` alone leaves a gap for a process
        killed by a signal. A probe running real processes showed that `Process.NormalExit` is
        `undefined` in QML, so the obvious "fix" would have made the gate permanently false and the
        rebuild unreachable, the very failure it was meant to prevent, while a `kill -TERM` child
        reports `exitCode = 15`, which the existing test already blocks. The code keeps
        `exitCode !== 0` and now records why.
      - RECORDED, not fixed: the Nix continuation lives on the popout, so unloading the popout during
        `nix flake update` skips the rebuild. It is not an out-of-order or double path, and only a
        shell reload mid-operation reaches it.
      - RECORDED and documented: the terminal wrapper hardcodes `-e`, so a configured terminal that
        does not accept it opens without running the command. The README now states that requirement.
      - The remaining informational items needed no change: the intended default shift for an unpinned
        `bar.entries`, property ordering that is not strictly alphabetical, and an imprecise phrase
        that was in the delegating brief rather than in the README.
    The three fixes are verified by the harness at 25 cases, by the linter, and by a probe that forces
    `confirming = true` so the new preview binding evaluates. They were not put through a second
    independent review; they add no shell construction and change no shared default.

L23. A defect found in production use, by the user, and not by any review in this document. Their session
    restarted, which dropped the `QML_IMPORT_PATH` they had been testing with, so the shell came back on
    the plugin installed on 23 September while `bar.entries` still had `updates` enabled. `GlobalConfig.updates`
    was therefore undefined, and the result was not a quiet degradation but a runaway poll loop: the
    binding `Math.max(1, GlobalConfig.updates.checkInterval) * 1000` threw, the timer kept its one second
    default, and the shell ran `pacman -Qu` plus `yay -Qua` once a second, hammering the AUR. Measured: a
    child process was present in five of six one second samples, and the log carried
    `@services/Updates.qml[253]: TypeError: Cannot read property 'checkInterval' of undefined`. The popout
    fared no better: `terminal` and `flakePath` threw 36 times between them, `plan` stayed undefined, and
    apply silently did nothing because `plan.length` threw as well, which is why the user's click applied
    nothing at all.
    Two lessons, both mine: a broken binding must never be able to turn a timer into a busy loop, and the
    missing-config-section state was never covered because every probe in this document, and both the
    delivered and the independent verification, ran against a freshly built plugin.
    Fix: `Actions.pollIntervalMs(seconds)` is pure, falls back to 1800 and floors at 60, asserted by case
    26 with RED observed first; the service reads the configured value inside a self-contained try/catch
    binding, with no helper to get the order wrong; the popout reads `terminal` and `flakePath` through
    guarded helpers; and `applyUpdates` and `runPlan` tolerate an absent plan. The configuration section
    is now optional customisation rather than a hard dependency, so the Arch feature works without the
    fresh plugin.
    Verified: harness 26 of 26 and lint clean; a probe run WITHOUT `QML2_IMPORT_PATH`, which reproduces the
    broken condition exactly, printed `terminal='foot' plan=yay targets=yay state=updates` and no
    TypeError; and in the live shell the error counts froze while ten one second samples showed no `yay`
    or `pacman` at all.
    Checked and dismissed: the `services/Time.qml` warnings that follow a reload are unrelated to this
    feature. The first one sits immediately after the `Configuration Loaded` at log line 63, long before
    any edit here, and 15 of them correspond to three reloads of five warnings each.

L24. Visual correction reported by the user after using the feature: hovering the bar entry drew a CIRCLE
    where a rounded rectangle belongs, and the count read a touch large. Cause: the entry had copied the
    icon-only hover pattern from `modules/bar/components/Power.qml`, a centred square
    (`implicitWidth: implicitHeight`) with `radius: Tokens.rounding.full`. That is right for a single icon
    but wrong for an entry that also carries a count: the square was about 18 px wide on a 40 px entry, so
    the highlight did not even cover the number next to the icon. Fixed by letting the StateLayer fill the
    entry and switching to `Tokens.rounding.small`, and by scaling the count to 0.9, which is the pattern
    `Clock.qml` uses for its secondary text. Measured with a probe rather than judged by eye:
    `item=39.6x24.0  hover=39.6x24.0  hoverRadius=8`, so the hover now spans the entry. Worth remembering
    about the token scale: radii clamp to half the height, so on a 24 px entry `rounding.medium` and up all
    render as a capsule, and `small` is the only token that still reads as a rounded rectangle.
