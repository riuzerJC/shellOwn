# Apply Progress — add-dashboard-subscriptions-tab

## Status: applied (automated verification passed; live visual check pending)

## What was built

- `services/CodexBar.qml` (new, 149 lines): singleton wrapping `codexbar usage --format json` via `sh -c`
  (exit 127/2 → `available: false`), defensive normalization to `{id,name,state,errorText,primary,secondary,
  credits,accountEmail,plan,pace,authCommand}`, 5-minute refresh timer, `renew()` via
  `Quickshell.execDetached([...terminal, "fish", "-C", cmd])`, `setApiKey()` via
  `codexbar config set-api-key --provider <id> --stdin` with `stdinEnabled` close-for-EOF.
- `modules/dashboard/Subscriptions.qml` (new, 349 lines): Usage/Accounts segmented views, per-provider cards
  (bars, credits, pace, email), auth-error warning + inline Renew, non-auth error text, "CodexBar not found"
  empty state, inline API-key editor (StyledTextField password mode, confirm/clear, transient result line).
- `modules/dashboard/Content.qml`: tab registered (icon `subscriptions`, gated by `showSubscriptions`).
- `plugin/src/Caelestia/Config/dashboardconfig.hpp`: `CONFIG_PROPERTY(bool, showSubscriptions, true)`.
- `modules/nexus/pages/panels/DashboardPanel.qml`: Subscriptions toggle (moved `last: true` from Weather).
- `README.md`: config example updated.

## Evidence

- `ninja caelestia-core`: build OK (config plugin with new property compiles).
- `qmllint -I build/qml` on CodexBar/Subscriptions/Content/DashboardPanel: clean.
- `scripts/qml-lint-conventions.py`: no findings for touched files.
- `set-api-key` round-trip with throwaway `CODEXBAR_CONFIG`: key stored, `config validate` OK.
- Parser smoke (node mirror of normalize): real codexbar output → codex+gemini `authError`, others `error`;
  synthetic doc payload → all fields parsed.

## Deviations from design

- None material. D2 auth heuristic implemented as designed with `ponytail:` comment.

## Iteration 2 (user feedback)

- Fixed dashboard breakage: missing `subscriptionsComponent` declaration in Content.qml.
- Installed rebuilt config plugin .so into /usr/lib/qt6/qml/Caelestia (system install; runtime loads system path).
- Redesigned tab per caelestia-design-system skill: M3 card borders (m3outlineVariant), auth/error banners on
  tonal containers (tertiaryContainer/errorContainer), plan/state chips (rounding.full), window icons per usage
  bar, credits/pace footer, divider under header.
- Layout: usage view 2-column grid (pane = 2x perfHeroCardWidth); accounts rows full width.
- Keyboard fix: ContentWindow keyboardFocus now includes screenState.dashboard in the OnDemand set; key editor
  field force-activates focus on open.

## Iteration 3 (user feedback)

- Usage view now lists only authenticated (state=ok) providers; failing providers live exclusively in the
  Accounts view. Empty state added when nothing is authenticated.
- API-key editor gated to providers that accept config keys per the installed binary (openai, copilot only);
  deepseek/opencode/gemini/codex reject config keys (verified per-provider against codexbar 0.56.6).
- Service race fix: setApiKey writes key in Process onStarted, then closes stdin for EOF.
- User config side-fixes (outside shell code): deepseek `source: "api"` set in codexbar config (auto needs
  macOS web on Linux); opencode disabled in codexbar (unsupported source on Linux in this build).
- Copy/paste support in key editor: explicit Ctrl+V/X/C/A Keys handlers + right/middle-click paste.
