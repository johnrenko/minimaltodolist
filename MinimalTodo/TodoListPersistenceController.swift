import CoreData

final class TodoListPersistenceController: ObservableObject {
    enum TodoFilter: String, CaseIterable {
        case all
        case done
        case todo
    }

    @Published private(set) var items: [Item] = []
    @Published var selectedFilter: TodoFilter = .all {
        didSet { fetchItems() }
    }

    private let context: NSManagedObjectContext
    private var contextObserver: NSObjectProtocol?

    init(context: NSManagedObjectContext) {
        self.context = context
        contextObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: context,
            queue: .main
        ) { [weak self] notification in
            self?.handleContextObjectsDidChange(notification)
        }
        fetchItems()
    }

    deinit {
        if let contextObserver {
            NotificationCenter.default.removeObserver(contextObserver)
        }
    }

    func fetchItems() {
        let fetchRequest: NSFetchRequest<Item> = Item.fetchRequest()
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "isCompleted", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]

        switch selectedFilter {
        case .all:
            fetchRequest.predicate = nil
        case .done:
            fetchRequest.predicate = NSPredicate(format: "isCompleted == YES")
        case .todo:
            fetchRequest.predicate = NSPredicate(format: "isCompleted == NO")
        }

        do {
            items = try context.fetch(fetchRequest)
        } catch {
            print("Failed to fetch items: \(error.localizedDescription)")
            items = []
        }
    }

    func addTask(task: String, deadline: Date? = nil) {
        let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTask.isEmpty else { return }

        let newItem = Item(context: context)
        newItem.id = UUID()
        newItem.task = trimmedTask
        newItem.isCompleted = false
        newItem.createdAt = Date()
        newItem.deadline = deadline

        saveContext()
    }

    func toggleIsCompleted(id: UUID?) {
        guard let id,
              let item = items.first(where: { $0.id == id }) else { return }

        item.isCompleted.toggle()
        saveContext()
    }

    func removeTask(id: UUID?) {
        guard let id,
              let item = items.first(where: { $0.id == id }) else { return }

        context.delete(item)
        saveContext()
    }

    private func saveContext() {
        guard context.hasChanges else { return }

        do {
            try context.save()
            fetchItems()
        } catch {
            print("An error occurred while saving: \(error.localizedDescription)")
        }
    }

    private func handleContextObjectsDidChange(_ notification: Notification) {
        guard notificationContainsRelevantItemChanges(notification) else {
            return
        }

        fetchItems()
    }

    private func notificationContainsRelevantItemChanges(_ notification: Notification) -> Bool {
        let keys = [
            NSInsertedObjectsKey,
            NSUpdatedObjectsKey,
            NSDeletedObjectsKey,
            NSRefreshedObjectsKey
        ]

        return keys.contains { key in
            guard let objects = notification.userInfo?[key] as? Set<NSManagedObject> else {
                return false
            }

            return objects.contains(where: { $0.entity.name == "Item" })
        }
    }
}
