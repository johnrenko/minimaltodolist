import XCTest

final class MinimalTodoiOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTodoFlowSmoke() throws {
        let app = XCUIApplication()
        app.launch()

        let taskField = app.textFields["New task"]
        XCTAssertTrue(taskField.waitForExistence(timeout: 5))
        taskField.tap()
        taskField.typeText("Smoke task")

        app.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["Smoke task"].waitForExistence(timeout: 5))

        app.buttons["Smoke task"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Smoke task"].waitForExistence(timeout: 5))

        app.buttons["Todo"].tap()
        XCTAssertFalse(app.buttons["Smoke task"].exists)

        app.buttons["All"].tap()
        XCTAssertTrue(app.buttons["Smoke task"].waitForExistence(timeout: 5))
    }
}
