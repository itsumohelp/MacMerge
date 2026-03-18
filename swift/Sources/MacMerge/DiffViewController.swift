import AppKit

// MARK: - DiffRowView

final class DiffRowView: NSTableRowView {
    var style: CellStyle = .equal
    override var isEmphasized: Bool { get { false } set {} }
    override func draw(_ dirtyRect: NSRect) { style.bgColor.setFill(); dirtyRect.fill() }
    override func drawSelection(in dirtyRect: NSRect) {}
}

// MARK: - LineNumberView
// Draws line numbers directly — no NSScrollView frame management issues.

final class LineNumberView: NSView {
    var rows: [DiffRow] = []
    var isLeft: Bool = true
    var rowH: CGFloat = 20
    var contentTopInset: CGFloat = 0
    private let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    // Scroll offset synced from code table
    var scrollY: CGFloat = 0 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let adjustedY = max(0, scrollY - contentTopInset)
        let first = max(0, Int(adjustedY / rowH))
        let last  = min(rows.count, Int((adjustedY + bounds.height) / rowH) + 2)

        for i in first..<last {
            let dr  = rows[i]
            let y   = contentTopInset + CGFloat(i) * rowH - scrollY
            let rect = NSRect(x: 0, y: y, width: bounds.width, height: rowH)

            // Background (matches code table row color)
            let style = isLeft ? dr.leftStyle : dr.rightStyle
            style.bgColor.setFill()
            rect.fill()

            // Line number text, right-aligned with 4px right margin
            if let n = isLeft ? dr.leftNum : dr.rightNum {
                let s   = "\(n)" as NSString
                let sw  = s.size(withAttributes: attrs).width
                let sh  = s.size(withAttributes: attrs).height
                s.draw(at: NSPoint(x: bounds.width - sw - 4,
                                   y: y + (rowH - sh) / 2),
                       withAttributes: attrs)
            }
        }
    }
}

// MARK: - CharDiffView

final class CharDiffView: NSView {
    private let leftLabel   = NSTextField(labelWithString: "")
    private let rightLabel  = NSTextField(labelWithString: "")
    private let leftScroll  = NSScrollView()
    private let rightScroll = NSScrollView()
    private let leftTV      = NSTextView()
    private let rightTV     = NSTextView()
    private let topSep      = NSView()
    private let midSep      = NSView()
    private var isSyncing   = false

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.09, green: 0.09, blue: 0.12, alpha: 1).cgColor

        for sep in [topSep, midSep] {
            sep.wantsLayer = true
            sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
        for (tv, scroll) in [(leftTV, leftScroll), (rightTV, rightScroll)] {
            configureTV(tv)
            scroll.documentView          = tv
            scroll.hasHorizontalScroller = true
            scroll.hasVerticalScroller   = false
            scroll.autohidesScrollers    = true
            scroll.borderType            = .noBorder
            scroll.backgroundColor       = .clear
            scroll.drawsBackground       = false
            scroll.contentView.postsBoundsChangedNotifications = true
        }
        for lbl in [leftLabel, rightLabel] {
            lbl.font = .systemFont(ofSize: 10, weight: .semibold)
            lbl.textColor = .secondaryLabelColor
        }
        for v in [topSep, leftLabel, leftScroll, midSep, rightLabel, rightScroll] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        let lineH: CGFloat = 26
        NSLayoutConstraint.activate([
            topSep.topAnchor.constraint(equalTo: topAnchor),
            topSep.leadingAnchor.constraint(equalTo: leadingAnchor),
            topSep.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSep.heightAnchor.constraint(equalToConstant: 1),

            leftLabel.topAnchor.constraint(equalTo: topSep.bottomAnchor, constant: 2),
            leftLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),

            leftScroll.topAnchor.constraint(equalTo: topSep.bottomAnchor),
            leftScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            leftScroll.heightAnchor.constraint(equalToConstant: lineH),

            midSep.topAnchor.constraint(equalTo: leftScroll.bottomAnchor),
            midSep.leadingAnchor.constraint(equalTo: leadingAnchor),
            midSep.trailingAnchor.constraint(equalTo: trailingAnchor),
            midSep.heightAnchor.constraint(equalToConstant: 1),

            rightLabel.topAnchor.constraint(equalTo: midSep.bottomAnchor, constant: 2),
            rightLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),

            rightScroll.topAnchor.constraint(equalTo: midSep.bottomAnchor),
            rightScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            rightScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightScroll.heightAnchor.constraint(equalToConstant: lineH),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(syncH(_:)),
            name: NSView.boundsDidChangeNotification, object: leftScroll.contentView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(syncH(_:)),
            name: NSView.boundsDidChangeNotification, object: rightScroll.contentView)
    }

    @objc private func syncH(_ note: Notification) {
        guard !isSyncing, let src = note.object as? NSClipView else { return }
        isSyncing = true
        let x = src.bounds.origin.x
        let other = (src === leftScroll.contentView) ? rightScroll : leftScroll
        var o = other.contentView.bounds.origin; o.x = x
        other.contentView.scroll(to: o); other.reflectScrolledClipView(other.contentView)
        isSyncing = false
    }

    private func configureTV(_ tv: NSTextView) {
        tv.isEditable              = false
        tv.isSelectable            = true
        tv.font                    = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.backgroundColor         = .clear
        tv.drawsBackground         = false
        tv.textContainerInset      = NSSize(width: 6, height: 4)
        tv.isHorizontallyResizable = true
        tv.maxSize                 = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                            height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize       = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                        height: CGFloat.greatestFiniteMagnitude)
    }

    func update(row: DiffRow) {
        leftLabel.stringValue  = row.leftNum .map { "← 行 \($0)" } ?? "←"
        rightLabel.stringValue = row.rightNum.map { "→ 行 \($0)" } ?? "→"
        let (lR, rR) = charDiff(old: row.leftText, new: row.rightText)
        leftTV.textStorage?.setAttributedString(
            makeAttr(row.leftText,  lR, NSColor(red: 0.65, green: 0.18, blue: 0.22, alpha: 0.6)))
        rightTV.textStorage?.setAttributedString(
            makeAttr(row.rightText, rR, NSColor(red: 0.15, green: 0.55, blue: 0.25, alpha: 0.6)))
    }

    private func makeAttr(_ text: String, _ ranges: [NSRange], _ bg: NSColor) -> NSAttributedString {
        let a = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ])
        for r in ranges { a.addAttribute(.backgroundColor, value: bg, range: r) }
        return a
    }

    private func charDiff(old: String, new: String) -> ([NSRange], [NSRange]) {
        var removed = Set<Int>(), inserted = Set<Int>()
        for c in Array(new).difference(from: Array(old)) {
            switch c { case .remove(let i,_,_): removed.insert(i)
                       case .insert(let j,_,_): inserted.insert(j) }
        }
        return (toRanges(removed, old), toRanges(inserted, new))
    }

    private func toRanges(_ idx: Set<Int>, _ s: String) -> [NSRange] {
        guard !idx.isEmpty else { return [] }
        let chars = Array(s); let sorted = idx.sorted()
        var out: [NSRange] = []; var start = sorted[0], prev = sorted[0]
        for i in sorted.dropFirst() {
            if i == prev + 1 { prev = i }
            else { out.append(nr(chars, start, prev, s)); start = i; prev = i }
        }
        out.append(nr(chars, start, prev, s)); return out
    }

    private func nr(_ chars: [Character], _ from: Int, _ to: Int, _ s: String) -> NSRange {
        let si = s.index(s.startIndex, offsetBy: min(from,   chars.count), limitedBy: s.endIndex) ?? s.endIndex
        let ei = s.index(s.startIndex, offsetBy: min(to + 1, chars.count), limitedBy: s.endIndex) ?? s.endIndex
        return NSRange(si..<ei, in: s)
    }
}

// MARK: - DiffViewController

final class DiffViewController: NSViewController {

    var leftURL:  URL?
    var rightURL: URL?
    private var leftInputText: String?
    private var rightInputText: String?
    private var leftTitleText: String = ""
    private var rightTitleText: String = ""

    private var rows: [DiffRow] = []
    private var isSyncing = false

    // Line number views (draw-based, no scroll view complexity)
    private var leftNumView:  LineNumberView!
    private var rightNumView: LineNumberView!
    private var leftNumW:     NSLayoutConstraint!
    private var rightNumW:    NSLayoutConstraint!
    private var currentNumWidth: CGFloat = 36

    // Code scroll views + tables
    private var leftCodeScroll:  NSScrollView!
    private var leftCodeTable:   NSTableView!
    private var rightCodeScroll: NSScrollView!
    private var rightCodeTable:  NSTableView!

    private var charDiffView:   CharDiffView!
    private var charDiffHeight: NSLayoutConstraint!
    private let detailHeight: CGFloat = 56

    private let leftLabel  = NSTextField(labelWithString: "")
    private let rightLabel = NSTextField(labelWithString: "")
    private let infoBar = NSView()
    private let leftInfoLabel = NSTextField(labelWithString: "")
    private let rightInfoLabel = NSTextField(labelWithString: "")

    // MARK: - Init

    convenience init(left: URL, right: URL) {
        self.init(nibName: nil, bundle: nil)
        leftURL = left; rightURL = right
        leftTitleText = left.path
        rightTitleText = right.path
    }

    convenience init(leftText: String, rightText: String) {
        self.init(nibName: nil, bundle: nil)
        leftInputText = leftText
        rightInputText = rightText
        leftTitleText = "入力（左）"
        rightTitleText = "入力（右）"
    }

    // MARK: - Lifecycle

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
        if let l = leftURL, let r = rightURL {
            loadDiff(left: l, right: r)
        } else if let lText = leftInputText, let rText = rightInputText {
            loadDiff(leftText: lText, rightText: rText)
        }
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
        for lbl in [leftLabel, rightLabel] {
            lbl.font = .systemFont(ofSize: 11, weight: .medium)
            lbl.textColor = .secondaryLabelColor
            lbl.lineBreakMode = .byTruncatingMiddle
            lbl.translatesAutoresizingMaskIntoConstraints = false
        }
        header.addSubview(backBtn); header.addSubview(leftLabel); header.addSubview(rightLabel)
        view.addSubview(header)

        // ── Center line number gutters (draw-based) ──────────────
        leftNumView  = LineNumberView(); leftNumView.isLeft  = true
        rightNumView = LineNumberView(); rightNumView.isLeft = false
        for v in [leftNumView!, rightNumView!] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }

        // ── Code scroll views + tables ───────────────────────────
        leftCodeScroll  = makeCodeScroll(); leftCodeTable  = makeCodeTable(id: "lc")
        rightCodeScroll = makeCodeScroll(); rightCodeTable = makeCodeTable(id: "rc")
        leftCodeScroll.documentView  = leftCodeTable
        rightCodeScroll.documentView = rightCodeTable
        for v in [leftCodeScroll!, rightCodeScroll!] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }

        // ── Divider ──────────────────────────────────────────────
        let div = NSView()
        div.wantsLayer = true
        div.layer?.backgroundColor = NSColor.separatorColor.cgColor
        div.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(div)

        // ── Encoding / Line-ending info bar ──────────────────────
        infoBar.wantsLayer = true
        infoBar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        infoBar.translatesAutoresizingMaskIntoConstraints = false
        let infoSep = NSView()
        infoSep.wantsLayer = true
        infoSep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        infoSep.translatesAutoresizingMaskIntoConstraints = false
        let infoMid = NSView()
        infoMid.wantsLayer = true
        infoMid.layer?.backgroundColor = NSColor.separatorColor.cgColor
        infoMid.translatesAutoresizingMaskIntoConstraints = false
        for lbl in [leftInfoLabel, rightInfoLabel] {
            lbl.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            lbl.textColor = .secondaryLabelColor
            lbl.lineBreakMode = .byClipping
            lbl.translatesAutoresizingMaskIntoConstraints = false
        }
        infoBar.addSubview(infoSep)
        infoBar.addSubview(infoMid)
        infoBar.addSubview(leftInfoLabel)
        infoBar.addSubview(rightInfoLabel)
        view.addSubview(infoBar)

        // ── Char diff panel ──────────────────────────────────────
        charDiffView = CharDiffView()
        charDiffView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(charDiffView)
        charDiffHeight = charDiffView.heightAnchor.constraint(equalToConstant: 0)

        // ── Constraints ──────────────────────────────────────────
        leftNumW  = leftNumView.widthAnchor.constraint(equalToConstant: currentNumWidth)
        rightNumW = rightNumView.widthAnchor.constraint(equalToConstant: currentNumWidth)

        NSLayoutConstraint.activate([
            // Header
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 40),
            backBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backBtn.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            leftLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            leftLabel.leadingAnchor.constraint(equalTo: backBtn.trailingAnchor, constant: 16),
            leftLabel.trailingAnchor.constraint(lessThanOrEqualTo: header.centerXAnchor, constant: -8),
            rightLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            rightLabel.leadingAnchor.constraint(equalTo: header.centerXAnchor, constant: 8),
            rightLabel.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -12),

            // Divider
            div.topAnchor.constraint(equalTo: header.bottomAnchor),
            div.bottomAnchor.constraint(equalTo: infoBar.topAnchor),
            div.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            div.widthAnchor.constraint(equalToConstant: 1),

            // Left edge gutter (line numbers)
            leftNumW,
            leftNumView.topAnchor.constraint(equalTo: header.bottomAnchor),
            leftNumView.bottomAnchor.constraint(equalTo: infoBar.topAnchor),
            leftNumView.leadingAnchor.constraint(equalTo: view.leadingAnchor),

            // Left code scroll
            leftCodeScroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            leftCodeScroll.bottomAnchor.constraint(equalTo: infoBar.topAnchor),
            leftCodeScroll.leadingAnchor.constraint(equalTo: leftNumView.trailingAnchor),
            leftCodeScroll.trailingAnchor.constraint(equalTo: div.leadingAnchor),

            // Right center gutter (line numbers)
            rightNumW,
            rightNumView.topAnchor.constraint(equalTo: header.bottomAnchor),
            rightNumView.bottomAnchor.constraint(equalTo: infoBar.topAnchor),
            rightNumView.leadingAnchor.constraint(equalTo: div.trailingAnchor),

            // Right code scroll
            rightCodeScroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            rightCodeScroll.bottomAnchor.constraint(equalTo: infoBar.topAnchor),
            rightCodeScroll.leadingAnchor.constraint(equalTo: rightNumView.trailingAnchor),
            rightCodeScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Info bar (always above detail panel)
            infoBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            infoBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            infoBar.bottomAnchor.constraint(equalTo: charDiffView.topAnchor),
            infoBar.heightAnchor.constraint(equalToConstant: 24),
            infoSep.topAnchor.constraint(equalTo: infoBar.topAnchor),
            infoSep.leadingAnchor.constraint(equalTo: infoBar.leadingAnchor),
            infoSep.trailingAnchor.constraint(equalTo: infoBar.trailingAnchor),
            infoSep.heightAnchor.constraint(equalToConstant: 1),
            infoMid.topAnchor.constraint(equalTo: infoBar.topAnchor),
            infoMid.bottomAnchor.constraint(equalTo: infoBar.bottomAnchor),
            infoMid.centerXAnchor.constraint(equalTo: infoBar.centerXAnchor),
            infoMid.widthAnchor.constraint(equalToConstant: 1),
            leftInfoLabel.leadingAnchor.constraint(equalTo: infoBar.leadingAnchor, constant: 10),
            leftInfoLabel.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),
            leftInfoLabel.trailingAnchor.constraint(lessThanOrEqualTo: infoMid.leadingAnchor, constant: -8),
            rightInfoLabel.leadingAnchor.constraint(equalTo: infoMid.trailingAnchor, constant: 10),
            rightInfoLabel.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),
            rightInfoLabel.trailingAnchor.constraint(lessThanOrEqualTo: infoBar.trailingAnchor, constant: -10),

            // Char diff
            charDiffHeight,
            charDiffView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            charDiffView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            charDiffView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // ── Scroll sync ──────────────────────────────────────────
        for sv in [leftCodeScroll, rightCodeScroll] as [NSScrollView] {
            sv.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(syncScroll(_:)),
                name: NSView.boundsDidChangeNotification, object: sv.contentView)
        }
    }

    // MARK: - Factory

    private func makeCodeScroll() -> NSScrollView {
        let sv = NSScrollView()
        sv.hasVerticalScroller   = true
        sv.hasHorizontalScroller = true
        sv.autohidesScrollers    = true
        sv.borderType            = .noBorder
        sv.backgroundColor       = CellStyle.equal.bgColor
        return sv
    }

    private func makeCodeTable(id: String) -> NSTableView {
        let tv = NSTableView()
        tv.headerView              = nil
        tv.rowHeight               = 20
        tv.intercellSpacing        = .zero
        tv.selectionHighlightStyle = .regular
        tv.backgroundColor         = .clear
        tv.columnAutoresizingStyle = .noColumnAutoresizing
        let col = NSTableColumn(identifier: .init(id))
        col.width = 2000; col.minWidth = 200; col.maxWidth = 1_000_000
        tv.addTableColumn(col)
        tv.dataSource = self; tv.delegate = self
        return tv
    }

    // MARK: - Load data

    private func loadDiff(left: URL, right: URL) {
        leftLabel.stringValue  = leftTitleText
        rightLabel.stringValue = rightTitleText
        DispatchQueue.global(qos: .userInitiated).async {
            let lText  = (try? String(contentsOf: left,  encoding: .utf8)) ?? ""
            let rText  = (try? String(contentsOf: right, encoding: .utf8)) ?? ""
            let result = DiffEngine.compute(left: lText, right: rText)
            DispatchQueue.main.async {
                self.updateInfoBar(leftText: lText, rightText: rText)
                self.applyRows(result)
            }
        }
    }

    private func loadDiff(leftText: String, rightText: String) {
        leftLabel.stringValue  = leftTitleText
        rightLabel.stringValue = rightTitleText
        let result = DiffEngine.compute(left: leftText, right: rightText)
        updateInfoBar(leftText: leftText, rightText: rightText)
        applyRows(result)
    }

    private func applyRows(_ result: [DiffRow]) {
        self.rows = result
        self.leftNumView.rows  = result
        self.rightNumView.rows = result
        self.leftNumView.needsDisplay  = true
        self.rightNumView.needsDisplay = true
        self.leftCodeTable.reloadData()
        self.rightCodeTable.reloadData()
        self.updateNumWidth()
        self.updateCodeColumnWidth()
        self.syncLineNumberMetrics()
    }

    private func updateCodeColumnWidth() {
        let maxChars = rows.reduce(0) { m, r in max(m, r.leftText.count, r.rightText.count) }
        let charWidth: CGFloat = 7.4
        let colW = max(CGFloat(maxChars) * charWidth + 40, 800)
        leftCodeTable.tableColumns.first?.width  = colW
        rightCodeTable.tableColumns.first?.width = colW
    }

    private func updateNumWidth() {
        let maxLine = max(rows.compactMap { $0.leftNum  }.max() ?? 0,
                         rows.compactMap { $0.rightNum }.max() ?? 0)
        let digits  = max(String(maxLine).count, 1)
        let sample  = String(repeating: "9", count: digits) as NSString
        let w = ceil(sample.size(withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ]).width) + 13
        currentNumWidth    = w
        leftNumW.constant  = w
        rightNumW.constant = w
    }

    private func syncLineNumberMetrics() {
        // Keep gutters aligned to the table's actual row geometry.
        let rowHeight = leftCodeTable.rowHeight + leftCodeTable.intercellSpacing.height
        leftNumView.rowH = rowHeight
        rightNumView.rowH = rowHeight

        let topInsetL = leftCodeTable.numberOfRows > 0 ? leftCodeTable.rect(ofRow: 0).minY : 0
        let topInsetR = rightCodeTable.numberOfRows > 0 ? rightCodeTable.rect(ofRow: 0).minY : 0
        leftNumView.contentTopInset = topInsetL
        rightNumView.contentTopInset = topInsetR
        leftNumView.needsDisplay = true
        rightNumView.needsDisplay = true
    }

    private func updateInfoBar(leftText: String, rightText: String) {
        leftInfoLabel.stringValue = "左  \(detectEncoding(leftText))   \(detectLineEnding(leftText))"
        rightInfoLabel.stringValue = "右  \(detectEncoding(rightText))   \(detectLineEnding(rightText))"
    }

    private func detectEncoding(_ content: String) -> String {
        if let first = content.unicodeScalars.first, first.value == 0xFEFF { return "UTF-8 BOM" }
        return "UTF-8"
    }

    private func detectLineEnding(_ content: String) -> String {
        let hasCRLF = content.contains("\r\n")
        let stripped = content.replacingOccurrences(of: "\r\n", with: "")
        let hasCR = stripped.contains("\r")
        let hasLF = stripped.contains("\n")
        let count = (hasCRLF ? 1 : 0) + (hasCR ? 1 : 0) + (hasLF ? 1 : 0)
        if count == 0 { return "None" }
        if count > 1 { return "Mixed" }
        if hasCRLF { return "CRLF" }
        if hasCR { return "CR" }
        return "LF"
    }

    // MARK: - Actions

    @objc private func goBack() {
        (view.window?.windowController as? WindowController)?.pop()
    }

    @objc private func syncScroll(_ note: Notification) {
        guard !isSyncing, let src = note.object as? NSClipView else { return }
        isSyncing = true
        let origin = src.bounds.origin

        // Sync both code scrolls (X + Y)
        let otherCode = (src === leftCodeScroll.contentView) ? rightCodeScroll : leftCodeScroll
        var o = otherCode!.contentView.bounds.origin
        o.x = origin.x; o.y = origin.y
        otherCode!.contentView.scroll(to: o)
        otherCode!.reflectScrolledClipView(otherCode!.contentView)

        // Sync line number views (Y only)
        let y = origin.y
        leftNumView.scrollY  = y
        rightNumView.scrollY = y

        isSyncing = false
    }
}

// MARK: - NSTableViewDataSource / Delegate

extension DiffViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView,
                   viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let dr     = rows[row]
        let isLeft = tableView === leftCodeTable

        let field = NSTextField(labelWithString: "")
        field.isBordered      = false
        field.isEditable      = false
        field.drawsBackground = false
        field.stringValue     = isLeft ? dr.leftText : dr.rightText
        field.font            = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.textColor       = .labelColor
        field.lineBreakMode   = .byClipping
        field.cell?.wraps     = false
        return field
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rv     = DiffRowView()
        let dr     = rows[row]
        let isLeft = tableView === leftCodeTable
        rv.style   = isLeft ? dr.leftStyle : dr.rightStyle
        return rv
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 20 }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTableView else { return }
        let row = tv.selectedRow
        guard row >= 0, row < rows.count else { hideDetail(); return }

        let dr    = rows[row]
        let other = (tv === leftCodeTable) ? rightCodeTable : leftCodeTable
        if other?.selectedRow != row {
            other?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        if dr.leftStyle == .equal && dr.rightStyle == .equal { hideDetail() }
        else { showDetail(for: dr) }
    }

    private func showDetail(for row: DiffRow) {
        charDiffView.update(row: row)
        guard charDiffHeight.constant == 0 else { return }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12
            charDiffHeight.animator().constant = detailHeight }
    }

    private func hideDetail() {
        guard charDiffHeight.constant > 0 else { return }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12
            charDiffHeight.animator().constant = 0 }
    }
}
