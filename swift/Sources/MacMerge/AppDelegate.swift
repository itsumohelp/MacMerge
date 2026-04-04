import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowControllers: [WindowController] = []
    private let startupURLs: [URL]
    private var settingsMenuItems: [NSMenuItem] = []

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
        setupMainMenu()
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
        let sourceFrame = NSApp.keyWindow?.frame ?? NSApp.mainWindow?.frame
        let sourceZoomed = (NSApp.keyWindow?.isZoomed == true) || (NSApp.mainWindow?.isZoomed == true)
        let wc = WindowController(initialFrame: sourceFrame)
        windowControllers.append(wc)
        wc.showWindow(nil)
        if sourceZoomed, wc.window?.isZoomed == false {
            wc.window?.zoom(nil)
        }
        wc.openDroppedPair(left: droppedURLs[0], right: droppedURLs[1])
        NSApp.activate(ignoringOtherApps: true)
    }

    func openFileDiffWindow(left: URL, right: URL, sourceWindow: NSWindow? = nil) {
        let sourceWindow = sourceWindow ?? NSApp.keyWindow ?? NSApp.mainWindow
        let sourceFrame = sourceWindow?.frame
        let sourceZoomed = sourceWindow?.isZoomed == true
        let wc = WindowController(initialFrame: sourceFrame)
        windowControllers.append(wc)
        wc.showDiff(left: left, right: right)
        wc.showWindow(nil)
        if sourceZoomed, wc.window?.isZoomed == false {
            wc.window?.zoom(nil)
        }
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

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let settingsItem = NSMenuItem(title: "設定", action: nil, keyEquivalent: "")
        mainMenu.addItem(settingsItem)
        let settingsMenu = NSMenu(title: "設定")
        settingsItem.submenu = settingsMenu

        let boundaryItem = NSMenuItem(title: "最初/最後到達メッセージを表示", action: #selector(toggleBoundaryMessage), keyEquivalent: "")
        boundaryItem.target = self
        boundaryItem.state = AppSettings.shared.showDiffBoundaryMessage ? .on : .off
        settingsMenu.addItem(boundaryItem)

        let crossFileItem = NSMenuItem(title: "差分移動で次/前ファイルへまたぐ", action: #selector(toggleCrossFileNavigation), keyEquivalent: "")
        crossFileItem.target = self
        crossFileItem.state = AppSettings.shared.crossFileDiffNavigation ? .on : .off
        settingsMenu.addItem(crossFileItem)

        settingsMenuItems = [boundaryItem, crossFileItem]
        NSApp.mainMenu = mainMenu
    }

    @objc private func toggleBoundaryMessage(_ sender: NSMenuItem) {
        let newValue = !AppSettings.shared.showDiffBoundaryMessage
        AppSettings.shared.showDiffBoundaryMessage = newValue
        sender.state = newValue ? .on : .off
    }

    @objc private func toggleCrossFileNavigation(_ sender: NSMenuItem) {
        let newValue = !AppSettings.shared.crossFileDiffNavigation
        AppSettings.shared.crossFileDiffNavigation = newValue
        sender.state = newValue ? .on : .off
    }
}
