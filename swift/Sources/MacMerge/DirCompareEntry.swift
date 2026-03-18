import AppKit

enum DirEntryStatus {
    case same
    case changed
    case binaryDiff
    case leftOnly
    case rightOnly

    var badge: String {
        switch self {
        case .same:       return "同一"
        case .changed:    return "変更"
        case .binaryDiff: return "変更(B)"
        case .leftOnly:   return "左のみ"
        case .rightOnly:  return "右のみ"
        }
    }

    var badgeColor: NSColor {
        switch self {
        case .same:       return .tertiaryLabelColor
        case .changed:    return NSColor(red: 0.95, green: 0.65, blue: 0.10, alpha: 1)
        case .binaryDiff: return NSColor(red: 0.85, green: 0.45, blue: 0.10, alpha: 1)
        case .leftOnly:   return NSColor(red: 0.75, green: 0.20, blue: 0.20, alpha: 1)
        case .rightOnly:  return NSColor(red: 0.25, green: 0.70, blue: 0.35, alpha: 1)
        }
    }

    var rowBgColor: NSColor {
        switch self {
        case .same:       return .clear
        case .changed:    return NSColor(red: 0.55, green: 0.38, blue: 0.08, alpha: 0.22)
        case .binaryDiff: return NSColor(red: 0.50, green: 0.28, blue: 0.05, alpha: 0.22)
        case .leftOnly:   return NSColor(red: 0.65, green: 0.18, blue: 0.22, alpha: 0.22)
        case .rightOnly:  return NSColor(red: 0.15, green: 0.55, blue: 0.25, alpha: 0.22)
        }
    }
}

/// A single row in the directory comparison tree.
struct DirCompareEntry {
    let relativePath: String   // full relative path from root
    let name: String           // last path component (file or dir name)
    let depth: Int             // nesting depth for indentation
    let status: DirEntryStatus
    let isDirectory: Bool
    let leftURL:  URL?
    let rightURL: URL?

    // Directory rows: whether their subtree is expanded
    var isExpanded: Bool = true

    // Computed: does this directory have any non-same descendants?
    var hasDescendantDiff: Bool = false
}
