# Dev Findings Log

## Corrections
| Date | Source | What Happened | What To Do Next Time |
|------|--------|---------------|----------------------|
| 2026-03-04 | Self | `xcodebuild` failed because `xcode-select` pointed at `/Library/Developer/CommandLineTools`. | Run Xcode builds/tests with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` in this environment. |
| 2026-03-04 | Self | `-only-testing:MinimalTodoUITests/testLaunchShowsTodosHeader` matched zero macOS UI tests. | Use the full identifier format `Target/Class/testMethod` for targeted `xcodebuild` UI test runs. |

## User Preferences
- Keep X bookmark setup sections collapsed by default unless the UI needs to force onboarding context open.

## Patterns That Work
- The X Bookmarks tab uses `DisclosureGroup` state plus fixed popover heights in `ContentView.swift`; changes to expanded/collapsed defaults should update both.

## Patterns To Avoid
- Leaving setup copy fully expanded by default in the X Bookmarks tab makes the section dominate the small menu bar popover.

## Improvement Leads
- Consider making X Bookmarks popover height track actual content size instead of the current fixed collapsed/expanded constants.
- `MinimalTodoUITests.testLaunchPerformance` is flaky when an existing app instance is already running; it should quit the app explicitly or avoid measuring from a dirty state.

## Domain Notes
- `MinimalTodo/ContentView.swift` owns the X Bookmarks setup UI and the popover height callback used by `MinimalTodoApp`.
