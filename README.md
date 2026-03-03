# MinimalTodo

MinimalTodo is a lightweight macOS menu bar todo app built with SwiftUI and Core Data.

## What it does

- Adds tasks from a compact popover UI.
- Marks tasks as done/undone by tapping the row.
- Filters tasks by **All / Todo / Done**.
- Persists tasks with Core Data so they survive app restarts.
- Supports System/Light/Dark theme selection in the popover header.
- Imports X (x.com) bookmarks for free through a local Chrome extension, with an optional paid X API OAuth flow as a fallback.

## Project structure

- `MinimalTodo/MinimalTodoApp.swift` — app entry point, menu bar popover setup.
- `MinimalTodo/ContentView.swift` — main UI for input, filtering, task list, and X bookmarks section.
- `MinimalTodo/TodoListPersistenceController.swift` — task operations and Core Data-backed filtering/sorting.
- `MinimalTodo/XBookmarksSyncService.swift` — X bookmark import listener, optional X API integration, and local bookmark cache.
- `MinimalTodo/PersistentController.swift` — Core Data stack configuration.
- `MinimalTodo/TodoListModel.xcdatamodeld` — data model (`Item` entity).
- `ChromeExtension/XBookmarksSync/` — unpacked Chrome extension for free bookmark scraping and local import.
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

## Free X bookmark sync with Chrome

1. Keep MinimalTodo running.
2. In Chrome, open `chrome://extensions` and enable **Developer mode**.
3. Click **Load unpacked** and select `ChromeExtension/XBookmarksSync`.
4. Open `https://x.com/i/bookmarks` while signed into the X account whose bookmarks you want.
5. Click the extension icon and confirm the endpoint is `http://127.0.0.1:48123/x-bookmarks/import`.
6. Click **Sync now**.
7. MinimalTodo imports the bookmarks into its local cache. Click any imported bookmark in the app to open the post in your browser.

This path does not use X API credits. It works by scraping the open bookmarks page in Chrome and posting the extracted bookmarks to MinimalTodo's loopback listener on `127.0.0.1`.

## Optional paid X API sync

1. Create an app in the X Developer Portal with access to the Bookmarks endpoint.
2. In that X app's OAuth settings, add this callback URL exactly: `minimaltodo://x-auth`
3. Copy the app's **Client ID**. Do not use the API key, API secret, or a bearer token.
4. In MinimalTodo, expand **Paid X API Sync (Optional)**, paste the Client ID, and click **Connect API**.
5. Finish the browser sign-in flow. MinimalTodo exchanges the code, resolves `/2/users/me`, refreshes the token automatically, and syncs bookmarks for the signed-in account.

> Note: the paid path uses `https://api.x.com/2/users/me`, `https://api.x.com/2/users/:id/bookmarks`, stores OAuth tokens in Keychain, and caches the last imported or synced bookmark list in `UserDefaults`.
