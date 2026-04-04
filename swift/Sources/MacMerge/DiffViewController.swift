import AppKit

// MARK: - DiffRowView

final class DiffRowView: NSTableRowView {
    var style: CellStyle = .equal
    override var isEmphasized: Bool { get { false } set {} }
    override func draw(_ dirtyRect: NSRect) {
        style.bgColor.setFill()
        dirtyRect.fill()
        guard isSelected else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.28).setFill()
        dirtyRect.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.95).setStroke()
        let path = NSBezierPath(rect: dirtyRect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }
    override func drawSelection(in dirtyRect: NSRect) {
        // selection is rendered in draw(_:) for consistent visibility
    }
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

// MARK: - DiffMiniMapOverlayView

final class DiffMiniMapOverlayView: NSView {
    var rows: [DiffRow] = [] { didSet { needsDisplay = true } }
    var visibleRows: ClosedRange<Int>? { didSet { needsDisplay = true } }
    var onSelectRow: ((Int) -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard !rows.isEmpty else { return }

        let unit = max(bounds.height / CGFloat(rows.count), 1)
        for (idx, row) in rows.enumerated() {
            let changed = !(row.leftStyle == .equal && row.rightStyle == .equal)
            guard changed else { continue }
            markerColor(for: row).setFill()
            let y = CGFloat(idx) * unit
            NSRect(x: 2, y: y, width: max(1, bounds.width - 4), height: max(2, unit)).fill()
        }

        if let vr = visibleRows {
            let y = CGFloat(vr.lowerBound) * unit
            let h = max(6, CGFloat(vr.count) * unit)
            let rect = NSRect(x: 0.5, y: y, width: bounds.width - 1, height: min(h, bounds.height - y))
            NSColor.controlAccentColor.setStroke()
            let p = NSBezierPath(rect: rect)
            p.lineWidth = 1
            p.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) { selectRow(from: event) }
    override func mouseDragged(with event: NSEvent) { selectRow(from: event) }

    private func selectRow(from event: NSEvent) {
        guard !rows.isEmpty else { return }
        let p = convert(event.locationInWindow, from: nil)
        let ratio = min(max(p.y / max(bounds.height, 1), 0), 1)
        let row = min(rows.count - 1, Int(ratio * CGFloat(rows.count)))
        onSelectRow?(row)
    }

    private func markerColor(for row: DiffRow) -> NSColor {
        if row.leftStyle == .removed || row.rightStyle == .removed {
            return NSColor(red: 0.85, green: 0.35, blue: 0.40, alpha: 1)
        }
        if row.leftStyle == .added || row.rightStyle == .added {
            return NSColor(red: 0.30, green: 0.72, blue: 0.40, alpha: 1)
        }
        return NSColor(red: 0.85, green: 0.68, blue: 0.22, alpha: 1)
    }
}

// MARK: - CharDiffView

final class CharDiffView: NSView {
    private let leftLabel   = NSTextField(labelWithString: "")
    private let rightLabel  = NSTextField(labelWithString: "")
    private let closeButton = NSButton(title: "✕", target: nil, action: nil)
    private let leftScroll  = NSScrollView()
    private let rightScroll = NSScrollView()
    private let leftTV      = NSTextView()
    private let rightTV     = NSTextView()
    private let topSep      = NSView()
    private let midSep      = NSView()
    private var isSyncing   = false
    private var leftScrollH: NSLayoutConstraint!
    private var rightScrollH: NSLayoutConstraint!
    var onClose: (() -> Void)?

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.98, alpha: 1).cgColor

        for sep in [topSep, midSep] {
            sep.wantsLayer = true
            sep.layer?.backgroundColor = NSColor(calibratedWhite: 0.85, alpha: 1).cgColor
        }
        for (tv, scroll) in [(leftTV, leftScroll), (rightTV, rightScroll)] {
            configureTV(tv)
            scroll.documentView          = tv
            scroll.hasHorizontalScroller = true
            scroll.hasVerticalScroller   = true
            scroll.autohidesScrollers    = true
            scroll.borderType            = .noBorder
            scroll.backgroundColor       = .white
            scroll.drawsBackground       = true
            scroll.contentView.postsBoundsChangedNotifications = true
        }
        for lbl in [leftLabel, rightLabel] {
            lbl.font = .systemFont(ofSize: 10, weight: .semibold)
            lbl.textColor = NSColor(calibratedWhite: 0.35, alpha: 1)
        }
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.bezelStyle = .texturedRounded
        closeButton.controlSize = .small
        closeButton.font = .systemFont(ofSize: 10, weight: .regular)

        for v in [topSep, leftLabel, leftScroll, midSep, rightLabel, rightScroll] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton, positioned: .above, relativeTo: leftScroll)
        let lineH: CGFloat = 26
        leftScrollH = leftScroll.heightAnchor.constraint(equalToConstant: lineH)
        rightScrollH = rightScroll.heightAnchor.constraint(equalToConstant: lineH)
        NSLayoutConstraint.activate([
            topSep.topAnchor.constraint(equalTo: topAnchor),
            topSep.leadingAnchor.constraint(equalTo: leadingAnchor),
            topSep.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSep.heightAnchor.constraint(equalToConstant: 1),

            leftLabel.topAnchor.constraint(equalTo: topSep.bottomAnchor, constant: 2),
            leftLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            closeButton.centerYAnchor.constraint(equalTo: leftLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),

            leftScroll.topAnchor.constraint(equalTo: topSep.bottomAnchor),
            leftScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            leftScrollH,

            midSep.topAnchor.constraint(equalTo: leftScroll.bottomAnchor),
            midSep.leadingAnchor.constraint(equalTo: leadingAnchor),
            midSep.trailingAnchor.constraint(equalTo: trailingAnchor),
            midSep.heightAnchor.constraint(equalToConstant: 1),

            rightLabel.topAnchor.constraint(equalTo: midSep.bottomAnchor, constant: 2),
            rightLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),

            rightScroll.topAnchor.constraint(equalTo: midSep.bottomAnchor),
            rightScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            rightScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightScrollH,
            rightScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(syncH(_:)),
            name: NSView.boundsDidChangeNotification, object: leftScroll.contentView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(syncH(_:)),
            name: NSView.boundsDidChangeNotification, object: rightScroll.contentView)
    }

    @objc private func closeTapped() {
        onClose?()
    }

    func copySelectionIfPossible() -> Bool {
        guard let responder = window?.firstResponder as? NSTextView else { return false }
        guard responder === leftTV || responder === rightTV else { return false }
        guard responder.selectedRange.length > 0 else { return false }
        responder.copy(nil)
        return true
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
        tv.textColor               = NSColor(calibratedWhite: 0.1, alpha: 1)
        tv.backgroundColor         = .white
        tv.drawsBackground         = true
        tv.textContainerInset      = NSSize(width: 6, height: 4)
        tv.isHorizontallyResizable = true
        tv.maxSize                 = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                            height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize       = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                        height: CGFloat.greatestFiniteMagnitude)
    }

    func update(rows: [DiffRow]) {
        guard !rows.isEmpty else {
            leftLabel.stringValue = "←"
            rightLabel.stringValue = "→"
            leftTV.string = ""
            rightTV.string = ""
            leftScrollH.constant = 26
            rightScrollH.constant = 26
            return
        }

        leftLabel.stringValue = "← 行 \(lineRangeText(for: rows.compactMap(\.leftNum)))"
        rightLabel.stringValue = "→ 行 \(lineRangeText(for: rows.compactMap(\.rightNum)))"

        let leftText = rows.map(\.leftText).joined(separator: "\n")
        let rightText = rows.map(\.rightText).joined(separator: "\n")
        let (lR, rR) = charDiff(old: leftText, new: rightText)
        leftTV.textStorage?.setAttributedString(
            makeAttr(leftText,  lR, NSColor(red: 0.95, green: 0.78, blue: 0.80, alpha: 1)))
        rightTV.textStorage?.setAttributedString(
            makeAttr(rightText, rR, NSColor(red: 0.80, green: 0.93, blue: 0.84, alpha: 1)))

        let lines = max(rows.count, 1)
        let h = CGFloat(min(max(lines, 1), 6)) * 20 + 8
        leftScrollH.constant = h
        rightScrollH.constant = h
    }

    private func lineRangeText(for nums: [Int]) -> String {
        guard let first = nums.first, let last = nums.last else { return "-" }
        return first == last ? "\(first)" : "\(first)-\(last)"
    }

    private func makeAttr(_ text: String, _ ranges: [NSRange], _ bg: NSColor) -> NSAttributedString {
        let a = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.1, alpha: 1),
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

    private let leftLabel  = NSTextField(labelWithString: "")
    private let rightLabel = NSTextField(labelWithString: "")
    private let reloadButton = NSButton(title: "⟳ 再読み込み", target: nil, action: nil)
    private let leftCopyNameButton = NSButton(title: "📄", target: nil, action: nil)
    private let leftCopyPathButton = NSButton(title: "📋", target: nil, action: nil)
    private let rightCopyNameButton = NSButton(title: "📄", target: nil, action: nil)
    private let rightCopyPathButton = NSButton(title: "📋", target: nil, action: nil)
    private let helpButton = NSButton(title: "？", target: nil, action: nil)
    private let prevDiffButton = NSButton(title: "◀ 差分", target: nil, action: nil)
    private let nextDiffButton = NSButton(title: "差分 ▶", target: nil, action: nil)
    private var diffBlocks: [ClosedRange<Int>] = []
    private var currentDiffBlockIndex: Int = -1
    private var backAction: (() -> Void)?
    private var crossFileDiffProvider: ((Bool) -> (URL, URL)?)?
    private var pendingBoundarySelectionForward: Bool?
    private let infoBar = NSView()
    private let leftInfoLabel = NSTextField(labelWithString: "")
    private let rightInfoLabel = NSTextField(labelWithString: "")
    private let miniMapOverlay = DiffMiniMapOverlayView()
    private let diffProgressLabel = NSTextField(labelWithString: "0/0")
    private var shortcutMonitor: Any?

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

    convenience init(left: URL, right: URL, backAction: (() -> Void)?) {
        self.init(left: left, right: right)
        self.backAction = backAction
    }

    convenience init(
        left: URL,
        right: URL,
        backAction: (() -> Void)?,
        crossFileDiffProvider: ((Bool) -> (URL, URL)?)?
    ) {
        self.init(left: left, right: right, backAction: backAction)
        self.crossFileDiffProvider = crossFileDiffProvider
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = CompareDropView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
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
        let contentTopSpacing: CGFloat = 6
        let miniMapWidth: CGFloat = 12
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
        prevDiffButton.target = self
        prevDiffButton.action = #selector(goPrevDiff)
        prevDiffButton.bezelStyle = .rounded
        prevDiffButton.font = .systemFont(ofSize: 11, weight: .regular)
        prevDiffButton.translatesAutoresizingMaskIntoConstraints = false
        nextDiffButton.target = self
        nextDiffButton.action = #selector(goNextDiff)
        nextDiffButton.bezelStyle = .rounded
        nextDiffButton.font = .systemFont(ofSize: 11, weight: .regular)
        nextDiffButton.translatesAutoresizingMaskIntoConstraints = false
        leftCopyNameButton.target = self
        leftCopyNameButton.action = #selector(copyLeftFileName)
        leftCopyPathButton.target = self
        leftCopyPathButton.action = #selector(copyLeftFullPath)
        rightCopyNameButton.target = self
        rightCopyNameButton.action = #selector(copyRightFileName)
        rightCopyPathButton.target = self
        rightCopyPathButton.action = #selector(copyRightFullPath)
        helpButton.target = self
        helpButton.action = #selector(showHelpDialog)
        for b in [leftCopyNameButton, leftCopyPathButton, rightCopyNameButton, rightCopyPathButton] {
            b.bezelStyle = .rounded
            b.font = .systemFont(ofSize: 11, weight: .regular)
            b.translatesAutoresizingMaskIntoConstraints = false
        }
        helpButton.bezelStyle = .rounded
        helpButton.font = .systemFont(ofSize: 12, weight: .bold)
        helpButton.translatesAutoresizingMaskIntoConstraints = false
        leftCopyNameButton.toolTip = "左ファイル名をコピー"
        leftCopyPathButton.toolTip = "左フルパスをコピー"
        rightCopyNameButton.toolTip = "右ファイル名をコピー"
        rightCopyPathButton.toolTip = "右フルパスをコピー"
        for lbl in [leftLabel, rightLabel] {
            lbl.font = .systemFont(ofSize: 11, weight: .medium)
            lbl.textColor = .secondaryLabelColor
            lbl.lineBreakMode = .byTruncatingMiddle
            lbl.translatesAutoresizingMaskIntoConstraints = false
            lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            lbl.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        header.addSubview(backBtn)
        header.addSubview(reloadButton)
        header.addSubview(prevDiffButton)
        header.addSubview(nextDiffButton)
        header.addSubview(leftCopyNameButton)
        header.addSubview(leftCopyPathButton)
        header.addSubview(rightCopyNameButton)
        header.addSubview(rightCopyPathButton)
        header.addSubview(helpButton)
        header.addSubview(leftLabel)
        header.addSubview(rightLabel)
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
        charDiffView.onClose = { [weak self] in
            self?.hideDetail()
        }
        charDiffView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(charDiffView)
        charDiffHeight = charDiffView.heightAnchor.constraint(equalToConstant: 0)

        // ── Overlay minimap (does not affect existing table layout) ──────────
        miniMapOverlay.translatesAutoresizingMaskIntoConstraints = false
        miniMapOverlay.onSelectRow = { [weak self] row in
            self?.jumpToRow(row)
        }
        view.addSubview(miniMapOverlay)
        diffProgressLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        diffProgressLabel.textColor = .secondaryLabelColor
        diffProgressLabel.alignment = .center
        diffProgressLabel.wantsLayer = true
        diffProgressLabel.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
        diffProgressLabel.layer?.cornerRadius = 4
        diffProgressLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(diffProgressLabel)

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
            reloadButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            reloadButton.leadingAnchor.constraint(equalTo: backBtn.trailingAnchor, constant: 8),
            prevDiffButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            prevDiffButton.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 8),
            nextDiffButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            nextDiffButton.leadingAnchor.constraint(equalTo: prevDiffButton.trailingAnchor, constant: 6),
            leftLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            leftLabel.leadingAnchor.constraint(equalTo: nextDiffButton.trailingAnchor, constant: 8),
            leftCopyNameButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            leftCopyNameButton.leadingAnchor.constraint(equalTo: leftLabel.trailingAnchor, constant: 4),
            leftCopyNameButton.widthAnchor.constraint(equalToConstant: 26),
            leftCopyPathButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            leftCopyPathButton.leadingAnchor.constraint(equalTo: leftCopyNameButton.trailingAnchor, constant: 4),
            leftCopyPathButton.widthAnchor.constraint(equalToConstant: 26),
            leftCopyPathButton.trailingAnchor.constraint(lessThanOrEqualTo: header.centerXAnchor, constant: -8),
            rightLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            rightLabel.leadingAnchor.constraint(equalTo: header.centerXAnchor, constant: 8),
            rightCopyNameButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            rightCopyNameButton.leadingAnchor.constraint(equalTo: rightLabel.trailingAnchor, constant: 4),
            rightCopyNameButton.widthAnchor.constraint(equalToConstant: 26),
            rightCopyPathButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            rightCopyPathButton.leadingAnchor.constraint(equalTo: rightCopyNameButton.trailingAnchor, constant: 4),
            rightCopyPathButton.widthAnchor.constraint(equalToConstant: 26),
            rightCopyPathButton.trailingAnchor.constraint(lessThanOrEqualTo: helpButton.leadingAnchor, constant: -6),
            helpButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            helpButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            helpButton.widthAnchor.constraint(equalToConstant: 26),

            // Divider
            div.topAnchor.constraint(equalTo: header.bottomAnchor, constant: contentTopSpacing),
            div.bottomAnchor.constraint(equalTo: infoBar.topAnchor),
            div.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            div.widthAnchor.constraint(equalToConstant: 1),

            // Left edge gutter (line numbers)
            leftNumW,
            leftNumView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: contentTopSpacing),
            leftNumView.bottomAnchor.constraint(equalTo: infoBar.topAnchor),
            leftNumView.leadingAnchor.constraint(equalTo: view.leadingAnchor),

            // Left code scroll
            leftCodeScroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: contentTopSpacing),
            leftCodeScroll.bottomAnchor.constraint(equalTo: infoBar.topAnchor),
            leftCodeScroll.leadingAnchor.constraint(equalTo: leftNumView.trailingAnchor),
            leftCodeScroll.trailingAnchor.constraint(equalTo: div.leadingAnchor),

            // Right center gutter (line numbers)
            rightNumW,
            rightNumView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: contentTopSpacing),
            rightNumView.bottomAnchor.constraint(equalTo: infoBar.topAnchor),
            rightNumView.leadingAnchor.constraint(equalTo: div.trailingAnchor),

            // Right code scroll
            rightCodeScroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: contentTopSpacing),
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

            // Overlay minimap
            miniMapOverlay.topAnchor.constraint(equalTo: header.bottomAnchor, constant: contentTopSpacing),
            miniMapOverlay.bottomAnchor.constraint(equalTo: infoBar.topAnchor),
            miniMapOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            miniMapOverlay.widthAnchor.constraint(equalToConstant: miniMapWidth),
            diffProgressLabel.topAnchor.constraint(equalTo: miniMapOverlay.topAnchor, constant: 4),
            diffProgressLabel.trailingAnchor.constraint(equalTo: miniMapOverlay.leadingAnchor, constant: -4),
            diffProgressLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
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
        sv.drawsBackground       = true
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
        leftURL = left
        rightURL = right
        leftTitleText = left.path
        rightTitleText = right.path
        leftLabel.stringValue  = leftTitleText
        rightLabel.stringValue = rightTitleText
        DispatchQueue.global(qos: .userInitiated).async {
            let lText  = self.readTextForDiff(from: left)
            let rText  = self.readTextForDiff(from: right)
            let result = DiffEngine.compute(left: lText, right: rText)
            DispatchQueue.main.async {
                self.updateInfoBar(leftText: lText, rightText: rText)
                self.applyRows(result)
            }
        }
    }

    private func readTextForDiff(from url: URL) -> String {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return "" }
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        if let s = String(data: data, encoding: .shiftJIS) { return s }
        if let s = String(data: data, encoding: .japaneseEUC) { return s }
        return String(decoding: data, as: UTF8.self)
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
        self.diffBlocks = buildDiffBlocks(from: result)
        self.currentDiffBlockIndex = -1
        self.leftNumView.rows  = result
        self.rightNumView.rows = result
        self.miniMapOverlay.rows = result
        self.leftNumView.needsDisplay  = true
        self.rightNumView.needsDisplay = true
        self.leftCodeTable.reloadData()
        self.rightCodeTable.reloadData()
        // Always reset to top on new diff load to avoid stale off-screen scroll offsets.
        if !result.isEmpty {
            self.leftCodeTable.scrollRowToVisible(0)
            self.rightCodeTable.scrollRowToVisible(0)
        }
        self.leftCodeTable.deselectAll(nil)
        self.rightCodeTable.deselectAll(nil)
        self.leftCodeScroll.contentView.scroll(to: .zero)
        self.rightCodeScroll.contentView.scroll(to: .zero)
        self.leftCodeScroll.reflectScrolledClipView(self.leftCodeScroll.contentView)
        self.rightCodeScroll.reflectScrolledClipView(self.rightCodeScroll.contentView)
        self.updateNumWidth()
        self.updateCodeColumnWidth()
        self.syncLineNumberMetrics()
        self.updateMiniMapViewport()
        self.updateDiffProgressLabel()
        updateDiffButtonsEnabled()
        if let forward = pendingBoundarySelectionForward {
            pendingBoundarySelectionForward = nil
            if !diffBlocks.isEmpty {
                selectDiffBlock(at: forward ? 0 : (diffBlocks.count - 1))
            }
        }
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
        if let backAction {
            backAction()
            return
        }
        (view.window?.windowController as? WindowController)?.pop()
    }

    @objc private func reloadComparison() {
        if let l = leftURL, let r = rightURL {
            loadDiff(left: l, right: r)
        } else if let lText = leftInputText, let rText = rightInputText {
            loadDiff(leftText: lText, rightText: rText)
        }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func copyLeftFileName() {
        copyText(leftURL?.lastPathComponent ?? leftTitleText)
    }

    @objc private func copyLeftFullPath() {
        copyText(leftURL?.path ?? leftTitleText)
    }

    @objc private func copyRightFileName() {
        copyText(rightURL?.lastPathComponent ?? rightTitleText)
    }

    @objc private func copyRightFullPath() {
        copyText(rightURL?.path ?? rightTitleText)
    }

    @objc private func showHelpDialog() {
        let text = """
キーボードショートカット

共通
• Esc: 戻る
• Cmd+R: 再読み込み
• Cmd+W: ウィンドウを閉じる
• Cmd+Q: 終了

差分ビュー
• Cmd+←: 前の差分へ
• Cmd+→: 次の差分へ
• 下部差分パネルでテキスト選択中に Cmd+C: コピー

ディレクトリビュー
• ↑/↓: 選択移動
• ←/→: ディレクトリ折りたたみ/展開
• Enter: ファイルをプレビュー（ディレクトリは開閉）

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

    private func installShortcutMonitorIfNeeded() {
        guard shortcutMonitor == nil else { return }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let plainFlags = flags.subtracting([.numericPad, .function])
            if plainFlags.isEmpty {
                switch event.keyCode {
                case 53: // Esc
                    self.goBack()
                    return nil
                default:
                    break
                }
            }
            guard flags.contains(.command) else { return event }
            switch event.keyCode {
            case 8: // C
                if self.charDiffView.copySelectionIfPossible() {
                    return nil
                }
                return event
            case 15: // R
                self.reloadComparison()
                return nil
            case 13: // W
                self.view.window?.performClose(nil)
                return nil
            case 12: // Q
                NSApp.terminate(nil)
                return nil
            case 123: // left
                self.goPrevDiff()
                return nil
            case 124: // right
                self.goNextDiff()
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

    private func updateDiffButtonsEnabled() {
        let enabled = !diffBlocks.isEmpty
        prevDiffButton.isEnabled = enabled
        nextDiffButton.isEnabled = enabled
    }

    @objc private func goNextDiff() {
        jumpDiff(forward: true)
    }

    @objc private func goPrevDiff() {
        jumpDiff(forward: false)
    }

    private func jumpDiff(forward: Bool) {
        guard !diffBlocks.isEmpty else { return }
        if currentDiffBlockIndex < 0 {
            currentDiffBlockIndex = forward ? 0 : (diffBlocks.count - 1)
        } else {
            if forward {
                if currentDiffBlockIndex >= diffBlocks.count - 1 {
                    if AppSettings.shared.crossFileDiffNavigation,
                       let pair = crossFileDiffProvider?(true) {
                        pendingBoundarySelectionForward = true
                        loadDiff(left: pair.0, right: pair.1)
                        return
                    }
                    showDiffBoundaryMessage(isLast: true)
                    return
                }
                currentDiffBlockIndex += 1
            } else {
                if currentDiffBlockIndex <= 0 {
                    if AppSettings.shared.crossFileDiffNavigation,
                       let pair = crossFileDiffProvider?(false) {
                        pendingBoundarySelectionForward = false
                        loadDiff(left: pair.0, right: pair.1)
                        return
                    }
                    showDiffBoundaryMessage(isLast: false)
                    return
                }
                currentDiffBlockIndex -= 1
            }
        }
        let block = diffBlocks[currentDiffBlockIndex]
        let index = IndexSet(integersIn: block)
        leftCodeTable.selectRowIndexes(index, byExtendingSelection: false)
        rightCodeTable.selectRowIndexes(index, byExtendingSelection: false)
        leftCodeTable.scrollRowToVisible(block.lowerBound)
        rightCodeTable.scrollRowToVisible(block.lowerBound)
        updateMiniMapViewport()
        updateDiffProgressLabel()
    }

    private func showDiffBoundaryMessage(isLast: Bool) {
        guard AppSettings.shared.showDiffBoundaryMessage else { return }
        let alert = NSAlert()
        alert.messageText = isLast ? "最後の差分に到達しました" : "最初の差分に到達しました"
        alert.alertStyle = .informational
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func buildDiffBlocks(from rows: [DiffRow]) -> [ClosedRange<Int>] {
        var blocks: [ClosedRange<Int>] = []
        var start: Int?

        for (idx, row) in rows.enumerated() {
            let changed = !(row.leftStyle == .equal && row.rightStyle == .equal)
            if changed {
                if start == nil { start = idx }
            } else if let s = start {
                blocks.append(s...idx - 1)
                start = nil
            }
        }

        if let s = start, !rows.isEmpty {
            blocks.append(s...(rows.count - 1))
        }
        return blocks
    }

    private func diffBlockIndex(containing row: Int) -> Int? {
        guard row >= 0 else { return nil }
        return diffBlocks.firstIndex(where: { $0.contains(row) })
    }

    private func selectDiffBlock(at index: Int) {
        guard index >= 0, index < diffBlocks.count else { return }
        currentDiffBlockIndex = index
        let block = diffBlocks[index]
        let selection = IndexSet(integersIn: block)
        leftCodeTable.selectRowIndexes(selection, byExtendingSelection: false)
        rightCodeTable.selectRowIndexes(selection, byExtendingSelection: false)
        leftCodeTable.scrollRowToVisible(block.lowerBound)
        rightCodeTable.scrollRowToVisible(block.lowerBound)
        updateMiniMapViewport()
        updateDiffProgressLabel()
    }

    private func jumpToRow(_ row: Int) {
        guard row >= 0, row < rows.count else { return }
        if let blockIndex = diffBlockIndex(containing: row) {
            selectDiffBlock(at: blockIndex)
            return
        }
        let index = IndexSet(integer: row)
        leftCodeTable.selectRowIndexes(index, byExtendingSelection: false)
        rightCodeTable.selectRowIndexes(index, byExtendingSelection: false)
        leftCodeTable.scrollRowToVisible(row)
        rightCodeTable.scrollRowToVisible(row)
        updateMiniMapViewport()
    }

    private func updateMiniMapViewport() {
        guard rows.count > 0 else {
            miniMapOverlay.visibleRows = nil
            updateDiffProgressLabel()
            return
        }
        let y = leftCodeScroll.contentView.bounds.origin.y
        let rowH = max(leftCodeTable.rowHeight + leftCodeTable.intercellSpacing.height, 1)
        let top = max(0, Int(y / rowH))
        let visibleCount = max(1, Int(ceil(leftCodeScroll.contentView.bounds.height / rowH)))
        let bottom = min(rows.count - 1, top + visibleCount - 1)
        miniMapOverlay.visibleRows = top...bottom
    }

    private func updateDiffProgressLabel() {
        let total = diffBlocks.count
        let current = (currentDiffBlockIndex >= 0 && currentDiffBlockIndex < total) ? (currentDiffBlockIndex + 1) : 0
        diffProgressLabel.stringValue = "\(current)/\(total)"
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
        updateMiniMapViewport()

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
        if dr.leftStyle == .equal && dr.rightStyle == .equal {
            let other = (tv === leftCodeTable) ? rightCodeTable : leftCodeTable
            if other?.selectedRow != row {
                other?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            hideDetail()
            return
        }

        if let blockIndex = diffBlockIndex(containing: row) {
            selectDiffBlock(at: blockIndex)
            let block = diffBlocks[blockIndex]
            showDetail(for: Array(rows[block]))
        } else {
            let other = (tv === leftCodeTable) ? rightCodeTable : leftCodeTable
            if other?.selectedRow != row {
                other?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            showDetail(for: [dr])
        }
    }

    private func showDetail(for rows: [DiffRow]) {
        charDiffView.update(rows: rows)
        let lineCount = min(max(rows.count, 1), 6)
        let targetHeight = 54 + CGFloat(lineCount) * 40
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12
            charDiffHeight.animator().constant = targetHeight
        }
    }

    private func hideDetail() {
        guard charDiffHeight.constant > 0 else { return }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12
            charDiffHeight.animator().constant = 0 }
    }
}
