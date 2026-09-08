# Spec Delta — dashboard-subscriptions (new capability)

## ADDED Requirements

### Requirement: Subscriptions tab lists enabled providers

The system SHALL provide a dashboard tab "Subscriptions" that shows one card per provider enabled in the CodexBar
config (`~/.config/codexbar/config.json`), rendered from `codexbar usage --format json` output.

#### Scenario: Healthy provider renders usage

- **WHEN** CodexBar returns a usage payload for an enabled provider
- **THEN** the card shows the provider name, primary window usage bar (usedPercent), secondary window usage bar when present, and account email / plan when present
- **AND** credits remaining and pace summary are shown when present

#### Scenario: Usage view shows only authenticated providers

- **WHEN** a provider returns an error of any kind
- **THEN** the Usage view omits that provider entirely
- **AND** when no provider is authenticated, the Usage view shows a hint pointing to the Accounts view

#### Scenario: CodexBar binary missing

- **WHEN** `codexbar` is not found on PATH
- **THEN** the tab shows a "CodexBar not found" empty state and no cards

### Requirement: Auth error states with inline renewal

The system SHALL distinguish provider errors of authentication kind from other errors and offer an inline
renewal action for auth errors.

#### Scenario: Expired OAuth token

- **WHEN** a provider returns an auth-kind error (e.g. codex 401 unauthorized)
- **THEN** the card renders a warning state with the short error reason
- **AND** a "Renew" action is shown that launches the provider's auth command in the user's configured terminal

#### Scenario: Non-auth error

- **WHEN** a provider returns a non-auth error (e.g. unsupported source on Linux)
- **THEN** the card renders the error message without a renew action

### Requirement: Accounts view

The tab SHALL include an accounts view listing enabled providers with auth status, per-provider renew action, and
a set-API-key action for API-capable providers.

#### Scenario: Set API key

- **WHEN** the user enters an API key for an API-capable provider in the accounts view
- **THEN** the shell pipes the key to `codexbar config set-api-key --provider <id> --stdin`
- **AND** the shell never writes CodexBar's config file directly
- **AND** the key is not logged, echoed to stdout, or retained after the operation

#### Scenario: Renew launches auth CLI

- **WHEN** the user triggers renew for a provider with a mapped auth command
- **THEN** the mapped command runs in a new terminal window (e.g. `codex login`, `opencode auth login`)
- **AND** providers without a mapping show a hint with the manual step instead

### Requirement: Data refresh

The subscriptions data SHALL refresh on tab activation, on manual reload, and on a periodic timer.

#### Scenario: Refresh cadence

- **WHEN** the tab becomes visible or the user presses reload
- **THEN** a `codexbar usage` fetch is started, showing a loading state and keeping stale data visible until new data arrives

### Requirement: Config gate

The tab SHALL be gated by a `dashboard.showSubscriptions` config property, defaulting to enabled, toggleable from
the Nexus dashboard panel.

#### Scenario: Toggle off

- **WHEN** `Config.dashboard.showSubscriptions` is false
- **THEN** the tab does not appear in the dashboard tab bar (same behavior as other dashboard tabs)
