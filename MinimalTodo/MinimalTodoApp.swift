//
//  MinimalTodoApp.swift
//  MinimalTodo
//
//  Created by John Dutamby 2 on 21/06/2023.
//

import SwiftUI
import CoreData

@main
struct MinimalTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var popover = NSPopover()
    var statusBarItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the SwiftUI view that provides the window contents.
        let contentView = ContentView().environment(\.managedObjectContext, MinimalTodoApp().persistenceController.container.viewContext)

        // Set the popover's content view.
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.contentSize = NSSize(width: 360, height: 360)
        popover.behavior = .transient // This makes the popover close when the user clicks outside of it.
        
        // Create the status item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusBarItem.button {
            button.image = NSImage(named: "Todo")
            button.action = #selector(togglePopover)
        }
    }
    
    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusBarItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
