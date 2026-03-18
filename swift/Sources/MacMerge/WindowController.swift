import AppKit

final class WindowController: NSWindowController {

    private var vcStack: [NSViewController] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MacMerge"
        window.minSize = NSSize(width: 800, height: 500)
        window.center()
        window.titlebarAppearsTransparent = true
        self.init(window: window)
        showWelcome()
    }

    func showWelcome() {
        vcStack.removeAll()
        window?.contentViewController = WelcomeViewController()
    }

    /// Push a new view controller onto the navigation stack.
    func push(_ vc: NSViewController) {
        if let current = window?.contentViewController {
            vcStack.append(current)
        }
        window?.contentViewController = vc
    }

    /// Pop back to the previous view controller (or Welcome if stack is empty).
    func pop() {
        if let prev = vcStack.popLast() {
            window?.contentViewController = prev
        } else {
            showWelcome()
        }
    }

    func showDiff(left: URL, right: URL) {
        push(DiffViewController(left: left, right: right))
    }

    func showDiff(leftText: String, rightText: String) {
        push(DiffViewController(leftText: leftText, rightText: rightText))
    }

    func showDirCompare(left: URL, right: URL) {
        push(DirCompareViewController(left: left, right: right))
    }

    func showTextCompareInput() {
        push(TextInputCompareViewController())
    }

    func openDroppedPair(left: URL, right: URL) {
        let isDir: (URL) -> Bool = {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        if isDir(left) && isDir(right) {
            showDirCompare(left: left, right: right)
        } else {
            showDiff(left: left, right: right)
        }
    }
}
