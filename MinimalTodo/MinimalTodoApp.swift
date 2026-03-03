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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment = AppEnvironment.shared
    private let popover = NSPopover()
    private var statusBarItem: NSStatusItem!

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

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusBarItem.button {
            let statusImage = NSImage(named: "Todo")
            statusImage?.isTemplate = true
            button.image = statusImage
            button.action = #selector(togglePopover)
        }
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
}
