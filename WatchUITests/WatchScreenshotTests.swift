import XCTest

/// Walks every watch page with sample data and attaches a screenshot of each.
///   xcodebuild test -scheme OpenReadinessWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (46mm)'
@MainActor
final class WatchScreenshotTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-demo"]
        app.launch()
    }

    func testCaptureWatchPages() throws {
        XCTAssertTrue(app.staticTexts["Readiness"].waitForExistence(timeout: 30))
        settle()
        snap("w01-score")

        page()
        snap("w02-contributors")
        let hrv = app.buttons.matching(NSPredicate(format: "label CONTAINS 'HRV'")).firstMatch
        XCTAssertTrue(hrv.waitForExistence(timeout: 5))
        hrv.tap()
        settle()
        snap("w03-hrv-detail")
        app.swipeUp()
        snap("w04-hrv-detail-more")
        app.navigationBars.buttons.firstMatch.tap()
        settle()

        // The contributors list scrolls before the page changes; swipe until the next page shows.
        var swipes = 0
        while !app.staticTexts["Last Night"].exists, swipes < 6 {
            page()
            swipes += 1
        }
        XCTAssertTrue(app.staticTexts["Last Night"].exists)
        snap("w05-last-night")
        page()
        snap("w06-hrv-trend")
        page()
        snap("w07-resting-hr-trend")
        page()
        snap("w08-week")
    }

    /// Next vertical page.
    private func page() {
        app.swipeUp()
        settle()
    }

    private func settle(_ seconds: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
