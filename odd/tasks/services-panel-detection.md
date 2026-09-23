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
      Commit: pending.
- [ ] 6. Migrate `qsTr` → `Tr.tr`/`Tr.trCtx` across `modules/servicespanel/**` and add
      `import Caelestia.I18n`; validate with `scripts/trs-check.py --file` and `qmllint`.
- [ ] 7. Update `docs/services-panel.example.json` for `iconFont`, the new params and the
      `failed` state.
- [ ] 8. End-to-end verification: `trs-check` + `qmllint` clean, live panel screenshot, close
      the remaining work units.

## Deviation from the original plan

Tasks 2, 3 and 4 share one work-unit commit: they all edit the same three functions/objects in
`ServiceOrchestrator.qml` plus `ServiceItem.qml`, and splitting interleaved hunks would have made
the commits less reviewable than the change itself.

## Non-goals

- No new services features, no redesign of the panel visuals.
- No changes to the merge itself or to upstream-owned files outside the panel's surface.
