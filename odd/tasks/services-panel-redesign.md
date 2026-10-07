# Services panel: grid redesign

Turn the panel from a vertical list into a grid of up to six columns with vertical scroll, where
each card carries its own state-driven appearance, a lit status dot, and all of its actions and
metrics visible at once.

Work branch: `feat/servicespanel-redesign` (to be created before T1; the previous feature used
`fix/servicespanel-detection`). One open decision blocks T1: the card geometry that reconciles six
columns with "everything visible" (see T1).

## Specs

Verbatim from the request; wording and typos preserved.

S1. The panel stops being a list and becomes a grid of squarer boxes inside a larger container:
    "actualemtne es un listado pero quiero que sea el contenedor princpal mas grande, donde cada
    recuadro sea mas cuadrado"
S2. The buttons move below the content of each box:
    "debajo los botones de lanzamiento status etc"
S3. Status also drives the box colours, with a distinct design per state rather than one shared
    treatment:
    "los status tmb aplican a sus los colores del recuadro, pero con una variacion mas bonita
    como un diseno especiual cuando esta apagado, roto, prendido etc"
S4. A status dot per box, lit like a light:
    "ademas un puntito tambien si esta prendido apagado, podria ser neon como si fuera una luz"
S5. Up to five or six columns, scrolling vertically:
    "podrian ser hasta 5 o 6 columna con scroll vertical"
S6. Nothing is hidden behind hover; every card shows its full content at all times:
    "Todo visible"
S7. Extra actions, selected from the offered set: "Restart + autostart" — a restart button plus an
    autostart toggle with a badge that says whether the unit starts at boot.
S8. Extra metric, selected: "Uptime + reinicios" — how long the unit has been up, and how many times
    it restarted (`NRestarts`).
S9. Extra metric, selected: "Memoria / CPU por unidad" — real per-unit consumption.
S10. Extra action, selected: "Logs a demanda" — opens `journalctl -u <unit>` for that service in a
    terminal.

## Tasks

- [x] 1. Settle the card geometry and the metrics set. **Decided by the user: 5 columns, CPU as a
      percentage sampled only while the panel is open.** Frozen geometry: panel ~960 px on a
      1920x1080 display at scale 1; card 179 px wide, 155 px usable; the always-visible action row
      is 5 icon buttons at 24 px with 6 px gaps (144 px), leaving 11 px of slack, so everything S6
      asks for fits in one row. Six columns was rejected: 148 px cards leave 124 px usable against
      a 144 px action row.
      Evidence: `Tokens.padding.large = 16` and `Tokens.spacing.small = 8` from
      `plugin/src/Caelestia/Config/tokens.hpp`; `hyprctl monitors` reports eDP-2 1920x1080 scale 1;
      the current panel is 460 + 2*16 = 492 px wide.
      Note carried forward: the UI font is now CaskaydiaCove Nerd Font (monospace, ~6.6 px per
      character at `label.small`), so a 15-character name needs ~99 px and long names will elide
      before the 155 px usable width is the binding constraint.
- [x] 2. Extend the systemd probe from `systemctl is-active` to a single `systemctl show -p ...`
      call carrying `MemoryCurrent`, `CPUUsageNSec`, `NRestarts` and `ActiveEnterTimestamp`, while
      preserving the existing state mapping exactly (including the `inactive` vs `failed`
      distinction and the `SuccessExitStatus` caveat). Regression check: the eight real mappings
      must still resolve to docker `running`, postgresql `failed`, bluetooth/firewalld/
      NetworkManager/asusd `running`, pipewire/ydotool `running` as `--user` units.
      Evidence: the parent re-derived the mapping independently for all nine units, running the old
      substring logic and the new `ActiveState`/`SubState` logic against the real `systemctl
      is-active` and `systemctl show` output on this machine. 0 differences. `qmllint` 0 errors;
      `qml-lint-conventions.py --file` 2 violations before and after, the two pre-existing ones.
      Known behaviour change: a bus or permission failure now resolves to `unknown` where the old
      substring logic could report a false `failed` from stderr text. More correct, but recorded.
- [x] 3. Same for `DockerAdapter`, with metrics rewritten after review: they come from the
      mapping's own systemd unit (one `systemctl show` with the same property list as the sibling),
      not from `docker stats`. Per-container metrics are out of scope, see the contract section.
      Evidence: the first delivery was rejected because it gated metrics on a `params.container` key
      that exists nowhere and derived `cpuUsageNSec` from a `docker stats` percentage over an
      assumed interval; both are gone. In the corrected diff the only line touching the state path
      is wrapping the callback (`runProbeFallback(..., result => {`), so the derivation is untouched,
      and `qmllint` reports 0 errors with the linter unchanged at 2 pre-existing violations.
- [x] 4. Carry the new fields through `ServiceEntry` in `ServiceOrchestrator.qml` without changing
      the state machine. CPU is a percentage, computed from two consecutive samples of the
      cumulative counter.
      Evidence: `normalizeProbeResult` now forwards the five fields; `ServiceEntry` gained
      `memoryBytes`, `cpuUsageNSec`, `cpuPercent`, `restarts`, `activeSince`, `autostart` and
      `cpuSampledAt`; the percentage is computed inline in the probe callback from consecutive
      samples, guarded so a counter that moved backwards (a restarted unit) reports 0 rather than a
      negative number. No new timer was needed: the existing `periodicRefresh` already runs
      `refreshVisible()` every `max(3000, refreshIntervalMs)` while `panelVisible`. The adapter field
      `enabled` is mapped to the entry field `autostart` so it does not collide with the mapping's
      own `enabled`. `qmllint` 0 errors; `qml-lint-conventions.py --file` 46 violations before and
      after. The first attempt extracted a helper function and added a 47th section-order violation
      (every function in this file already sits after a `component` definition), so the logic was
      inlined instead of accepting the regression.
- [x] 5. Replace the list with the grid: `GridView` (precedent in
      `components/filedialog/FolderContents.qml`) plus a highlight, `StyledScrollBar` and 2D
      keyboard navigation, in `ServiceList.qml` or a new component. Fix the `Wrapper.qml` `630`
      fallback versus the `460` list width while here.
      Evidence: `ServiceList.qml` is now a 5-column `GridView` with a 187 px cell pitch
      (179 card + 8 gap), grid width 927 and viewport 935; `Content.implicitWidth` derives 959;
      `Wrapper.qml` computes the same 959 instead of falling back to 630. Verified by a live
      screenshot at 1920x1080: five columns x two rows for the nine enabled services, measured card
      runs of 177-179 px against a 187 px pitch, matching the computed geometry. `qmllint` 0 errors
      and `qml-lint-conventions.py` 0 violations on all three files, unchanged. Scrolling, the
      transition animations and other resolutions were not exercised, and the writer deliberately
      did not clip each cell so that the card overflow below stays visible.
      Follow-up applied by the parent: the writer's `Keys.onLeftPressed`/`onRightPressed` handlers
      swallowed Left/Right from the search field, which the panel focuses on open, breaking caret
      movement while typing. They now set `event.accepted = false` when the field holds text, so
      Left/Right only drive the grid while the field is empty.
- [x] 6. Redesign the card: state-driven background, border and content treatment per T1, the neon
      dot with a `MultiEffect` glow following the `Workspaces.qml:80-85` pattern, the action row
      (start/stop/restart/autostart/logs) and the metrics block. Keep the Nerd Font icon path.
      Add `pragma ComponentBehavior: Bound` to `ServiceOrchestrator.qml` and `DockerAdapter.qml`,
      which are the only two panel files missing it.
      Evidence: `ServiceItem.qml` rebuilt from a 64 px row to a 510-line vertical card. Verified by
      the parent against a live screenshot at 1920x1080: nine cards in five columns, and the three
      live states read apart at a glance — PostgreSQL (failed) renders a red `m3errorContainer` fill,
      a red border and a lit red dot; Bluetooth and the other running units render an elevated
      surface with a lit dot and a soft halo; Docker and Dropbox (stopped) render a dashed
      `m3outlineVariant` outline, a sunken fill and an unlit dot. Live metrics are real, not
      placeholders: `2h 34m`, `×0`, `36 MB`, `196 KB`, `0%`, and `—` for the null memory of
      PostgreSQL and the stopped units, which is exactly the `MemoryCurrent=[not set]` case. Names
      elide as intended (`ASUS Control Dae…`). `qmllint` 0 errors, `qml-lint-conventions.py` 0
      violations, `trs-check.py` clean, and the shell log has 0 warnings and 0 `ReferenceError`
      lines. The parent added the missing `pragma ComponentBehavior: Bound` to
      `ServiceOrchestrator.qml` and confirmed the reload stays clean.
      Two defects were found by live inspection rather than by linting and were fixed by the writer:
      `ShapePath` elements cannot resolve properties declared on their parent `Shape` (so the dashed
      outline silently never drew, `ReferenceError: corner is not defined`), and config tokens cannot
      be read inside a path element. Neither is catchable by `qmllint` here, which cannot resolve the
      `qs.*` imports.
      Deliberate deviations from the literal brief, all measured and reported: the state label shares
      the header row with the icon and dot, because a measured 11 pt line box is 18 px and not the
      13-15 assumed, so a separate line pushed the action row 24 px out of the card; the action gaps
      are `Tokens.spacing.small` (8 px, the token set has no 6 px step) giving 152 px against 155
      usable; and the row has five buttons, the four required plus a per-service re-probe, because
      the frozen T1 geometry counts five and dropping it would remove an existing capability.
      Unverified: `checking`/`unknown` cards were never rendered, no action was clicked, and hover,
      press ripples, font scale > 1 and scrolling were not exercised.
- [x] 7. Humanise the metrics: durations for uptime and byte sizes for memory. Decide where the
      helpers live; handle `MemoryCurrent=[not set]` for units whose cgroup is gone.
      Evidence: delivered inside `ServiceItem.qml` as functions rather than a separate file, and
      confirmed against live values: `formatDuration` renders `2h 34m` from `activeSince` and `—`
      for the empty string; `formatBytes` renders `196 KB`, `36 MB` and `—` for a null `memoryBytes`;
      `formatPercent` renders `0%` below 0.05 % and one decimal above. The null memory path is proven
      by the failed PostgreSQL card, whose cgroup is gone.
- [ ] 8. Verification. `qmllint` clean, `scripts/qml-lint-conventions.py` with no new violations
      against the `9e62c35d` baseline, a shell that boots with an empty error log, every tab card
      state rendered on purpose (running, stopped, failed, checking, busy), and the drawer blob
      geometry checked in `modules/drawers/ContentWindow.qml` since the panel's dimensions feed it.
      Route: verify.
- [ ] 9. Docs: the README *Services panel* section and `docs/services-panel.example.json` for any
      new mapping parameter, plus the state language from S3/S4 so the design is discoverable.
      Route: parent.

## Log

L1. Original request, verbatim:
    "actualemtne es un listado pero quiero que sea el contenedor princpal mas grande, donde cada
    recuadro sea mas cuadrado, debajo los botones de lanzamiento status etc, los status tmb aplican
    a sus los colores del recuadro, pero con una variacion mas bonita como un diseno especiual
    cuando esta apagado, roto, prendido etc, ademas un puntito tambien si esta prendido apagado,
    podria ser neon como si fuera una luz. y que mas podria agregarse a este redisenio"
L2. Scope narrowed to the services panel, design not functionality: "cambiar el disenio, te dire
    como seria".
L3. Grid density chosen: "podrian ser hasta 5 o 6 columna con scroll vertical".
L4. Extras selected, all four offered: "Restart + autostart", "Uptime + reinicios",
    "Memoria / CPU por unidad", "Logs a demanda".
L5. Card reveal behaviour: "Todo visible".
L6. Evidence that the S8-S9 data exists, sampled live on 2026-10-07:
    `bluetooth.service` MemoryCurrent 2600960, CPUUsageNSec 63153000, NRestarts 0;
    `firewalld.service` 46944256 / 1655344000; `pipewire.service` (user) 11689984 / 18277338000;
    `ydotool.service` (user) 200704 / 12905000; `postgresql.service` (failed) MemoryCurrent
    `[not set]`, CPUUsageNSec 79670000. `MemoryAccounting=yes`. `ActiveEnterTimestamp` is populated
    for active units and empty otherwise. `CPUUsageNSec` is cumulative CPU time, not a percentage.
L7. T1 resolved by the user: "5 columnas (recomendado)" and "Porcentaje, solo con panel abierto".
    Geometry frozen at 5 columns / 179 px cards / 24 px action buttons; CPU is a percentage
    computed from two `CPUUsageNSec` samples taken only while the panel is visible.
L8. State language (S3) confirmed by the user as proposed: "Como lo propuse". Stopped is sunken
    (`m3surfaceContainerLowest`, dashed `m3outlineVariant` border, attenuated content and icon),
    running is elevated with `m3primary`, and failed is the only state that shouts, in `m3error`.
L9. Status dot (S4) confirmed by the user: "Solo running y failed". The dot is lit with a glow only
    for `running` (`m3primary`) and `failed` (`m3error`); `stopped` and `checking` stay unlit.
L10. T2 and T3 delegated to two background writers on disjoint files, with the data contract below
    frozen first so neither depends on the other.
L11. T2 reviewed and accepted: the state mapping was re-derived independently for all nine units
    (postgresql failed, bluetooth/firewalld/NetworkManager/asusd/pipewire/ydotool running,
    dropbox and a nonexistent unit stopped) by running both the old substring logic and the new
    `ActiveState`/`SubState` logic against the real `systemctl is-active` and `systemctl show`
    output. 0 differences. The only behaviour change is that a bus/permission failure now resolves
    to `unknown` where the old substring logic could report a false `failed` from stderr text, which
    is the more correct outcome.
L12. T3 rejected on review, one defect of which was mine. I told the writer the container name lives
    in `params`, which I never verified: no mapping in the repo or in the user's config has
    `params.container` (the docker mapping is `{"id":"docker","name":"Docker Daemon"}` with no
    `params` at all), so `resolveContainer()` returns empty and the metrics gate returns early — the
    docker card would have shown no metrics at all. Its second defect is `statsCpuNSec()`, which
    derives a value from a `docker stats` percentage over an assumed 1000 ms interval; the contract
    requires a cumulative counter, and the orchestrator would have differenced a delta. Both are
    corrected by reading metrics from the mapping's systemd unit instead, and the per-container path
    is dropped rather than shipping a number that cannot be computed honestly.
L13. T5 reviewed and accepted, with one fix applied by the parent. The grid matches the frozen
    geometry, confirmed against a live screenshot at 1920x1080: five columns by two rows for the
    nine enabled services, card runs of 177-179 px against a 187 px pitch, panel width 959 px. The
    writer's answer to the card question was a clear NO with the reason: `ServiceItem.qml` is a
    full-width 64 px list row, so inside a 179 px cell its `fillWidth` title column collapses and the
    service name disappears, which the screenshot confirms. It deliberately did not clip the cells
    so the overflow stays visible rather than hidden. Parent fix: its `Keys.onLeftPressed` and
    `onRightPressed` swallowed those keys from the search field, which the panel focuses on open,
    breaking caret movement while typing; they now set `event.accepted = false` when the field holds
    text, so Left/Right only drive the grid while the field is empty.
L14. Grid height confirmed by the user: "probemos 4". `maxVisibleRows = 4`, so the panel is
    `4*179 + 3*8 = 740` px tall before the grid starts scrolling, which fits the 1080 px display.
L15. T6 planned. Planning surfaced that restart, autostart and logs have no implementation: only
    `start` and `stop` exist on the adapters and the orchestrator. They are frozen as an action
    contract (see the section above) before delegating, so the card UI and the action plumbing can be
    written in parallel against the same names.
L16. T6 action plumbing delivered and reviewed. `SystemdAdapter` gained `canRestart`/`canAutostart`,
    `restart()` and `setAutostart()` reusing `runAction`, and `logsCommand()`; `DockerAdapter` gained
    `canRestart`/`canAutostart` (false), its own restart path and a `setAutostart()` that resolves
    `ok: false` with "Autostart is not supported for Docker mappings."; the orchestrator gained the
    three `*ById` functions and merges adapter-derived capability defaults in `reload()`. Linter
    counts: adapters 2 -> 2, orchestrator 46 -> 49. The +3 is exactly the three new orchestrator
    functions, and it is unavoidable without moving every `component` definition to the end of that
    file; reported rather than hidden, and left as a documented follow-up because the user scoped
    this work to design, not to convention cleanup. `qmllint` 0 errors on all three.
L17. The writer pushed back correctly on one instruction. My brief required every new action to go
    through the adapters' `runCommand` so it would inherit the watchdogs and the 10 s timeout. It
    implemented `restart` and `setAutostart` that way but deliberately did NOT do so for logs, with a
    sound argument: `journalctl -f` is a long-lived interactive process and `commandRunTimeoutMs`
    would kill the terminal after ten seconds. `openLogsById` uses `Quickshell.execDetached`, creates
    no `Process` and never sets `entry.busy`, so it cannot reintroduce the infinite spinner. Accepted.
L18. The writer also corrected my brief on the terminal configuration: I claimed the orchestrator had
    a `paths` section to resolve a terminal from. It verified instead and found that the `paths`
    config node is `UserPaths` with no terminal entry, and that `general.apps.terminal`
    (`plugin/src/Caelestia/Config/generalconfig.hpp:20`, default `["foot"]`) is the only terminal key
    in the shipped config. Parent verified that `journalctl -u docker` resolves without the
    `.service` suffix, so the docker logs command is valid.
L19. Parent applied the `pragma ComponentBehavior: Bound` line to `ServiceOrchestrator.qml`, which the
    task called for and the writer left out as outside its change set. Runtime confirmation is
    deferred until the card writer stops restarting the shell, to avoid racing it.
L20. T6 and T7 delivered and reviewed against a live screenshot. The card reads correctly in all three
    live states and the metrics are real. The writer corrected a number of mine for the second time in
    this task: my brief said roughly 6.6 px per character for the monospace UI font, derived sloppily
    as 0.6 x the 11 pt size number instead of 0.6 x the pixel size; the measured advance is about
    8.7 px, which fits about 17.8 characters in the 155 px usable width and elides a 19-character name.
    Neither `qmllint` nor the conventions linter could have caught the two real defects it fixed, both
    of which needed a live shell: a `ShapePath` cannot resolve a property declared on its parent
    `Shape`, so the dashed outline never drew, and config tokens cannot be read inside a path element.
    The lesson carried from the rest of this task is that the live signal beats the static one here.
L21. Icons switched to Nerd Font at the user's request, all nine verified present in
    `CaskaydiaCoveNerdFont-Regular.ttf` with `fc-query` before being applied: `fa-docker` U+F21F,
    `dev-postgresql` U+E76E, `fa-bluetooth` U+F293, `fa-fire` U+F06D, `fa-wifi` U+F1EB,
    `fa-laptop` U+F109, `fa-volume_up` U+F028, `fa-keyboard` U+F11C, `fa-dropbox` U+F16B.
    A hard limit was found the hard way: **a codepoint above U+FFFF breaks the whole mappings file.**
    `qml[services.panel] Failed to parse services-panel.json: SyntaxError: JSON.parse: Parse error`,
    the FileView falls back and the panel stops rendering. Confirmed by A/B: with `md-wall_fire`
    (U+F1A11) the panel does not open, with the eight BMP glyphs plus `fa-fire` it does. It fails both
    as an escaped surrogate pair and as a literal UTF-8 character, so the codepoint is the problem, not
    the escape. `node` and Python both parse the file happily, which is why a third-party parser is not
    a verification: the consumer is. Practical consequence: the whole `md-*` set
    (U+F0001-U+F1AF0) is unusable here, and there is no wall glyph in the BMP, so firewalld keeps
    `fa-fire`. The Devicons family is BMP, so `dev-microsoftsqlserver` U+E82E, `dev-mysql` U+E704,
    `dev-mariadb` U+E828, `dev-redis` U+E76D and `dev-mongodb` U+E7A4 are all available for later.
L22. The user reported the icons were too large and clipped by their container. Cause: the Nerd path
    used `Tokens.font.icon.large` (24 pt) inside a 22 px icon slot, while the Material path used
    `icon.medium` (18 pt); Nerd glyphs fill their em more than Material Symbols do, so 24 pt overflowed.
    Fixed by aligning both paths on `icon.medium`, which also means switching `iconFont` no longer
    changes the size. Verified at 4x zoom on a live screenshot: both glyphs sit inside the container
    uncut with a clear gap before the state label. `qmllint` 0 errors, linter 0 violations.
    `icon.small` (15 pt) is the next step down if 18 pt is still too big.
    Follow-up: the user reported it still clipped some glyphs at `icon.medium`, so the same one line was
    taken one step further to `icon.small` (15 pt). All nine glyphs were then checked individually at
    4x zoom on a live screenshot (docker whale, dev-postgresql elephant, bluetooth rune, fa-fire flame,
    fa-wifi, fa-laptop, fa-volume_up, fa-keyboard, fa-dropbox) and every one sits inside its container
    uncut with margin. `qmllint` 0 errors, linter 0 violations. No other change was made.
    Final size, after a further request for "un poquito mas pequeno": 13 pt, written as
    `Math.round(Tokens.font.icon.small.pointSize * 0.85)` because `icon.small` is the smallest icon
    token. Deriving from the token instead of writing a literal keeps `appearance.font.scale`
    working. All nine glyphs were re-checked in a 3x3 grid of their containers at 5x zoom and every
    one still fits. Residual: at 13 pt the detailed logos (the Docker whale, the PostgreSQL elephant)
    are small; `icon.small` at 15 pt is the step back up if any reads badly at real size.

## Data contract for T2-T4

Every adapter probe returns the existing `state` plus these fields, so the two adapters can be
implemented without touching each other:

| Field | Type | Source | Notes |
| --- | --- | --- | --- |
| `memoryBytes` | number or `null` | `MemoryCurrent` | `null` when the cgroup is gone (`[not set]`) |
| `cpuUsageNSec` | number | `CPUUsageNSec` | MUST be genuinely cumulative. A source that can only offer a percentage is not acceptable for this field |
| `restarts` | int | `NRestarts` | 0 when absent |
| `activeSince` | string | `ActiveEnterTimestamp` | empty string when inactive |
| `enabled` | bool or `null` | `UnitFileState` | `null` when the unit-file state is not enabled/enabled-runtime/static/alias/disabled |

Every mapping in this panel resolves to a systemd unit, including the docker one, whose target is the
daemon (`docker.service`). Metrics are therefore read from `systemctl show` for both adapters.
Per-container metrics are out of scope: `docker stats` exposes only a percentage and no cumulative
counter, so an honest container CPU figure needs a cgroup `cpu.stat` read.

The percentage is the orchestrator's job, not the adapter's: `ServiceOrchestrator` samples
`cpuUsageNSec` on a timer gated by the existing `setPanelVisible`, so the adapters stay stateless.
The `state` values and their derivation are unchanged by this work.

## Action contract for T6

S7 and S10 need three actions that do not exist yet; only `start` and `stop` are implemented today.
Frozen so the card UI and the action plumbing can be built in parallel against the same names.

Adapter side, alongside the existing `probe`/`start`/`stop`:

| Function | Behaviour |
| --- | --- |
| `restart(serviceConfig, callback)` | Restart the unit. systemd: `pkexec systemctl restart <unit>`, or `systemctl --user restart` for a user unit. Docker: its own restart path. |
| `setAutostart(serviceConfig, enabled, callback)` | systemd: `pkexec systemctl enable\|disable <unit>`. Docker: unsupported, resolves with `ok: false` and a clear message. |
| `logsCommand(serviceConfig)` | Returns the argv array to run in a terminal, e.g. `["journalctl", "-u", unit, "-n", "200", "-f"]`, with `--user` when applicable. |

Orchestrator side:

| Function | Behaviour |
| --- | --- |
| `restartServiceById(id)` | Same verification machinery as start/stop. |
| `setAutostartById(id, enabled)` | Same, and a re-probe so the badge updates. |
| `openLogsById(id)` | Runs `logsCommand()` in a terminal. |

Every one of these must go through the adapters' existing `runCommand`, so they inherit the start
watchdog and the 10 s run timeout. A new action that spawns its own process outside that machinery
would reintroduce exactly the infinite spinner that `commandRunTimeoutMs` exists to prevent.
`capabilities` gains `restart` (default true) and `autostart` (default true for systemd, false for
docker); the card must hide an action the mapping cannot perform.
