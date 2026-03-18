import AppKit

// MARK: - Drag-accepting view

final class DropZoneView: NSView {

    var onDrop: (([URL]) -> Void)?
    private var isHovered = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isHovered = true; needsDisplay = true; return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        isHovered = false; needsDisplay = true
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHovered = false; needsDisplay = true
        guard let items = sender.draggingPasteboard
            .readObjects(forClasses: [NSURL.self],
                         options: [.urlReadingFileURLsOnly: true]) as? [URL]
        else { return false }
        onDrop?(items)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg: NSColor = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.118, green: 0.118, blue: 0.153, alpha: 1)
            : NSColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        bg.setFill()
        dirtyRect.fill()

        if isHovered {
            let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 20, dy: 20),
                                     xRadius: 16, yRadius: 16)
            NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
            border.lineWidth = 2
            border.stroke()
        }
    }
}

// MARK: - WelcomeViewController

final class WelcomeViewController: NSViewController {

    private let dropZone = DropZoneView(frame: .zero)
    private var pendingLeft: URL?

    override func loadView() {
        view = dropZone
        view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        dropZone.onDrop = { [weak self] urls in self?.handleDrop(urls) }
    }

    private func buildUI() {
        let icon = NSTextField(labelWithString: "⇄")
        icon.font = .systemFont(ofSize: 80, weight: .ultraLight)
        icon.textColor = .tertiaryLabelColor

        let title = NSTextField(labelWithString: "MacMerge")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        title.textColor = .labelColor

        let sub = NSTextField(labelWithString: "ファイルまたはフォルダを2つドロップして比較")
        sub.font = .systemFont(ofSize: 14)
        sub.textColor = .secondaryLabelColor

        let inputBtn = NSButton(title: "入力して比較する", target: self, action: #selector(openInputCompare))
        inputBtn.bezelStyle = .rounded
        inputBtn.font = .systemFont(ofSize: 13, weight: .semibold)

        for v in [icon, title, sub, inputBtn] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -60),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
            sub.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            inputBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            inputBtn.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 18),
        ])
    }

    @objc private func openInputCompare() {
        guard let wc = view.window?.windowController as? WindowController else { return }
        wc.showTextCompareInput()
    }

    private func handleDrop(_ urls: [URL]) {
        guard let wc = view.window?.windowController as? WindowController else { return }

        if urls.count >= 2 {
            open(wc: wc, left: urls[0], right: urls[1])
        } else if urls.count == 1 {
            if let left = pendingLeft {
                open(wc: wc, left: left, right: urls[0])
                pendingLeft = nil
            } else {
                pendingLeft = urls[0]
                showWaiting(path: urls[0].lastPathComponent)
            }
        }
    }

    private func open(wc: WindowController, left: URL, right: URL) {
        let isDir: (URL) -> Bool = {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        if isDir(left) && isDir(right) {
            wc.showDirCompare(left: left, right: right)
        } else {
            wc.showDiff(left: left, right: right)
        }
    }

    private func showWaiting(path: String) {
        // Update subtitle to show 1 file is loaded
        for sv in view.subviews {
            if let f = sv as? NSTextField, f.stringValue.contains("ドロップ") {
                f.stringValue = "「\(path)」を受け取りました。もう1つをドロップ"
            }
        }
    }
}
