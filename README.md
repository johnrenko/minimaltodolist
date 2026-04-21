# MinimalTodo

MinimalTodo is a lightweight todo app built with SwiftUI, Core Data, and CloudKit. The project now includes two app targets inside the same Xcode project:

- `MinimalTodo` — the macOS menu bar app.
- `MinimalTodoiOS` — the iPhone companion app.

Todos are stored in a shared Core Data model and synced through CloudKit, so tasks created on macOS can appear on iOS and vice versa when both apps are signed into the same Apple ID.

## Features

- Add tasks from a compact SwiftUI UI.
- Mark tasks as done or undone by tapping the row.
- Filter tasks by **All / Todo / Done**.
- Optionally assign a deadline to each task.
- Sync task creation, completion, and deletion between macOS and iOS with CloudKit.
- Keep macOS-specific extras in the menu bar app:
  - Pomodoro timer
  - Theme selection
  - X (x.com) bookmark import through the bundled Chrome extension
  - Optional paid X API OAuth flow as a fallback for bookmarks

## Targets

- `MinimalTodo`
  - Platform: macOS
  - Minimum OS: macOS 13.0
  - Entry point: `MinimalTodo/MinimalTodoApp.swift`
  - Shell: menu bar popover with Todo, Pomodoro, and X Bookmarks tabs

- `MinimalTodoiOS`
  - Platform: iPhone
  - Minimum OS: iOS 16.0
  - Entry point: `MinimalTodoiOS/MinimalTodoiOSApp.swift`
  - Shell: `NavigationStack` focused on the todo experience only

## Project Structure

- `MinimalTodo/PersistentController.swift` — shared `NSPersistentCloudKitContainer` setup
- `MinimalTodo/TodoListModel.xcdatamodeld` — shared Core Data model (`Item`)
- `MinimalTodo/TodoListPersistenceController.swift` — shared task mutations, filtering, and refresh logic
- `MinimalTodo/TodoFeatureView.swift` — shared cross-platform todo UI
- `MinimalTodo/ContentView.swift` — macOS-only shell that hosts Todo, Pomodoro, and X Bookmarks
- `MinimalTodo/MinimalTodoApp.swift` — macOS app entry and menu bar setup
- `MinimalTodoiOS/MinimalTodoiOSApp.swift` — iOS app entry
- `MinimalTodoiOS/Info.plist` — iOS app plist, including `remote-notification` background mode for CloudKit imports
- `MinimalTodo/XBookmarksSyncService.swift` — macOS bookmark import listener and optional X API integration
- `ChromeExtension/XBookmarksSync/` — unpacked Chrome extension for free bookmark scraping and local import
- `MinimalTodoTests/` and `MinimalTodoUITests/` — macOS tests
- `MinimalTodoiOSTests/` and `MinimalTodoiOSUITests/` — iOS tests

## Requirements

- macOS with Xcode installed
- A recent Xcode version with macOS 13 and iOS 16 SDK support
- An Apple signing setup with iCloud / CloudKit enabled if you want to verify real device sync

## Build And Run

### From Xcode

1. Open `MinimalTodo.xcodeproj`.
2. Select one of these schemes:
   - `MinimalTodo` for the macOS menu bar app
   - `MinimalTodoiOS` for the iPhone app
3. Choose a run destination:
   - `My Mac` for the macOS app
   - An iPhone simulator or device for the iOS app
4. Build and run.

When the macOS app launches, it places an icon in the menu bar. Click it to open the popover.

### From Terminal

Build the macOS app:

```bash
xcodebuild build -project MinimalTodo.xcodeproj -scheme MinimalTodo -destination 'platform=macOS'
```

Build the iOS app:

```bash
xcodebuild build -project MinimalTodo.xcodeproj -scheme MinimalTodoiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
```

Adjust the simulator name if that device is not available on your machine.

## Running Tests

Run macOS tests:

```bash
xcodebuild test -project MinimalTodo.xcodeproj -scheme MinimalTodo -destination 'platform=macOS'
```

Run iOS unit tests:

```bash
xcodebuild test -project MinimalTodo.xcodeproj -scheme MinimalTodoiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -only-testing:MinimalTodoiOSTests
```

Run iOS UI tests:

```bash
xcodebuild test -project MinimalTodo.xcodeproj -scheme MinimalTodoiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -only-testing:MinimalTodoiOSUITests
```

The test and preview paths use an in-memory Core Data store, so they do not require iCloud, CloudKit entitlements, or network connectivity.

## CloudKit Notes

- The shared store is backed by `NSPersistentCloudKitContainer`.
- Both app targets use the same CloudKit container identifier: `iCloud.JD.MinimalTodo`.
- The persistent store keeps the default local SQLite location so existing macOS todos are preserved and uploaded after CloudKit is enabled.
- Remote changes merge automatically into the main view context.
- In debug builds, you can intentionally bootstrap the CloudKit schema by launching the app with this argument:

```text
-InitializeCloudKitSchema
```

Do not use that launch argument for normal everyday runs.

## Manual Sync Verification

1. Build and sign both app targets with iCloud / CloudKit enabled.
2. Sign the macOS app and the iPhone app into the same Apple ID.
3. Launch both apps and wait for the CloudKit-backed store to initialize.
4. Create, complete, and delete tasks on one platform.
5. Confirm the corresponding changes appear on the other platform.

## Free X Bookmark Sync With Chrome (macOS Only)

1. Keep the macOS app running.
2. In Chrome, open `chrome://extensions` and enable **Developer mode**.
3. Click **Load unpacked** and select `ChromeExtension/XBookmarksSync`.
4. Open `https://x.com/i/bookmarks` while signed into the X account whose bookmarks you want.
5. Click the extension icon and confirm the endpoint is `http://127.0.0.1:48123/x-bookmarks/import`.
6. Click **Sync now**.
7. MinimalTodo imports the bookmarks into its local cache. Click any imported bookmark in the app to open the post in your browser.

This path does not use X API credits. It works by scraping the open bookmarks page in Chrome and posting the extracted bookmarks to MinimalTodo's loopback listener on `127.0.0.1`.

## Optional Paid X API Sync (macOS Only)

1. Create an app in the X Developer Portal with access to the Bookmarks endpoint.
2. In that X app's OAuth settings, add this callback URL exactly: `minimaltodo://x-auth`
3. Copy the app's **Client ID**. Do not use the API key, API secret, or a bearer token.
4. In MinimalTodo, expand **Paid X API Sync (Optional)**, paste the Client ID, and click **Connect API**.
5. Finish the browser sign-in flow. MinimalTodo exchanges the code, resolves `/2/users/me`, refreshes the token automatically, and syncs bookmarks for the signed-in account.

> Note: the paid path uses `https://api.x.com/2/users/me`, `https://api.x.com/2/users/:id/bookmarks`, stores OAuth tokens in Keychain, and caches the last imported or synced bookmark list in `UserDefaults`.
