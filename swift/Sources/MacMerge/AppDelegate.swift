import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowControllers: [WindowController] = []
    private let startupURLs: [URL]

    override init() {
        let args = CommandLine.arguments.dropFirst()
        startupURLs = args
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let wc = WindowController()
        windowControllers = [wc]
        wc.showWindow(nil)
        if startupURLs.count >= 2 {
            wc.openDroppedPair(left: startupURLs[0], right: startupURLs[1])
        }
        NSApp.activate(ignoringOtherApps: true)
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
}
