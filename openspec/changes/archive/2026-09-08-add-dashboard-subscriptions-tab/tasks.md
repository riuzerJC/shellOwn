# Tasks — add-dashboard-subscriptions-tab

## 1. Service layer

- [x] T1 Create `services/CodexBar.qml`: singleton with `providers`/`fetching`/`available`/`lastUpdated` state,
      `reload()` running `codexbar usage --format json` via `Quickshell.Io.Process`, defensive JSON normalization
      per design D5, 5-minute refresh `Timer`, `CodexBarProcess` availability probe.
- [x] T2 Add `renew(providerId)` with the auth-command map (design D3) using
      `Quickshell.execDetached([...GlobalConfig.general.apps.terminal, "fish", "-C", cmd])`.
- [x] T3 Add `setApiKey(providerId, key, callback)` running `codexbar config set-api-key --provider <id> --stdin`
      (design D4): write key to stdin, no logging, clear-on-success callback contract.

## 2. Dashboard UI

- [x] T4 Create `modules/dashboard/Subscriptions.qml`: header (reload button, last updated), Usage/Accounts
      segmented switch, per-provider usage cards with primary/secondary bars, account email/plan, credits, pace,
      auth-error warning state with inline Renew, non-auth error text, "CodexBar not found" empty state.
- [x] T5 Add the Accounts view inside `Subscriptions.qml`: status rows per enabled provider with Renew and
      set-API-key dialog (`StyledTextField`, confirm clears field, success/failure toast via existing notif pattern).

## 3. Registration and config

- [x] T6 Register the tab in `modules/dashboard/Content.qml` (`dashboardTabs` entry: iconName `subscriptions`,
      enabled: `Config.dashboard.showSubscriptions`) and add `CONFIG_PROPERTY(bool, showSubscriptions, true)` to
      `plugin/src/Caelestia/Config/dashboardconfig.hpp`.
- [x] T7 Add the Nexus toggle in `modules/nexus/pages/panels/DashboardPanel.qml` following the `showPerformance`
      precedent, and document the new flag in `README.md` config section.

## 4. Verification

- [x] T8 Manual verification (remaining: visual check in a live shell session — user runs `caelestia` reload):
      automated parts already passed — `ninja caelestia-core` builds, `qmllint -I build/qml` clean on all touched
      QML, `qml-lint-conventions.py` clean, `codexbar config set-api-key --stdin` round-trip verified against a
      throwaway `CODEXBAR_CONFIG`, parser smoke-tested against real codexbar output (codex/gemini classified
      authError) and a synthetic success payload.

## Review Workload Forecast

- Files touched: 7 (2 new QML files, 5 small edits)
- Estimated changed lines: ~450 (service ~160, tab+accounts ~230, registration/config/toggle/docs ~60)
- 400-line budget risk: **High** → delivery decision required before apply (ask-on-risk).
- Chained PRs recommended: No (single cohesive feature; a split would leave the tab unbuildable without the service).
