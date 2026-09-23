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
      Commit: pending.
- [ ] 2. Wire `iconFont` end to end (mapping → `ServiceEntry` → `ServiceItem`). Today
      `ServiceItem` reads `modelData.iconFont` but nothing ever sets it, so the Nerd Font
      branch added in `27fb63d6` is dead.
- [ ] 3. Add a distinct `failed` state instead of collapsing it into `stopped`
      (`SystemdAdapter`, `ServiceOrchestrator.stateFromRaw`, `ServiceItem` badge).
      Today a `failed` unit renders as `Stopped` (observed with `postgresql.service`).
- [ ] 4. `DockerAdapter`: make `probe()` honour `params.probeMode`/`params.unit` through the
      existing (currently dead) `buildProbeCommands`/`runProbeFallback` path, and make a failing
      `docker info` resolve to `stopped` so `probeMode: "cli-only"` cannot report `unknown`
      for a stopped daemon.
- [ ] 5. Migrate `qsTr` → `Tr.tr`/`Tr.trCtx` across `modules/servicespanel/**` and add
      `import Caelestia.I18n`; validate with `scripts/trs-check.py --file` and `qmllint`.
- [ ] 6. Update `docs/services-panel.example.json` for `iconFont`, the new params and the
      `failed` state.
- [ ] 7. End-to-end verification: `trs-check` + `qmllint` clean, live panel screenshot, and one
      work-unit commit per task.

## Non-goals

- No new services features, no redesign of the panel visuals.
- No changes to the merge itself or to upstream-owned files outside the panel's surface.
