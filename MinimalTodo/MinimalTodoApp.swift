import SwiftUI
import CoreData

@MainActor
private final class AppEnvironment {
    static let shared = AppEnvironment()

    let context: NSManagedObjectContext
    let xBookmarksSyncService: XBookmarksSyncService

    private init() {
        context = PersistenceController.shared.container.viewContext
        xBookmarksSyncService = XBookmarksSyncService()
    }
}

private struct StatusItemRestoreView: View {
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Menu bar icon removed")
                .font(.system(size: 18, weight: .semibold))

            Text("MinimalTodo cannot re-add its menu bar icon after macOS removes it.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("To restore it:")
                    .font(.system(size: 13, weight: .semibold))
                Text("1. Open System Settings")
                Text("2. Go to Menu Bar")
                Text("3. In \"Allow in the Menu Bar\", turn MinimalTodo back on")
            }
            .font(.system(size: 13))
            .foregroundColor(.primary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Quit", action: onQuit)

                Spacer()

                Button("Open System Settings", action: onOpenSettings)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

@main
struct MinimalTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let environment = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            ContentView(
                context: environment.context,
                xBookmarksSyncService: environment.xBookmarksSyncService
            )
            .environment(\.managedObjectContext, environment.context)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private enum Constants {
        static let statusItemAutosaveName = "JD.MinimalTodo.StatusItem"
        static let restoreWindowSize = NSSize(width: 400, height: 230)
        static let systemSettingsAppPath = "/System/Applications/System Settings.app"
    }

    private let environment = AppEnvironment.shared
    private let popover = NSPopover()
    private var statusBarItem: NSStatusItem!
    private var statusItemVisibilityObserver: NSKeyValueObservation?
    private var pendingRestoreWindowTask: Task<Void, Never>?
    private var hasFinishedLaunching = false
    private var restoreWindowActivationPolicy: NSApplication.ActivationPolicy?
    private lazy var statusItemRestoreWindow: NSWindow = makeStatusItemRestoreWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment.xBookmarksSyncService.startExtensionImportListenerIfNeeded()

        let contentView = ContentView(
            context: environment.context,
            xBookmarksSyncService: environment.xBookmarksSyncService,
            capturesAuthenticationAnchor: true,
            preferredPopoverHeightChanged: { [weak self] height in
                self?.updatePopoverHeight(height)
            }
        )
        .environment(\.managedObjectContext, environment.context)

        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.contentSize = NSSize(width: 400, height: 700)
        popover.behavior = .transient

        installStatusBarItem()
        hasFinishedLaunching = true

        if !statusBarItem.isVisible {
            scheduleStatusItemRestoreWindow()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard statusBarItem != nil, !statusBarItem.isVisible else {
            return
        }

        showStatusItemRestoreWindow()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusBarItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updatePopoverHeight(_ height: CGFloat) {
        let size = NSSize(width: popover.contentSize.width, height: height)
        guard popover.contentSize != size else {
            return
        }

        popover.contentSize = size
    }

    private func installStatusBarItem() {
        statusItemVisibilityObserver = nil
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusBarItem.autosaveName = Constants.statusItemAutosaveName
        statusBarItem.behavior = .removalAllowed

        if let button = statusBarItem.button {
            let statusImage = NSImage(named: "Todo")
            statusImage?.isTemplate = true
            button.image = statusImage
            button.target = self
            button.action = #selector(togglePopover)
        }

        observeStatusItemVisibility()
    }

    private func observeStatusItemVisibility() {
        statusItemVisibilityObserver = statusBarItem.observe(\.isVisible, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.handleStatusItemVisibility(isVisible: item.isVisible)
            }
        }
    }

    private func handleStatusItemVisibility(isVisible: Bool) {
        guard !isVisible else {
            pendingRestoreWindowTask?.cancel()
            statusItemRestoreWindow.orderOut(nil)
            restoreActivationPolicyIfNeeded()
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        }

        scheduleStatusItemRestoreWindow()
    }

    private func showStatusItemRestoreWindow() {
        if restoreWindowActivationPolicy == nil {
            restoreWindowActivationPolicy = NSApp.activationPolicy()
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        statusItemRestoreWindow.orderFrontRegardless()
        statusItemRestoreWindow.makeKeyAndOrderFront(nil)
    }

    private func scheduleStatusItemRestoreWindow() {
        pendingRestoreWindowTask?.cancel()
        pendingRestoreWindowTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            if !self.hasFinishedLaunching {
                await Task.yield()
            }

            guard self.statusBarItem?.isVisible == false else {
                return
            }

            self.showStatusItemRestoreWindow()
        }
    }

    func showStatusItemRestoreInstructions() {
        showStatusItemRestoreWindow()
    }

    private func openSystemSettings() {
        let systemSettingsURL = URL(fileURLWithPath: Constants.systemSettingsAppPath)
        NSWorkspace.shared.open(systemSettingsURL)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as AnyObject? === statusItemRestoreWindow else {
            return
        }

        restoreActivationPolicyIfNeeded()
    }

    private func makeStatusItemRestoreWindow() -> NSWindow {
        let contentView = StatusItemRestoreView(
            onOpenSettings: { [weak self] in
                self?.openSystemSettings()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Constants.restoreWindowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Restore Menu Bar Icon"
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: contentView)

        return window
    }

    private func restoreActivationPolicyIfNeeded() {
        guard let activationPolicy = restoreWindowActivationPolicy else {
            return
        }

        NSApp.setActivationPolicy(activationPolicy)
        restoreWindowActivationPolicy = nil
    }
}
