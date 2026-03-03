# MinimalTodo

MinimalTodo is a lightweight macOS menu bar todo app built with SwiftUI and Core Data.

## What it does

- Adds tasks from a compact popover UI.
- Marks tasks as done/undone by tapping the row.
- Filters tasks by **All / Todo / Done**.
- Persists tasks with Core Data so they survive app restarts.
- Supports a manual light/dark mode toggle in the popover header.

## Project structure

- `MinimalTodo/MinimalTodoApp.swift` — app entry point, menu bar popover setup.
- `MinimalTodo/ContentView.swift` — main UI for input, filtering, and task list.
- `MinimalTodo/TodoListPersistenceController.swift` — task operations and Core Data-backed filtering/sorting.
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
