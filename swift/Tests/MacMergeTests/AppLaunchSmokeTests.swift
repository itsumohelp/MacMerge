import XCTest
@testable import MacMerge

final class AppLaunchSmokeTests: XCTestCase {

    func testLaunchInitialWindowCreatesSingleWindowController() {
        let appDelegate = AppDelegate(startupURLs: [])

        _ = appDelegate.launchInitialWindow(activateApp: false)

        XCTAssertEqual(appDelegate.openWindowCount, 1)
    }
}
