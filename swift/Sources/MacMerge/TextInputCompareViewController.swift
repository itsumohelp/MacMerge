import AppKit

final class NonInteractiveLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class FocusingScrollView: NSScrollView {
    weak var editor: NSTextView?

    override func mouseDown(with event: NSEvent) {
        if let editor { window?.makeFirstResponder(editor) }
        super.mouseDown(with: event)
    }
}

final class PasteEnabledTextView: NSTextView {
    var onFocus: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?() }
        return ok
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onFocus?()
        super.mouseDown(with: event)
    }
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars == "v" {
            pasteAsPlainText(nil)
            return
        }
        super.keyDown(with: event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars == "v" {
            pasteAsPlainText(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class TextInputCompareViewController: NSViewController {

    private let leftTextView = PasteEnabledTextView()
    private let rightTextView = PasteEnabledTextView()
    private weak var activeEditor: NSTextView?
    private var keyMonitor: Any?

    override func loadView() {
        view = CompareDropView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        (view as? CompareDropView)?.onDrop = { urls in
            (NSApp.delegate as? AppDelegate)?.openComparisonWindow(with: urls)
        }
        buildUI()
        leftTextView.onFocus = { [weak self] in self?.activeEditor = self?.leftTextView }
        rightTextView.onFocus = { [weak self] in self?.activeEditor = self?.rightTextView }
        installShortcutMonitor()
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    private func buildUI() {
        let header = NSView()
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        header.translatesAutoresizingMaskIntoConstraints = false

        let backBtn = NSButton(title: "← 戻る", target: self, action: #selector(goBack))
        backBtn.bezelStyle = .rounded
        backBtn.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "入力して比較")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.translatesAutoresizingMaskIntoConstraints = false

        let compareBtn = NSButton(title: "比較する", target: self, action: #selector(compareText))
        compareBtn.bezelStyle = .rounded
        compareBtn.translatesAutoresizingMaskIntoConstraints = false

        for v in [backBtn, title, compareBtn] as [NSView] {
            header.addSubview(v)
        }
        view.addSubview(header)

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)

        let leftScroll = makeTextScroll(textView: leftTextView, placeholder: "左側のテキストを入力")
        let rightScroll = makeTextScroll(textView: rightTextView, placeholder: "右側のテキストを入力")
        let mid = NSView()
        mid.wantsLayer = true
        mid.layer?.backgroundColor = NSColor.separatorColor.cgColor
        mid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mid)
        view.addSubview(leftScroll)
        view.addSubview(rightScroll)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 40),

            backBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backBtn.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: backBtn.trailingAnchor, constant: 16),
            compareBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            compareBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),

            divider.topAnchor.constraint(equalTo: header.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            mid.topAnchor.constraint(equalTo: divider.bottomAnchor),
            mid.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mid.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mid.widthAnchor.constraint(equalToConstant: 1),

            leftScroll.topAnchor.constraint(equalTo: divider.bottomAnchor),
            leftScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftScroll.trailingAnchor.constraint(equalTo: mid.leadingAnchor),
            leftScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            rightScroll.topAnchor.constraint(equalTo: divider.bottomAnchor),
            rightScroll.leadingAnchor.constraint(equalTo: mid.trailingAnchor),
            rightScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        leftTextView.window?.makeFirstResponder(leftTextView)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.window?.makeFirstResponder(self.leftTextView)
            self.activeEditor = self.leftTextView
        }
    }

    private func makeTextScroll(textView: NSTextView, placeholder: String) -> NSScrollView {
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let inputTextColor = NSColor(name: nil) { trait in
            trait.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.92, alpha: 1)
                : NSColor(calibratedWhite: 0.12, alpha: 1)
        }
        textView.textColor = inputTextColor
        textView.insertionPointColor = inputTextColor
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: inputTextColor
        ]
        textView.backgroundColor = CellStyle.equal.bgColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = ""
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineBreakMode = .byClipping
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.height]

        let sv = FocusingScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = true
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        sv.documentView = textView
        sv.editor = textView
        sv.backgroundColor = CellStyle.equal.bgColor

        let hint = NonInteractiveLabel(labelWithString: placeholder)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        sv.contentView.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: sv.contentView.leadingAnchor, constant: 10),
            hint.topAnchor.constraint(equalTo: sv.contentView.topAnchor, constant: 8),
        ])
        NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) { _ in
            hint.isHidden = !textView.string.isEmpty
        }
        return sv
    }

    @objc private func goBack() {
        (view.window?.windowController as? WindowController)?.pop()
    }

    @objc private func compareText() {
        guard let wc = view.window?.windowController as? WindowController else { return }
        wc.showDiff(leftText: leftTextView.string, rightText: rightTextView.string)
    }

    private func installShortcutMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags.intersection([.command, .control])
            guard !mods.isEmpty else { return event }
            guard let key = event.charactersIgnoringModifiers?.lowercased() else { return event }

            let target: NSTextView? = {
                if let active = self.activeEditor { return active }
                return self.view.window?.firstResponder as? NSTextView
            }()
            guard let editor = target, editor === self.leftTextView || editor === self.rightTextView else {
                return event
            }

            switch key {
            case "a":
                editor.selectAll(nil)
                return nil
            case "c":
                editor.copy(nil)
                return nil
            case "x":
                editor.cut(nil)
                return nil
            case "v":
                editor.pasteAsPlainText(nil)
                return nil
            case "z":
                editor.undoManager?.undo()
                return nil
            case "y":
                editor.undoManager?.redo()
                return nil
            default:
                return event
            }
        }
    }
}
