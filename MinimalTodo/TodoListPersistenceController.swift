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

    init(context: NSManagedObjectContext) {
        self.context = context
        fetchItems()
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

    func addTask(task: String) {
        let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTask.isEmpty else { return }

        let newItem = Item(context: context)
        newItem.id = UUID()
        newItem.task = trimmedTask
        newItem.isCompleted = false
        newItem.createdAt = Date()

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
}
