import XCTest

final class MinimalTodoUITests: XCTestCase {
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        return app
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsTodosHeader() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Todos"].exists)
    }

    func testLaunchPerformance() throws {
        throw XCTSkip("Launch performance metrics are unreliable for this macOS UI test target in automated runs.")
    }
}
