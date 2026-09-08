# Proposal — add-dashboard-subscriptions-tab

## Why

The user maintains multiple AI subscriptions (codex, openai, opencode, gemini, copilot, deepseek) tracked by the
installed CodexBar CLI. Today there is no in-shell visibility of quota usage, and when provider credentials expire
(observed: codex 401, gemini API-key-rejected) the only remedy is leaving the shell to run CLIs by hand. The shell
already has a dashboard with tabs (Dashboard, Media, Performance, Weather); a Subscriptions tab is the natural home.

## What Changes

- Add `services/CodexBar.qml`: Quickshell singleton wrapping `codexbar usage --format json` (fetch, parse, refresh
  timer, manual reload), `codexbar config set-api-key --provider <id> --stdin` (key setting), and a provider →
  auth-CLI command mapping for credential renewal.
- Add dashboard tab **Subscriptions** (`modules/dashboard/Subscriptions.qml`): one card per enabled provider with
  primary/secondary usage bars, account identity, credits, and pace when present.
- Error and credential surfaces:
  - Auth-kind provider errors render a warning state with an inline **Renew** action that launches the provider's
    auth CLI in the user's terminal (`Quickshell.execDetached`).
  - An **Accounts** view inside the tab lists enabled providers with auth status, per-provider renew, and a
    set-API-key dialog (for API-capable providers) piping the key to `codexbar config set-api-key --stdin`.
- Register the tab in `modules/dashboard/Content.qml` behind a new `Config.dashboard.showSubscriptions` flag
  (`plugin/src/Caelestia/Config/dashboardconfig.hpp`), with a toggle in `modules/nexus/pages/panels/DashboardPanel.qml`.

## Capabilities

### New: dashboard-subscriptions

In-shell subscription usage view backed by CodexBar, including credential renewal and API key management.

## Impact

- Code: `services/` (new file), `modules/dashboard/` (new file + tab registration), `plugin/src/Caelestia/Config/`
  (new config property), `modules/nexus/pages/panels/DashboardPanel.qml` (toggle).
- No changes to CodexBar itself; the shell only consumes its CLI. No new external dependencies.

## Non-goals

- No provider enable/disable toggles in the shell (scope decision: show only providers enabled in codexbar config).
- No bar-module widget; dashboard tab only.
- No `codexbar cost` / spend views in v1.
- No background daemon (`codexbar serve`); one-shot CLI fetches only.
