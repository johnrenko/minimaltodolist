import XCTest
import CoreData
@testable import MinimalTodo

final class MinimalTodoTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var controller: TodoListPersistenceController!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        controller = TodoListPersistenceController(context: context)
    }

    override func tearDownWithError() throws {
        context = nil
        controller = nil
    }

    func testAddTaskTrimsWhitespaceAndRejectsEmptyValues() throws {
        controller.addTask(task: "   ")
        controller.addTask(task: "   Write tests   ")

        XCTAssertEqual(controller.items.count, 1)
        XCTAssertEqual(controller.items.first?.task, "Write tests")
        XCTAssertEqual(controller.items.first?.isCompleted, false)
    }

    func testAddTaskStoresDeadlineWhenProvided() throws {
        let deadline = Calendar.current.date(byAdding: .day, value: 3, to: Date())!

        controller.addTask(task: "Pay rent", deadline: deadline)

        XCTAssertEqual(controller.items.count, 1)
        XCTAssertEqual(controller.items.first?.deadline, deadline)
    }

    func testToggleCompletionByIdentifier() throws {
        controller.addTask(task: "Ship feature")
        let id = controller.items.first?.id

        controller.toggleIsCompleted(id: id)

        XCTAssertEqual(controller.items.first?.isCompleted, true)
    }

    func testDeleteTaskByIdentifier() throws {
        controller.addTask(task: "A")
        controller.addTask(task: "B")

        let firstId = controller.items.first?.id
        controller.removeTask(id: firstId)

        XCTAssertEqual(controller.items.count, 1)
    }

    func testFilteringDoneAndTodo() throws {
        controller.addTask(task: "todo item")
        controller.addTask(task: "done item")

        let doneId = controller.items.first(where: { $0.task == "done item" })?.id
        controller.toggleIsCompleted(id: doneId)

        controller.selectedFilter = .done
        XCTAssertEqual(controller.items.count, 1)
        XCTAssertEqual(controller.items.first?.task, "done item")

        controller.selectedFilter = .todo
        XCTAssertEqual(controller.items.count, 1)
        XCTAssertEqual(controller.items.first?.task, "todo item")
    }
}
