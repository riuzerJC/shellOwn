# Services panel: state detection and adapter hardening

## Objective

Restore reliable service state detection in the standalone services panel and harden its
adapters, then align the panel with the upstream i18n convention introduced by the
`upstream/main` sync (`Tr.tr`/`Tr.trCtx`).

## Context

- Panel: `modules/servicespanel/` (orchestrator + `systemd`/`docker` adapters + items).
- Mappings resolve in this order: `simulatedMappings` → `~/.config/caelestia/services-panel.json`
  → `GlobalConfig.services.panelMappings` → deprecated `GlobalConfig.launcher.services`.
- User config in play: `~/.config/caelestia/services-panel.json` (8 mappings: docker + 7 systemd,
  two of them `userUnit`).
- The documented ordering means the C++ defaults in `serviceconfig.hpp` are not exercised for
  this user, but they are the fallback for everyone else.

## Root cause (task 1)

`SystemdAdapter.qml` read `StdioCollector.value`, which does not exist in Quickshell 0.3.1
(exposed properties: `text`, `data`, `waitForEnd`). Every systemd-backed mapping therefore
resolved to `state: "unknown"`, the panel showed `Checking…` plus
`Unable to determine service status`, and post start/stop verification always failed.

Introduced by local commit `ddc2c98a` (2026-08-30), not by the `5a9c63ed` merge:
`modules/servicespanel/**` has zero diff in that merge. It surfaced only when the shell was
rebuilt and restarted on 2026-09-23.

## Tasks

- [x] 1. Fix `SystemdAdapter` probe output collection (`.value` → `.text`). Evidence: live panel
      screenshot after the fix shows Docker `Running`, PostgreSQL `Stopped`, and
      Bluetooth/Firewall/NetworkManager/ASUS `Running`, matching `systemctl is-active`.
      Commit: `5f6d3e59`.
- [x] 2. Wire `iconFont` end to end (mapping → `ServiceEntry` → `ServiceItem`), with
      `normalizeIconFont()` defaulting anything that is not `"nerd"` to `"material"`.
      Evidence: a temporary mapping with `iconFont: "nerd"` and glyph U+F1B2 rendered the
      Nerd Font glyph in the panel; the temporary mapping was removed afterwards.
      Commit: same work unit as 3 and 4.
- [x] 3. Add a distinct `failed` state instead of collapsing it into `stopped`
      (`SystemdAdapter` probe order, `ServiceOrchestrator.stateFromRaw`, stale-error clearing in
      `probeEntry`, `ServiceItem` label/colours/border).
      Evidence: `postgresql.service` (systemd state `failed`) now renders a red `Failed` badge
      with `Service has failed.`
      Commit: same work unit as 2 and 4.
- [x] 4. Reload `services-panel.json` when it changes: the panel's `FileView` had
      `watchChanges: true` without the `onFileChanged: reload()` call every other `FileView` in
      the repo uses, so mapping edits were ignored until a shell restart.
      Evidence: renaming a mapping in the JSON while the shell ran updated the open panel
      without any QML reload.
      Commit: same work unit as 2 and 3.
      Known side effect: saving a *changed* JSON while the panel is open rebuilds the entries and
      the panel closes (the Hyprland focus grab is cleared); reopening it shows the new mappings.
      An identical-content write keeps it open. Follow-up candidate, not a blocker.
- [x] 5. `DockerAdapter`: `probe()` now runs `buildProbeCommands()`/`runProbeFallback()` (previously
      dead code) and honours `params.probeMode` and `params.unit`; `params.socketUnit` controls the
      socket (default `docker.socket` for the default unit, none otherwise, `false` to disable).
      A failing `docker info` resolves to `stopped` and a `failed` unit to `failed`.
      Evidence: isolated `qs` harness printed the resolved commands and parse results for six
      mapping shapes (default, `cli-only`, custom unit, `noPkexec`, `socketUnit: false`, explicit
      socket) and a live probe returned `running`; the live panel still shows Docker `Running`.
      Commit: `c0dd5c00`.
- [x] 6. Migrate `qsTr` → `Tr.tr` across `modules/servicespanel/**` (5 files, 71 call sites) and add
      `import Caelestia.I18n` to each. Evidence: `scripts/trs-check.py --strict --file` reports no
      issues per file, `qmllint` is clean, and a fresh shell generation logs no
      `Tr is not defined` (the two historical hits were the intermediate sed-without-import state
      and do not recur).
      Note: 8 other local-fork modules still use `qsTr` (46 occurrences total):
      `modules/dashboard/Subscriptions.qml` (14), `modules/appcatalog/Content.qml` (11),
      `modules/polkit/PolkitDialog.qml` (8), `modules/workspaceoverlay/Content.qml` (6),
      `modules/workspaceoverlay/WorkspaceTarget.qml` (4), `modules/dashboard/Content.qml` (1),
      `modules/nexus/pages/panels/DashboardPanel.qml` (1),
      `modules/workspaceoverlay/WindowChip.qml` (1). Out of scope here. A repo-wide
      `scripts/trs-check.py` run is dominated by `.git/gentle-ai/candidate-views/**` snapshots and
      `build/` copies, so it needs exclusions before it is a usable signal.
      Commit: `af2144ad`.
- [x] 7. Add a command start watchdog to both adapters. Quickshell never emits `exited` when a
      binary cannot be found, so any probe candidate that may not exist (`docker info`, `service`)
      would leave an entry `probeInFlight` forever with a stuck `Checking…` row. A 1 s sweep now
      delivers one failure (`exitCode -1`, `Command did not start.`) after
      `commandStartTimeoutMs` (3000 ms) for processes that never emitted `started`; `finish()` is
      guarded so a command reports exactly once.
      Evidence: isolated harness — live docker/systemd probes still resolve, and
      `runCommand(["definitely-not-a-real-binary-xyz"])` reports failure after 3.0-4.0 s.
      Commit: `55d78cdd`.
- [x] 8. Update `docs/services-panel.example.json` (docker params, a systemd user unit and a
      `iconFont: "nerd"` example with glyph U+F11C) and the *Services panel* README section
      (field/param tables, watch behaviour, the four reported states).
      Evidence: the JSON parses, the glyph exists in `CaskaydiaCoveNerdFont-Regular.ttf`, and the
      README code block is byte-equivalent to the example after `json.loads`.
      Commit: `67e3bf03`.
      Note: the example documents `probeMode: systemctl-or-cli` (the QML default) while the built-in
      mapping in `serviceconfig.hpp` pins `cli-only`; the example was left on the more portable
      value and the C++ default was not touched to avoid forcing a plugin rebuild.
- [x] 9. End-to-end verification.
      `scripts/trs-check.py --strict --file` reports no issues for all 8 panel files, `qmllint`
      (`-I build/qml -I /usr/lib/qt6/qml`) is clean, and a fresh shell generation logs no
      `Tr is not defined` or other services-panel error.
      Adapter ground truth, all 8 mappings of the real user config:
      docker `running`, postgresql `failed`, bluetooth/firewalld/NetworkManager/asusd `running`
      (live panel, cross-checked against `systemctl is-active`), pipewire and ydotool `running`
      as `--user` units (adapter harness). A nonexistent unit resolves to `stopped`.
      Commits on `fix/servicespanel-detection`: `5f6d3e59`, `73e9435b`, `c0dd5c00`, `af2144ad`,
      `55d78cdd`, `67e3bf03`.

- [x] 10. Follow-up requested after review: migrate the remaining 46 `qsTr` sites in the 8
      neighbouring local-fork modules (`modules/dashboard/{Content,Subscriptions}.qml`,
      `modules/appcatalog/Content.qml`, `modules/polkit/PolkitDialog.qml`,
      `modules/workspaceoverlay/{Content,WorkspaceTarget,WindowChip}.qml`,
      `modules/nexus/pages/panels/DashboardPanel.qml`).
      Evidence: `trs-check.py --strict --file` clean per file, `qmllint` clean, and a forced shell
      reload adds no new `Tr is not defined` (log count unchanged at 10 historical hits).
      Commit: `ea4cb9cc`.

## Not done / out of scope

- The built-in docker mapping in `plugin/src/Caelestia/config/serviceconfig.hpp` still pins
  `probeMode: cli-only`; changing it requires a plugin rebuild.
- The dead-but-registered `modules/launcher/services/Services.qml` singleton (no consumer imports
  it) was left in place.

## Deviation from the original plan

Tasks 2, 3 and 4 share one work-unit commit: they all edit the same three functions/objects in
`ServiceOrchestrator.qml` plus `ServiceItem.qml`, and splitting interleaved hunks would have made
the commits less reviewable than the change itself.

## Non-goals

- No new services features, no redesign of the panel visuals.
- No changes to the merge itself or to upstream-owned files outside the panel's surface.
