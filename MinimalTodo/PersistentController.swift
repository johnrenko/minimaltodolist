import CoreData

struct PersistenceController {
    static let cloudKitContainerIdentifier = "iCloud.JD.MinimalTodo"
    static let shared = PersistenceController()
    private static let managedObjectModel: NSManagedObjectModel = {
        let bundle = Bundle(for: ModelBundleLocator.self)
        guard let modelURL = bundle.url(forResource: "TodoListModel", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Unable to load TodoListModel from bundle \(bundle.bundlePath).")
        }
        return model
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(
            name: "TodoListModel",
            managedObjectModel: Self.managedObjectModel
        )

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Missing persistent store description.")
        }

        let usesEphemeralStore = inMemory || Self.isRunningTests

        if usesEphemeralStore {
            // Keep previews and test hosts entirely local so they don't require CloudKit setup.
            description.type = NSInMemoryStoreType
            description.cloudKitContainerOptions = nil
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

    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || arguments.contains("-ui-testing")
    }
}

private final class ModelBundleLocator: NSObject {}
