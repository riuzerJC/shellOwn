# Design — add-dashboard-subscriptions-tab

## Decisions and tradeoffs

### D1: One-shot CLI fetch, not `codexbar serve`

`codexbar serve` offers cached HTTP JSON, but a persistent server + bearer-token management is state the shell does
not need. `codexbar usage --format json` is stateless, matches the existing `services/Weather.qml` Process pattern,
and dies with the shell. Cost: each refresh spawns a process (~1s). Acceptable at a 5-minute cadence.

### D2: Auth error detection by message inspection, not a new codexbar flag

CodexBar's error objects carry `kind` (`provider`, `runtime`, ...) but auth failures are not a dedicated kind
(observed: codex 401 → `kind: "provider"`). Detection: error message matches auth signals (`401`, `unauthorized`,
`sign in`, `auth`, `token`). This is a heuristic; a wrong guess only changes whether the Renew button shows.
Marked with a `ponytail:` comment noting the upgrade path (CodexBar may add an error kind later).

### D3: Renew via `Quickshell.execDetached` + user's terminal from config

Reuse the existing pattern from `modules/launcher/items/CalcItem.qml`:
`Quickshell.execDetached([...GlobalConfig.general.apps.terminal, "fish", "-C", "<auth-cmd>"])`.
The auth command map lives in the service:

| Provider | Command |
| --- | --- |
| codex | `codex login` |
| opencode | `opencode auth login` |
| gemini | `gemini` (first-run OAuth) |
| copilot | `gh auth login` |
| openai / deepseek | none (API key path) |

Unmapped providers render a hint instead of a button. Tradeoff: the `fish -C` wrapper assumes fish exists (it is the
caelestia launcher convention); acceptable for this fork.

### D4: API keys via `codexbar config set-api-key --stdin`

The installed binary supports `codexbar config set-api-key --provider <id> --stdin`. The service runs it with
`Quickshell.Io.Process`, writes the key to stdin, closes stdin. The shell never touches
`~/.config/codexbar/config.json` directly (schema/perm risk), never echoes the key, and clears the TextField after
success. File perms (0600) are CodexBar's responsibility.

### D5: Data model — one service, plain JS objects

`services/CodexBar.qml` (Singleton) exposes:

- `providers: list<var>` — normalized rows: `{id, name, state: "ok"|"authError"|"error"|"loading", errorText,
  primary: {usedPercent, resetsAt} | null, secondary | null, credits, accountEmail, plan, authCommand}`
- `fetching: bool`, `available: bool` (binary present), `lastUpdated: date`
- `reload()`, `renew(providerId)`, `setApiKey(providerId, key, callback)`
- Internal `Timer` (5 min) + `Process` per operation (usage fetch, key set).

Parsing is defensive: unknown fields are ignored; `usage.primary/secondary {usedPercent, resetsAt}`,
`identity.accountEmail`, `credits.remaining`, `pace` read when present (payload documented in CodexBar `docs/cli.md`).

### D6: UI composition mirrors Performance tab

`modules/dashboard/Subscriptions.qml` renders a header (reload button, last-updated), a segmented switch
(Usage / Accounts) and a column of cards reusing `StyledRect`, `MaterialIcon`, `StyledText`, `Tokens`, `Colours`,
`Anim` from `qs.components`. Usage bars reuse the simple two-color bar pattern from `modules/dashboard/Performance.qml`
rather than introducing a new reusable component for a single consumer. Auth-error cards add a `StateLayer`-styled
Renew button. Accounts view rows show status icon, provider name, renew, and a key icon opening the API-key dialog
(a small popup with `StyledTextField` + confirm; no new dialog framework).

### D7: Config property lives in the C++ plugin

`plugin/src/Caelestia/Config/dashboardconfig.hpp`: `CONFIG_PROPERTY(bool, showSubscriptions, true)` next to
`showPerformance`. The Nexus toggle follows the exact `showPerformance` precedent in `DashboardPanel.qml`
(`Config.dashboard.showSubscriptions` read / `GlobalConfig.dashboard.showSubscriptions` write).

## Risks

- **Payload variance across providers**: not every provider fills every field; UI must tolerate nulls (covered in D5).
- **Auth heuristics false positive**: worst case an extra Renew button on a non-auth error (harmless, command may fail in terminal).
- **`codexbar config set-api-key` blocking**: it is a fast local file write; no timeout handling beyond Quickshell defaults.
- **Review budget**: ~450 estimated changed lines across 7 files — above the 400-line threshold; delivery decision required before apply (ask-on-risk).
