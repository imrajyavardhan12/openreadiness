import XCTest

/// Walks every main screen with sample data and attaches a screenshot of each.
/// Doubles as a smoke test and as the source of README/App Store screenshots:
///   xcodebuild test -scheme OpenReadiness -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
@MainActor
final class ScreenshotTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        // Screenshots use sample data by default. For local review against data already loaded in the
        // Simulator (e.g. an imported export), run with TEST_RUNNER_UITEST_USE_STORED_DATA=1.
        // Those screenshots are personal: never commit them.
        let useStoredData = ProcessInfo.processInfo.environment["UITEST_USE_STORED_DATA"] == "1"
        app.launchArguments = useStoredData ? [] : ["-demo"]
        app.launch()
    }

    func testReadinessScreens() throws {
        XCTAssertTrue(app.staticTexts["What's driving your score"].waitForExistence(timeout: 20) ||
                      app.otherElements["Readiness"].waitForExistence(timeout: 1))
        snap("01-today")
        app.swipeUp()
        snap("02-today-contributors")

        app.swipeDown()
        let hrv = button(containing: "Heart Rate Variability")
        if !hrv.isHittable { app.swipeUp() }
        hrv.tap()
        settle()
        snap("03-hrv-detail")
        back()

        app.swipeDown(); app.swipeDown()
        app.navigationBars.buttons["History"].tap()
        settle()
        snap("04-history")
    }

    func testHealthScreens() throws {
        app.tabBars.buttons["Health"].tap()
        XCTAssertTrue(button(containing: "Activity Rings").waitForExistence(timeout: 30))
        settle()
        snap("10-health")
        app.swipeUp()
        snap("11-health-more")
        app.swipeUp()
        snap("12-health-more-2")

        app.swipeDown(); app.swipeDown(); app.swipeDown()
        open("Steps", name: "13-steps", scrolls: 2)
        open("Heart Rate,", name: "14-heart-rate", scrolls: 0)
        open("HRV", name: "15-hrv", scrolls: 1)
        open("Activity Rings", name: "16-rings", scrolls: 1)
        open("Sleep", name: "17-sleep", scrolls: 2)
        open("Your day, hour by hour", name: "18-timeline", scrolls: 1)
    }

    func testWorkoutsAndInsights() throws {
        app.tabBars.buttons["Workouts"].tap()
        XCTAssertTrue(app.staticTexts["Minutes per week"].waitForExistence(timeout: 30) ||
                      app.staticTexts["MINUTES PER WEEK"].exists)
        settle()
        snap("20-workouts")
        // Any workout row (rows read "Activity, day · duration …").
        visibleButton(containing: " · ").tap()
        settle(2)
        snap("21-workout-detail")
        app.swipeUp()
        snap("22-workout-zones")

        app.tabBars.buttons["Insights"].tap()
        settle(3)
        snap("30-insights")
        app.swipeUp()
        snap("31-insights-more")
        app.swipeUp(); app.swipeUp()
        snap("32-insights-explorer")
    }

    func testWidgetGallery() throws {
        app.tabBars.buttons["About"].tap()
        let gallery = app.buttons["Widget gallery"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 10))
        gallery.tap()
        settle()
        snap("40-widgets")
        app.swipeUp()
        snap("41-widgets-lock-screen")
    }

    func testCSVExportOpensShareSheet() throws {
        // Load the Health tab first so both exports are enabled.
        app.tabBars.buttons["Health"].tap()
        XCTAssertTrue(button(containing: "Activity Rings").waitForExistence(timeout: 30))
        app.tabBars.buttons["About"].tap()
        let export = app.buttons["Export readiness history"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        snap("50-about-export")
        export.tap()
        // The share sheet shows the file name of the CSV it was handed.
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 15) || app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'csv'")).firstMatch.exists)
        settle(1.5)
        snap("51-share-sheet")
    }

    // MARK: - Helpers

    private func open(_ label: String, name: String, scrolls: Int) {
        let target = button(containing: label)
        var attempts = 0
        while !target.isHittable, attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        target.tap()
        settle()
        snap(name)
        for i in 0..<scrolls {
            app.swipeUp()
            snap("\(name)-\(i + 2)")
        }
        back()
        for _ in 0..<(attempts + 1) { app.swipeDown() }
    }

    /// The first on-screen button containing `text` that isn't hidden behind the floating tab bar.
    private func visibleButton(containing text: String) -> XCUIElement {
        let candidates = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text))
        let limit = app.frame.height - 140
        for index in 0..<candidates.count {
            let element = candidates.element(boundBy: index)
            if element.isHittable, element.frame.minY > 120, element.frame.maxY < limit { return element }
        }
        return candidates.firstMatch
    }

    /// A button whose own label contains `text` (rows combine their children into one label).
    private func button(containing text: String) -> XCUIElement {
        let own = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        return own.exists ? own : app.buttons.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        settle(0.6)
    }

    private func settle(_ seconds: TimeInterval = 1) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
