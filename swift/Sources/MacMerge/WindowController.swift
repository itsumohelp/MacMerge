import AppKit

private final class MainWindow: NSWindow {
    private let doubleClickTopInset: CGFloat = 36

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseUp,
           event.clickCount == 2 {
            let p = event.locationInWindow
            if p.y >= frame.height - doubleClickTopInset {
                if !isZoomed {
                    zoom(nil)
                }
                return
            }
        }
        super.sendEvent(event)
    }
}

final class WindowController: NSWindowController {

    private var vcStack: [NSViewController] = []
    private typealias WindowState = (frame: NSRect, isZoomed: Bool)

    convenience init() {
        self.init(initialFrame: nil)
    }

    convenience init(initialFrame: NSRect?) {
        let window = MainWindow(
            contentRect: initialFrame ?? NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppVersion.displayTitle()
        window.minSize = NSSize(width: 480, height: 320)
        window.center()
        window.titlebarAppearsTransparent = true
        self.init(window: window)
        showWelcome()
    }

    func showWelcome() {
        applyKeepingWindowState {
            vcStack.removeAll()
            window?.contentViewController = WelcomeViewController()
        }
    }

    /// Push a new view controller onto the navigation stack.
    func push(_ vc: NSViewController) {
        applyKeepingWindowState {
            if let current = window?.contentViewController {
                vcStack.append(current)
            }
            window?.contentViewController = vc
        }
    }

    /// Pop back to the previous view controller (or Welcome if stack is empty).
    func pop() {
        applyKeepingWindowState {
            if let prev = vcStack.popLast() {
                window?.contentViewController = prev
            } else {
                vcStack.removeAll()
                window?.contentViewController = WelcomeViewController()
            }
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
        applyKeepingWindowState {
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

    private func captureWindowState() -> WindowState? {
        guard let window else { return nil }
        return (frame: window.frame, isZoomed: window.isZoomed)
    }

    private func restoreWindowState(_ state: WindowState?) {
        guard let window, let state else { return }
        window.setFrame(state.frame, display: false)
        if state.isZoomed, !window.isZoomed {
            window.zoom(nil)
        }
    }

    private func applyKeepingWindowState(_ changes: () -> Void) {
        let state = captureWindowState()
        changes()
        restoreWindowState(state)
    }
}
