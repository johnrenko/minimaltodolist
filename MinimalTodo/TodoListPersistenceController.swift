import CoreData

class TodoListPersistenceController: ObservableObject {
    let container: NSPersistentContainer
    
    @Published var items: [Item] = []
    
    init() {
        container = NSPersistentContainer(name: "TodoListModel")
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Error: \(error.localizedDescription)")
            }
        }
        fetchItems()
    }
    
    func fetchItems() {
        let fetchRequest: NSFetchRequest<Item> = Item.fetchRequest()
        
        do {
            items = try container.viewContext.fetch(fetchRequest)
        } catch {
            print("Failed to fetch items!")
        }
    }
    
    func addTask(task: String) {
        let newItem = Item(context: container.viewContext)
        newItem.task = task
        newItem.isCompleted = false
        newItem.id = UUID()
        
        saveContext()
    }
    
    func toggleIsCompleted(forItemAtIndex index: Int) {
        items[index].isCompleted.toggle()
        saveContext()
    }
    
    func removeTask(at offsets: IndexSet) {
        for index in offsets {
            let item = items[index]
            container.viewContext.delete(item)
        }
        saveContext()
    }
    
    func saveContext() {
        if container.viewContext.hasChanges {
            do {
                try container.viewContext.save()
                fetchItems()
            } catch {
                print("An error occurred while saving: \(error)")
            }
        }
    }
    
    func filteredItems(for filter: ContentView.TodoFilter) -> [Item] {
        switch filter {
        case .all:
            return items
        case .done:
            return items.filter { $0.isCompleted }
        case .todo:
            return items.filter { !$0.isCompleted }
        }
    }
}
