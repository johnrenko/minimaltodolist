import SwiftUI
import CoreData

@main
struct MinimalTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(context: PersistenceController.shared.container.viewContext)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var popover = NSPopover()
    private var statusBarItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let context = PersistenceController.shared.container.viewContext
        let contentView = ContentView(context: context)
            .environment(\.managedObjectContext, context)

        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.contentSize = NSSize(width: 380, height: 620)
        popover.behavior = .transient

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusBarItem.button {
            button.image = NSImage(named: "Todo")
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
}
