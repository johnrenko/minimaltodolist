import CoreData

struct PersistenceController {
    static let cloudKitContainerIdentifier = "iCloud.JD.MinimalTodo"
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "TodoListModel")

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Missing persistent store description.")
        }

        let usesEphemeralStore = inMemory || Self.isRunningTests

        if usesEphemeralStore {
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerIdentifier
            )
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        #if DEBUG
        if !inMemory, ProcessInfo.processInfo.arguments.contains("-InitializeCloudKitSchema") {
            do {
                try container.initializeCloudKitSchema(options: [])
            } catch {
                assertionFailure("Failed to initialize CloudKit schema: \(error.localizedDescription)")
            }
        }
        #endif
    }

    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                fatalError("Unresolved error \(error)")
            }
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
