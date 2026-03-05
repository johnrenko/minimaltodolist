# Dev Findings Log

## Corrections
| Date | Source | What Happened | What To Do Next Time |
|------|--------|---------------|----------------------|
| 2026-03-04 | Self | `xcodebuild` failed because `xcode-select` pointed at `/Library/Developer/CommandLineTools`. | Run Xcode builds/tests with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` in this environment. |
| 2026-03-04 | Self | `-only-testing:MinimalTodoUITests/testLaunchShowsTodosHeader` matched zero macOS UI tests. | Use the full identifier format `Target/Class/testMethod` for targeted `xcodebuild` UI test runs. |
| 2026-03-05 | Self | A new `@MainActor` service failed to compile when a static helper was called from `Task.detached`. | Mark detached-callable static helpers as `nonisolated` (or move them out of actor-isolated types). |
| 2026-03-05 | Self | Codex DB lookup using only `~/.codex` was unreliable in app context and returned false "not found". | Resolve Codex home using multiple candidates (`CODEX_HOME`, `NSHomeDirectoryForUser`, current-user home, explicit `/Users/<name>`) before querying `state_*.sqlite`. |
| 2026-03-05 | Self | Assumed Codex usage percentages had to be derived from `state_*.sqlite` token totals. | Read the newest `rollout-*.jsonl` session logs instead; `payload.rate_limits.primary/secondary.used_percent` already contain the real 5h and weekly percentages. |
| 2026-03-05 | Self | Showing a restore window during `applicationDidFinishLaunching` was unreliable for this `LSUIElement` app when the status item was already hidden. | For startup recovery, defer to the next main-actor turn and auto-restore the `NSStatusItem` first; use a window only as fallback. |
| 2026-03-05 | Self | Menu bar debugging was confused by two different `MinimalTodo.app` bundles running at once (Downloads copy plus Xcode build). | Before debugging launch/status-item behavior, quit every running copy and test from exactly one app bundle. |
| 2026-03-05 | Self | Xcode kept an old `MinimalTodo` instance alive through `debugserver`, so `pkill` alone did not produce a clean single-instance launch. | When menu bar behavior looks inconsistent, also terminate the debugger-owned process and verify only one `MinimalTodo` PID remains before reproducing. |
| 2026-03-05 | Self | The restore window crashed because its collection behavior combined `NSWindowCollectionBehaviorCanJoinAllSpaces` with `NSWindowCollectionBehaviorMoveToActiveSpace`. | For floating recovery windows, pick one space behavior; `canJoinAllSpaces` is valid here, `moveToActiveSpace` must be removed. |
| 2026-03-05 | Self | The menu bar icon restore action was a no-op because the status item was never configured with `NSStatusItemBehaviorRemovalAllowed`. | For cmd-drag-removable menu bar items, set `.behavior = .removalAllowed` and make restore capable of reinstalling the status item if `isVisible = true` does not bring it back. |
| 2026-03-05 | Self | Reusing the same `NSStatusItem.autosaveName` after cmd-drag removal caused the restore modal to close and immediately reopen in a loop. | When restore must clear a removed item's persisted hidden state, rotate to a fresh autosave-name generation and keep the observer suppression active until restore callbacks have drained. |
| 2026-03-05 | User | The app cannot legitimately re-add a removed menu bar item itself; the correct recovery path is macOS Menu Bar settings. | Treat cmd-drag removal as a System Settings restore flow: use a stable `autosaveName`, stop programmatic reinsert attempts, and guide the user to System Settings -> Menu Bar -> "Allow in the Menu Bar". |
| 2026-03-05 | Self | A pending restore-window task could survive after the status item became visible, so the help modal opened even though the icon was already in the menu bar. | When reacting to `NSStatusItem.isVisible`, avoid `.initial` for this flow, cancel pending help-window tasks once visibility turns `true`, and re-check visibility immediately before showing the modal. |
| 2026-03-05 | Self | The Claude web-page import path was brittle and blocked by embedded login failures. | For this app, use Claude Code's local OAuth credentials from Keychain plus `GET https://api.anthropic.com/api/oauth/usage`; do not depend on `WKWebView`, browser automation, or manual inputs. |
| 2026-03-05 | Self | Assumed the Claude OAuth usage endpoint behaved like a normal bearer endpoint without feature gating. | Include `anthropic-beta: oauth-2025-04-20` on `https://api.anthropic.com/api/oauth/usage` requests or the call will not return the expected consumer usage payload. |
| 2026-03-05 | Self | Assumed Claude Code credential `expiresAt` would be ISO8601. | Parse `Claude Code-credentials` `claudeAiOauth.expiresAt` as a millisecond epoch first, then fall back to numeric-string or ISO8601 parsing. |

## User Preferences
- Keep X bookmark setup sections collapsed by default unless the UI needs to force onboarding context open.

## Patterns That Work
- The X Bookmarks tab uses `DisclosureGroup` state plus fixed popover heights in `ContentView.swift`; changes to expanded/collapsed defaults should update both.
- For Codex usage recap, read recent local `~/.codex/sessions` or `~/.codex/archived_sessions` `rollout-*.jsonl` files and extract `token_count.rate_limits.primary/secondary.used_percent`.
- For Claude usage, read the `Claude Code-credentials` Keychain item through Security.framework, decode `claudeAiOauth.accessToken`, and call `https://api.anthropic.com/api/oauth/usage` with `anthropic-beta: oauth-2025-04-20`; the response provides `five_hour` and `seven_day` utilization directly.
- Keep Claude usage cached in `@AppStorage` and render `claudeUsageService.snapshot ?? cachedClaudeUsageSnapshot` so the UI preserves the last known values when a refresh fails.
- `NSStatusItem` visibility can be recovered by observing `isVisible` and setting it back to `true`; use an explicit `autosaveName` so hidden-state persistence is stable across launches.
- For this app, a single clean launch reports `NSStatusItem.isVisible == true`; if recovery UI feels invisible, temporarily switch the app to `.regular`, use a floating restore window, and expose a direct restore action inside `ContentView`.

## Patterns To Avoid
- Leaving setup copy fully expanded by default in the X Bookmarks tab makes the section dominate the small menu bar popover.
- Do not scrape `claude.ai/settings/usage` from `WKWebView` or AppleScript-controlled browsers for this feature; the Claude Code OAuth endpoint is simpler and more reliable on this Mac.

## Improvement Leads
- Consider making X Bookmarks popover height track actual content size instead of the current fixed collapsed/expanded constants.
- `MinimalTodoUITests.testLaunchPerformance` is flaky when an existing app instance is already running; it should quit the app explicitly or avoid measuring from a dirty state.
- Replace the current local-log Codex parsing with a true provider API if Codex exposes one; Claude already has a workable local OAuth-backed usage path.

## Domain Notes
- `MinimalTodo/ContentView.swift` owns the X Bookmarks setup UI and the popover height callback used by `MinimalTodoApp`.
- `ContentView.swift` now includes a `Usage` tab; Codex values are refreshed via `UsageRecapService` from local rollout logs and Claude values are refreshed via `ClaudeUsageService` from Claude Code OAuth credentials, then cached in `@AppStorage`.
