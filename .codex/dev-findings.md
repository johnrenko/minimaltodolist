# Dev Findings Log

## Corrections
| Date | Source | What Happened | What To Do Next Time |
|------|--------|---------------|----------------------|
| 2026-03-04 | Self | `xcodebuild` failed because `xcode-select` pointed at `/Library/Developer/CommandLineTools`. | Run Xcode builds/tests with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` in this environment. |
| 2026-03-04 | Self | `-only-testing:MinimalTodoUITests/testLaunchShowsTodosHeader` matched zero macOS UI tests. | Use the full identifier format `Target/Class/testMethod` for targeted `xcodebuild` UI test runs. |
| 2026-03-05 | Self | A new `@MainActor` service failed to compile when a static helper was called from `Task.detached`. | Mark detached-callable static helpers as `nonisolated` (or move them out of actor-isolated types). |

## User Preferences
- Keep X bookmark setup sections collapsed by default unless the UI needs to force onboarding context open.

## Patterns That Work
- The X Bookmarks tab uses `DisclosureGroup` state plus fixed popover heights in `ContentView.swift`; changes to expanded/collapsed defaults should update both.
- For a lightweight Codex usage recap, query the newest local `~/.codex/state_*.sqlite` database and aggregate `threads.tokens_used` by `updated_at` window (5h, 7d).

## Patterns To Avoid
- Leaving setup copy fully expanded by default in the X Bookmarks tab makes the section dominate the small menu bar popover.

## Improvement Leads
- Consider making X Bookmarks popover height track actual content size instead of the current fixed collapsed/expanded constants.
- `MinimalTodoUITests.testLaunchPerformance` is flaky when an existing app instance is already running; it should quit the app explicitly or avoid measuring from a dirty state.
- Replace the current token-based Codex estimate / manual Claude entry with true quota percentages if official usage APIs become available.

## Domain Notes
- `MinimalTodo/ContentView.swift` owns the X Bookmarks setup UI and the popover height callback used by `MinimalTodoApp`.
- `ContentView.swift` now includes a `Usage` tab; Codex values are refreshed via `UsageRecapService` and Claude 5h/weekly values are stored in `@AppStorage`.
