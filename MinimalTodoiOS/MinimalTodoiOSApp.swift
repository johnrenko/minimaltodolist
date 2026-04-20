import SwiftUI

@main
struct MinimalTodoiOSApp: App {
    private let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                TodoFeatureRootView(context: persistenceController.container.viewContext)
                    .navigationTitle("Todos")
            }
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
