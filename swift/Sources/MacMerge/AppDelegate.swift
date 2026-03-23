import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowControllers: [WindowController] = []
    private let startupURLs: [URL]

    override init() {
        startupURLs = Self.parseStartupURLs(from: CommandLine.arguments)
        super.init()
    }

    init(startupURLs: [URL]) {
        self.startupURLs = startupURLs
        super.init()
    }

    var openWindowCount: Int { windowControllers.count }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchInitialWindow()
    }

    @discardableResult
    func launchInitialWindow(activateApp: Bool = true) -> WindowController {
        let wc = WindowController()
        windowControllers = [wc]
        wc.showWindow(nil)
        if startupURLs.count >= 2 {
            wc.openDroppedPair(left: startupURLs[0], right: startupURLs[1])
        }
        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
        }
        return wc
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func openComparisonWindow(with droppedURLs: [URL]) {
        guard droppedURLs.count >= 2 else { return }
        let wc = WindowController()
        windowControllers.append(wc)
        wc.showWindow(nil)
        wc.openDroppedPair(left: droppedURLs[0], right: droppedURLs[1])
        NSApp.activate(ignoringOtherApps: true)
    }

    func openFileDiffWindow(left: URL, right: URL) {
        let wc = WindowController()
        windowControllers.append(wc)
        wc.showWindow(nil)
        wc.showDiff(left: left, right: right)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func parseStartupURLs(from args: [String]) -> [URL] {
        let fm = FileManager.default
        return args
            .dropFirst()
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
            .filter { fm.fileExists(atPath: $0.path) }
    }
}
