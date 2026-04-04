import AppKit

// MARK: - Row view

private final class DirRowView: NSTableRowView {
    var bgColor: NSColor = .clear
    override var isEmphasized: Bool { get { false } set {} }
    override func draw(_ dirtyRect: NSRect) {
        bgColor.setFill()
        dirtyRect.fill()
        guard isSelected else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
        dirtyRect.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.95).setStroke()
        let path = NSBezierPath(rect: dirtyRect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }
    override func drawSelection(in dirtyRect: NSRect) {
        // Selection rendering is handled in draw(_:) to ensure visibility in all focus states.
    }
}

// MARK: - DirCompareViewController

final class DirCompareViewController: NSViewController {

    var leftURL:  URL?
    var rightURL: URL?

    private var allEntries: [DirCompareEntry] = []
    private var entries:    [DirCompareEntry] = []
    private var previewDiffVC: DiffViewController?
    private let tableView  = NSTableView()
    private let spinner    = NSProgressIndicator()
    private let countLabel = NSTextField(labelWithString: "")
    private let leftLabel  = NSTextField(labelWithString: "")
    private let rightLabel = NSTextField(labelWithString: "")
    private let reloadButton = NSButton(title: "⟳ 再読み込み", target: nil, action: nil)
    private let helpButton = NSButton(title: "？", target: nil, action: nil)
    private let splitView = NSSplitView()
    private let listPane = NSView()
    private let previewPane = NSView()
    private let previewPlaceholder = NSTextField(labelWithString: "左の差分ファイルを選択してください")
    private var selectedPath: String?
    private var lastSelectedRow: Int = -1
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
        restoreSelection()
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
        helpButton.target = self
        helpButton.action = #selector(showHelpDialog)
        helpButton.bezelStyle = .rounded
        helpButton.font = .systemFont(ofSize: 12, weight: .bold)
        helpButton.translatesAutoresizingMaskIntoConstraints = false

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

        for v in [backBtn, reloadButton, leftLabel, rightLabel, countLabel, helpButton] as [NSView] {
            header.addSubview(v)
        }
        view.addSubview(header)

        // ── Separator ────────────────────────────────────────────
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sep)

        // ── Split view (left: directory, right: diff preview) ───
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        view.addSubview(splitView)
        splitView.addArrangedSubview(listPane)
        splitView.addArrangedSubview(previewPane)
        listPane.translatesAutoresizingMaskIntoConstraints = false
        previewPane.translatesAutoresizingMaskIntoConstraints = false

        // ── Table (left pane) ────────────────────────────────────
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
        tableView.target                  = self
        tableView.action                  = #selector(handleTableClick)

        let badgeCol = NSTableColumn(identifier: .init("badge"))
        badgeCol.width = 64; badgeCol.minWidth = 64; badgeCol.maxWidth = 64
        tableView.addTableColumn(badgeCol)

        let pathCol = NSTableColumn(identifier: .init("path"))
        pathCol.width = 2000; pathCol.minWidth = 300; pathCol.maxWidth = 1_000_000
        tableView.addTableColumn(pathCol)

        scroll.documentView = tableView
        listPane.addSubview(scroll)

        // ── Spinner (left pane) ──────────────────────────────────
        spinner.style       = .spinning
        spinner.controlSize = .regular
        spinner.translatesAutoresizingMaskIntoConstraints = false
        listPane.addSubview(spinner)

        // ── Preview placeholder (right pane) ─────────────────────
        previewPlaceholder.font = .systemFont(ofSize: 13, weight: .regular)
        previewPlaceholder.textColor = .tertiaryLabelColor
        previewPlaceholder.alignment = .center
        previewPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        previewPane.addSubview(previewPlaceholder)

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
            countLabel.trailingAnchor.constraint(equalTo: helpButton.leadingAnchor, constant: -8),
            helpButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            helpButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            helpButton.widthAnchor.constraint(equalToConstant: 26),

            sep.topAnchor.constraint(equalTo: header.bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),

            splitView.topAnchor.constraint(equalTo: sep.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            listPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            listPane.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            previewPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),

            scroll.topAnchor.constraint(equalTo: listPane.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: listPane.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: listPane.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: listPane.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: listPane.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: listPane.centerYAnchor),

            previewPlaceholder.centerXAnchor.constraint(equalTo: previewPane.centerXAnchor),
            previewPlaceholder.centerYAnchor.constraint(equalTo: previewPane.centerYAnchor),
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
                self.restoreSelection()
                if self.tableView.selectedRow < 0, !self.entries.isEmpty {
                    self.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                    self.lastSelectedRow = 0
                }
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
        selectedPath = target.relativePath

        guard let idx = allEntries.firstIndex(where: { $0.relativePath == target.relativePath && $0.isDirectory }) else { return }
        allEntries[idx].isExpanded.toggle()
        rebuildVisibleEntries()
        tableView.reloadData()
        restoreSelection()
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

    private func restoreSelection() {
        guard let selectedPath else { return }
        guard let row = entries.firstIndex(where: { $0.relativePath == selectedPath }) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    // MARK: - Actions

    @objc private func goBack() {
        (view.window?.windowController as? WindowController)?.pop()
    }

    @objc private func showHelpDialog() {
        let text = """
キーボードショートカット

共通
• Esc: 戻る
• Cmd+R: 再読み込み
• Cmd+W: ウィンドウを閉じる
• Cmd+Q: 終了

ディレクトリビュー
• ↑/↓: 選択移動
• ←/→: ディレクトリ折りたたみ/展開
• Enter: ファイルをプレビュー（ディレクトリは開閉）

差分ビュー
• Cmd+←: 前の差分へ
• Cmd+→: 次の差分へ
• 下部差分パネルでテキスト選択中に Cmd+C: コピー

設定メニュー（上部メニュー > 設定）
• 最初/最後到達メッセージを表示（ON/OFF）
• 差分移動で次/前ファイルへまたぐ（ON/OFF）
"""
        let alert = NSAlert()
        alert.messageText = "ヘルプ"
        alert.informativeText = text
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func moveSelection(delta: Int) {
        guard !entries.isEmpty else { return }
        let current = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        let next = min(max(current + delta, 0), entries.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    private func ensureSelection() {
        guard !entries.isEmpty else { return }
        guard tableView.selectedRow < 0 else { return }
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
    }

    private func expandSelectedDirectory() {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count else { return }
        let entry = entries[row]
        guard entry.isDirectory else { return }
        guard let idx = allEntries.firstIndex(where: { $0.relativePath == entry.relativePath && $0.isDirectory }) else { return }
        guard !allEntries[idx].isExpanded else { return }
        allEntries[idx].isExpanded = true
        rebuildVisibleEntries()
        tableView.reloadData()
        restoreSelection()
    }

    private func collapseSelectedDirectoryOrParent() {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count else { return }
        let entry = entries[row]

        if entry.isDirectory,
           let idx = allEntries.firstIndex(where: { $0.relativePath == entry.relativePath && $0.isDirectory }),
           allEntries[idx].isExpanded {
            allEntries[idx].isExpanded = false
            rebuildVisibleEntries()
            tableView.reloadData()
            restoreSelection()
            return
        }

        guard entry.depth > 0 else { return }
        for i in stride(from: row - 1, through: 0, by: -1) {
            let candidate = entries[i]
            if candidate.isDirectory && candidate.depth == entry.depth - 1 {
                selectedPath = candidate.relativePath
                restoreSelection()
                break
            }
        }
    }

    private func openSelectedDiffIfPossible(row: Int? = nil) {
        let row = row ?? tableView.selectedRow
        guard row >= 0, row < entries.count else { return }
        let entry = entries[row]
        selectedPath = entry.relativePath

        if entry.isDirectory {
            if entry.isExpanded {
                collapseSelectedDirectoryOrParent()
            } else {
                expandSelectedDirectory()
            }
            return
        }

        switch entry.status {
        case .changed:
            guard let l = entry.leftURL, let r = entry.rightURL else { return }
            showDiffPreview(left: l, right: r)

        case .binaryDiff:
            let alert = NSAlert()
            alert.messageText = "バイナリファイル"
            alert.informativeText = "バイナリファイルのため差分表示はできません。"
            alert.runModal()

        default:
            break
        }
    }

    private func neighborDiffPair(forward: Bool) -> (URL, URL)? {
        let changed = allEntries.filter {
            !$0.isDirectory && $0.status == .changed && $0.leftURL != nil && $0.rightURL != nil
        }
        guard !changed.isEmpty else { return nil }
        guard let currentPath = selectedPath else { return nil }
        guard let current = changed.firstIndex(where: { $0.relativePath == currentPath }) else { return nil }
        let nextIndex = forward ? current + 1 : current - 1
        guard nextIndex >= 0, nextIndex < changed.count else { return nil }
        let next = changed[nextIndex]
        selectedPath = next.relativePath
        restoreSelection()
        return (next.leftURL!, next.rightURL!)
    }

    private func showDiffPreview(left: URL, right: URL) {
        previewPlaceholder.isHidden = true
        previewDiffVC?.view.removeFromSuperview()
        previewDiffVC?.removeFromParent()

        let diffVC = DiffViewController(left: left, right: right, backAction: { [weak self] in
            self?.restoreSelection()
            if let table = self?.tableView {
                self?.view.window?.makeFirstResponder(table)
            }
        }, crossFileDiffProvider: { [weak self] forward in
            self?.neighborDiffPair(forward: forward)
        })
        addChild(diffVC)
        diffVC.view.translatesAutoresizingMaskIntoConstraints = false
        previewPane.addSubview(diffVC.view)
        NSLayoutConstraint.activate([
            diffVC.view.topAnchor.constraint(equalTo: previewPane.topAnchor),
            diffVC.view.leadingAnchor.constraint(equalTo: previewPane.leadingAnchor),
            diffVC.view.trailingAnchor.constraint(equalTo: previewPane.trailingAnchor),
            diffVC.view.bottomAnchor.constraint(equalTo: previewPane.bottomAnchor),
        ])
        previewDiffVC = diffVC
    }

    @objc private func handleTableClick() {
        let clicked = tableView.clickedRow
        guard clicked >= 0, clicked < entries.count else { return }
        if clicked == tableView.selectedRow, clicked == lastSelectedRow {
            if entries[clicked].isDirectory {
                toggleDirectory(atVisibleIndex: clicked)
                return
            }
            openSelectedDiffIfPossible(row: clicked)
        }
    }

    private func installShortcutMonitorIfNeeded() {
        guard shortcutMonitor == nil else { return }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if flags.contains(.command),
               let key = event.charactersIgnoringModifiers?.lowercased() {
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

            let nonCommandFlags = flags.subtracting([.numericPad, .function])
            guard nonCommandFlags.isEmpty else { return event }
            self.ensureSelection()
            switch event.keyCode {
            case 126: // Up
                self.moveSelection(delta: -1)
                return nil
            case 125: // Down
                self.moveSelection(delta: 1)
                return nil
            case 124: // Right
                self.expandSelectedDirectory()
                return nil
            case 123: // Left
                self.collapseSelectedDirectoryOrParent()
                return nil
            case 36, 76: // Return / Enter
                self.openSelectedDiffIfPossible()
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
        lastSelectedRow = row
        selectedPath = entry.relativePath
    }
}
