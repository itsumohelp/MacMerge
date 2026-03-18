import AppKit

enum CellStyle {
    case equal
    case added
    case removed
    case changed
    case filler
}

struct DiffRow {
    let leftNum:    Int?
    let rightNum:   Int?
    let leftText:   String
    let rightText:  String
    let leftStyle:  CellStyle
    let rightStyle: CellStyle

    static func equal(ln: Int, rn: Int, text: String) -> DiffRow {
        DiffRow(leftNum: ln, rightNum: rn,
                leftText: text, rightText: text,
                leftStyle: .equal, rightStyle: .equal)
    }

    static func removed(ln: Int, text: String) -> DiffRow {
        DiffRow(leftNum: ln, rightNum: nil,
                leftText: text, rightText: "",
                leftStyle: .removed, rightStyle: .filler)
    }

    static func added(rn: Int, text: String) -> DiffRow {
        DiffRow(leftNum: nil, rightNum: rn,
                leftText: "", rightText: text,
                leftStyle: .filler, rightStyle: .added)
    }

    static func changed(ln: Int, rn: Int, left: String, right: String) -> DiffRow {
        DiffRow(leftNum: ln, rightNum: rn,
                leftText: left, rightText: right,
                leftStyle: .changed, rightStyle: .changed)
    }
}

extension CellStyle {
    var bgColor: NSColor {
        switch self {
        case .equal:
            return NSColor(name: nil) { trait in
                trait.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 0.118, green: 0.118, blue: 0.153, alpha: 1)
                    : .white
            }
        case .added:
            return NSColor(red: 0.15, green: 0.55, blue: 0.25, alpha: 0.35)
        case .removed:
            return NSColor(red: 0.65, green: 0.18, blue: 0.22, alpha: 0.35)
        case .changed:
            return NSColor(red: 0.55, green: 0.38, blue: 0.08, alpha: 0.35)
        case .filler:
            return NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        }
    }
}
