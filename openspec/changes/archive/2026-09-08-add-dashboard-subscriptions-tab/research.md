# Research — add-dashboard-subscriptions-tab

## Pre-proposal decisions (confirmed by user, 2026 session)

- Provider scope: only providers `enabled: true` in `~/.config/codexbar/config.json`.
- Credential management: BOTH inline renew button (per provider, on auth errors) AND a separate accounts/status view.
- Auth flows v1: OAuth via provider CLIs launched in a floating terminal + manual API key editing in the UI.

## CodexBar CLI findings

- Binary: `/usr/bin/codexbar` v0.56.6. Single subcommand: `usage`.
- `codexbar usage --format json [--pretty]` → stdout JSON array:
  `[ { "provider": "<id>", "source": "auto|web|cli|oauth|api", "error": {...} | usage-payload } ]`
- No `login` subcommand; credential renewal is delegated to provider CLIs:
  - codex → `codex login` (401 observed when token expired)
  - gemini → OAuth via Google account (API key rejected by codexbar)
  - opencode → `opencode auth login`
  - copilot → device flow (gh / VS Code)
  - openai / deepseek → API key based (key storage location TBD in design)
- Config file `~/.config/codexbar/config.json` contains provider enable flags only (id/enabled/region); token accounts loaded from "resolved CodexBar config file".

## Codebase findings

- Dashboard tabs: `modules/dashboard/Content.qml` (`dashboardTabs` array, each entry {component, iconName, text, enabled: Config.dashboard.showX}).
- Tab bar: `modules/dashboard/Tabs.qml` (generic, consumes `tabs` model; wheel/hover/click handled).
- Tab UI pattern: `modules/dashboard/Performance.qml` + `modules/dashboard/performance/` cards.
- Service pattern: `services/Weather.qml` (pragma Singleton, Quickshell.Io Process, exposes props + reload()).
- Config plugin: `plugin/src/Caelestia/Config/dashboardconfig.hpp` uses `CONFIG_PROPERTY(bool, showPerformance, true)`.
- Toggle UI: `modules/nexus/pages/panels/DashboardPanel.qml` (uses GlobalConfig for writes).
- services/ has no CodexBar service yet.

## Open items for design

1. Where codexbar reads API keys from on Linux (env vars vs config file) — decides feasibility/safety of in-UI key editing.
2. How caelestia spawns a floating terminal (existing utility or `Hypr` service / Process spawn of user's $TERMINAL).
