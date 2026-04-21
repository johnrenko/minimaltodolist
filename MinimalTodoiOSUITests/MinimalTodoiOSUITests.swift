import XCTest

final class MinimalTodoiOSUITests: XCTestCase {
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        return app
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTodoFlowSmoke() throws {
        let app = makeApp()
        app.launch()

        let taskField = app.textFields["New task"]
        XCTAssertTrue(taskField.waitForExistence(timeout: 5))
        taskField.tap()
        taskField.typeText("Smoke task")

        app.buttons["Add"].tap()
        let smokeTaskButton = app.buttons["Smoke task"].firstMatch
        XCTAssertTrue(smokeTaskButton.waitForExistence(timeout: 5))

        smokeTaskButton.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Smoke task"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Todo"].tap()
        XCTAssertFalse(app.buttons["Smoke task"].exists)

        app.buttons["All"].tap()
        XCTAssertTrue(app.buttons["Smoke task"].firstMatch.waitForExistence(timeout: 5))
    }
}
