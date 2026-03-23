import AppKit

// MARK: - Row view

private final class DirRowView: NSTableRowView {
    var bgColor: NSColor = .clear
    override var isEmphasized: Bool { get { false } set {} }
    override func draw(_ dirtyRect: NSRect) { bgColor.setFill(); dirtyRect.fill() }
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).setFill()
        dirtyRect.fill()
    }
}

// MARK: - DirCompareViewController

final class DirCompareViewController: NSViewController {

    var leftURL:  URL?
    var rightURL: URL?

    private var allEntries: [DirCompareEntry] = []
    private var entries:    [DirCompareEntry] = []
    private let tableView  = NSTableView()
    private let spinner    = NSProgressIndicator()
    private let countLabel = NSTextField(labelWithString: "")
    private let leftLabel  = NSTextField(labelWithString: "")
    private let rightLabel = NSTextField(labelWithString: "")
    private let reloadButton = NSButton(title: "⟳ 再読み込み", target: nil, action: nil)
    private var shortcutMonitor: Any?

    // MARK: - Init

    convenience init(left: URL, right: URL) {
        self.init(nibName: nil, bundle: nil)
        leftURL = left; rightURL = right
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = CompareDropView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        (view as? CompareDropView)?.onDrop = { urls in
            (NSApp.delegate as? AppDelegate)?.openComparisonWindow(with: urls)
        }
        buildUI()
        loadComparison()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installShortcutMonitorIfNeeded()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        removeShortcutMonitor()
    }

    deinit {
        removeShortcutMonitor()
    }

    // MARK: - Build UI

    private func buildUI() {
        // ── Header ──────────────────────────────────────────────
        let header = NSView()
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        header.translatesAutoresizingMaskIntoConstraints = false

        let backBtn = NSButton(title: "← 戻る", target: self, action: #selector(goBack))
        backBtn.bezelStyle = .rounded
        backBtn.translatesAutoresizingMaskIntoConstraints = false
        reloadButton.target = self
        reloadButton.action = #selector(reloadComparison)
        reloadButton.bezelStyle = .rounded
        reloadButton.font = .systemFont(ofSize: 11, weight: .regular)
        reloadButton.translatesAutoresizingMaskIntoConstraints = false

        for lbl in [leftLabel, rightLabel] {
            lbl.font = .systemFont(ofSize: 11, weight: .medium)
            lbl.textColor = .secondaryLabelColor
            lbl.lineBreakMode = .byTruncatingMiddle
            lbl.translatesAutoresizingMaskIntoConstraints = false
            lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            lbl.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.lineBreakMode = .byTruncatingTail
        countLabel.maximumNumberOfLines = 1
        countLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        countLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        for v in [backBtn, reloadButton, leftLabel, rightLabel, countLabel] as [NSView] {
            header.addSubview(v)
        }
        view.addSubview(header)

        // ── Separator ────────────────────────────────────────────
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sep)

        // ── Table ────────────────────────────────────────────────
        let scroll = NSScrollView()
        scroll.hasVerticalScroller   = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers    = true
        scroll.borderType            = .noBorder
        scroll.backgroundColor       = CellStyle.equal.bgColor
        scroll.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView              = nil
        tableView.rowHeight               = 22
        tableView.intercellSpacing        = .zero
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor         = .clear
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.delegate                = self
        tableView.dataSource              = self

        let badgeCol = NSTableColumn(identifier: .init("badge"))
        badgeCol.width = 64; badgeCol.minWidth = 64; badgeCol.maxWidth = 64
        tableView.addTableColumn(badgeCol)

        let pathCol = NSTableColumn(identifier: .init("path"))
        pathCol.width = 2000; pathCol.minWidth = 300; pathCol.maxWidth = 1_000_000
        tableView.addTableColumn(pathCol)

        scroll.documentView = tableView
        view.addSubview(scroll)

        // ── Spinner ──────────────────────────────────────────────
        spinner.style       = .spinning
        spinner.controlSize = .regular
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        // ── Constraints ──────────────────────────────────────────
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 40),

            backBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backBtn.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            reloadButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            reloadButton.leadingAnchor.constraint(equalTo: backBtn.trailingAnchor, constant: 8),

            leftLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            leftLabel.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 16),
            leftLabel.trailingAnchor.constraint(lessThanOrEqualTo: header.centerXAnchor, constant: -8),

            rightLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            rightLabel.leadingAnchor.constraint(equalTo: header.centerXAnchor, constant: 8),
            rightLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -12),

            countLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),

            sep.topAnchor.constraint(equalTo: header.bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),

            scroll.topAnchor.constraint(equalTo: sep.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        leftLabel.stringValue  = leftURL?.lastPathComponent  ?? ""
        rightLabel.stringValue = rightURL?.lastPathComponent ?? ""
    }

    // MARK: - Load

    @objc private func reloadComparison() {
        loadComparison()
    }

    private func loadComparison() {
        spinner.startAnimation(nil)
        spinner.isHidden = false
        guard let left = leftURL, let right = rightURL else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = DirScanner.compare(left: left, right: right)
            DispatchQueue.main.async {
                guard let self else { return }
                self.allEntries = result
                self.rebuildVisibleEntries()
                self.tableView.reloadData()
                self.updateCountLabel()
                self.spinner.stopAnimation(nil)
                self.spinner.isHidden = true
            }
        }
    }

    private func rebuildVisibleEntries() {
        var visible: [DirCompareEntry] = []
        var collapsedDepth: Int? = nil

        for entry in allEntries {
            if let d = collapsedDepth, entry.depth > d { continue }
            collapsedDepth = nil
            visible.append(entry)
            if entry.isDirectory && !entry.isExpanded {
                collapsedDepth = entry.depth
            }
        }
        entries = visible
    }

    private func toggleDirectory(atVisibleIndex row: Int) {
        guard row >= 0, row < entries.count else { return }
        let target = entries[row]
        guard target.isDirectory else { return }

        guard let idx = allEntries.firstIndex(where: { $0.relativePath == target.relativePath && $0.isDirectory }) else { return }
        allEntries[idx].isExpanded.toggle()
        rebuildVisibleEntries()
        tableView.reloadData()
    }

    private func updateCountLabel() {
        let files = allEntries.filter { !$0.isDirectory }
        let changed   = files.filter { $0.status == .changed || $0.status == .binaryDiff }.count
        let leftOnly  = files.filter { $0.status == .leftOnly  }.count
        let rightOnly = files.filter { $0.status == .rightOnly }.count
        var parts: [String] = []
        if changed   > 0 { parts.append("変更 \(changed)") }
        if leftOnly  > 0 { parts.append("左のみ \(leftOnly)") }
        if rightOnly > 0 { parts.append("右のみ \(rightOnly)") }
        countLabel.stringValue = parts.isEmpty ? "差分なし" : parts.joined(separator: "  ")
    }

    // MARK: - Actions

    @objc private func goBack() {
        (view.window?.windowController as? WindowController)?.pop()
    }

    private func installShortcutMonitorIfNeeded() {
        guard shortcutMonitor == nil else { return }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.modifierFlags.contains(.command),
                  let key = event.charactersIgnoringModifiers?.lowercased() else { return event }
            switch key {
            case "r":
                self.reloadComparison()
                return nil
            case "w":
                self.view.window?.performClose(nil)
                return nil
            case "q":
                NSApp.terminate(nil)
                return nil
            default:
                return event
            }
        }
    }

    private func removeShortcutMonitor() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
    }
}

// MARK: - NSTableViewDataSource / Delegate

extension DirCompareViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView,
                   viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let field = NSTextField(labelWithString: "")
        field.isBordered = false; field.isEditable = false; field.drawsBackground = false

        if column?.identifier.rawValue == "badge" {
            if entry.isDirectory {
                field.stringValue = entry.hasDescendantDiff ? "差異あり" : "差異なし"
                field.textColor = entry.hasDescendantDiff
                    ? NSColor(red: 0.95, green: 0.65, blue: 0.10, alpha: 1)
                    : .tertiaryLabelColor
            } else {
                field.stringValue = entry.status.badge
                field.textColor   = entry.status.badgeColor
            }
            field.font        = .systemFont(ofSize: 10, weight: .semibold)
            field.alignment   = .center
        } else {
            let indent = String(repeating: "  ", count: entry.depth)
            if entry.isDirectory {
                let icon = entry.isExpanded ? "▾" : "▸"
                field.stringValue = "\(indent)\(icon) \(entry.name)"
            } else {
                field.stringValue = "\(indent)  \(entry.name)"
            }
            field.font          = .monospacedSystemFont(ofSize: 12, weight: .regular)
            field.textColor     = entry.status == .same ? .secondaryLabelColor : .labelColor
            field.lineBreakMode = .byClipping
            field.cell?.wraps   = false
        }
        return field
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rv = DirRowView()
        rv.bgColor = entries[row].status.rowBgColor
        return rv
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 22 }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count else { return }
        let entry = entries[row]

        if entry.isDirectory {
            toggleDirectory(atVisibleIndex: row)
            tableView.deselectRow(row)
            return
        }

        switch entry.status {
        case .changed:
            guard let l = entry.leftURL, let r = entry.rightURL else { return }
            (NSApp.delegate as? AppDelegate)?.openFileDiffWindow(left: l, right: r)
            tableView.deselectRow(row)

        case .binaryDiff:
            let alert = NSAlert()
            alert.messageText     = "バイナリファイル"
            alert.informativeText = "バイナリファイルのため差分表示はできません。"
            alert.runModal()
            tableView.deselectRow(row)

        default:
            tableView.deselectRow(row)
        }
    }
}
