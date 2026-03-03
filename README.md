# MinimalTodo

MinimalTodo is a lightweight macOS menu bar todo app built with SwiftUI and Core Data.

## What it does

- Adds tasks from a compact popover UI.
- Marks tasks as done/undone by tapping the row.
- Filters tasks by **All / Todo / Done**.
- Persists tasks with Core Data so they survive app restarts.
- Supports System/Light/Dark theme selection in the popover header.
- Syncs X (x.com) bookmarks via the X API and opens tweets in your default browser.

## Project structure

- `MinimalTodo/MinimalTodoApp.swift` — app entry point, menu bar popover setup.
- `MinimalTodo/ContentView.swift` — main UI for input, filtering, task list, and X bookmarks section.
- `MinimalTodo/TodoListPersistenceController.swift` — task operations and Core Data-backed filtering/sorting.
- `MinimalTodo/XBookmarksSyncService.swift` — X API integration and local bookmark cache.
- `MinimalTodo/PersistentController.swift` — Core Data stack configuration.
- `MinimalTodo/TodoListModel.xcdatamodeld` — data model (`Item` entity).
- `MinimalTodoTests/` and `MinimalTodoUITests/` — unit and UI tests.

## Requirements

- macOS with Xcode installed.
- Swift toolchain compatible with the Xcode project.

## Build and run

1. Open `MinimalTodo.xcodeproj` in Xcode.
2. Select the `MinimalTodo` scheme.
3. Build and run.

When launched, the app places a todo icon in the menu bar. Click it to open the todo popover.

## Running tests

From Xcode:

- Product → Test

From terminal (macOS with Xcode command line tools):

```bash
xcodebuild test -project MinimalTodo.xcodeproj -scheme MinimalTodo -destination 'platform=macOS'
```

## Notes

- Tasks are stored locally using Core Data.
- The Core Data stack enables lightweight migration options for model evolution.

## X bookmark sync setup

1. Create an app in the X Developer Portal with access to the Bookmarks endpoint.
2. Copy your **Bearer Token** and your X numeric **User ID**.
3. In the app popover, open **X Bookmarks**. On first use you can click **Open X Login** and **Get API Token** shortcuts to open the right pages in your browser.
4. Paste both values and click **Sync**.
5. Click a synced bookmark to open the tweet in your default browser.

> Note: this feature uses `https://api.x.com/2/users/:id/bookmarks` and stores the last synced results locally in `UserDefaults`.
