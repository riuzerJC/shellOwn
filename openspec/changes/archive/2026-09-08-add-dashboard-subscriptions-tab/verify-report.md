# Verify Report — add-dashboard-subscriptions-tab

## Status: verified (automated); live UI check handed to user

## Spec coverage

| Requirement | Evidence |
| --- | --- |
| Tab lists enabled providers | Parser smoke against real codexbar output: 6 rows normalized; UI Repeater over `CodexBar.providers` |
| CodexBar binary missing | `sh -c` wrapper guarantees exit (127 → `available:false`); empty-state text in UI |
| Auth error + inline Renew | codex/gemini classified `authError`; card renders `lock_clock` + Renew; `renew()` map per design D3 |
| Non-auth error | openai/opencode/copilot/deepseek classified `error`, no renew button |
| Set API key via stdin | Round-trip verified: piping a key to `codexbar config set-api-key --provider openai --stdin` → stored + validate OK; shell never writes config directly |
| Renew launches auth CLI | `Quickshell.execDetached` with `GlobalConfig.general.apps.terminal` + `fish -C` (CalcItem precedent) |
| Refresh on activation/manual/timer | `Component.onCompleted: reload()`, refresh IconButton, 5-min Timer; stale data kept while fetching |
| Config gate + Nexus toggle | Property compiles into plugin; toggle follows showPerformance precedent; README updated |

## Limitations

- DeepSeek on Linux reports "web source only supported on macOS" — codexbar limitation, surfaced as generic error text (per spec: render error without renew).
- Interactive visual verification (tab renders, swipe, dialog flow) requires a live shell session; delegated to user as final acceptance.

## Iteration 2–3 verification

- Live log followed with timestamps after each hot reload: no Subscriptions/CodexBar errors (only pre-existing
  Polkit module noise from the base repo).
- deepseek end-to-end verified against real codexbar output after source=api fix ($1.64 balance).
- codex healthy in real usage output (OAuth recovered); usage view shows only ok providers per new spec scenario.
