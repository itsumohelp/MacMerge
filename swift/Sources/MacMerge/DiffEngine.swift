import Foundation

struct DiffEngine {

    static func compute(left: String, right: String) -> [DiffRow] {
        let leftLines  = splitLines(left)
        let rightLines = splitLines(right)
        return buildRows(left: leftLines, right: rightLines)
    }

    // MARK: - Private

    private static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        // Remove trailing empty line added by the split
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    private static func buildRows(left: [String], right: [String]) -> [DiffRow] {
        // Swift's built-in diff: O(n·d) where d = number of differences
        let changes = right.difference(from: left)

        var removedSet  = Set<Int>()
        var insertedSet = Set<Int>()
        for change in changes {
            switch change {
            case .remove(offset: let i, element: _, associatedWith: _): removedSet.insert(i)
            case .insert(offset: let j, element: _, associatedWith: _): insertedSet.insert(j)
            }
        }

        var rows: [DiffRow] = []
        var li = 0, ri = 0
        var ln = 1, rn = 1

        while li < left.count || ri < right.count {
            let leftChanged  = li < left.count  && removedSet.contains(li)
            let rightChanged = ri < right.count && insertedSet.contains(ri)

            if !leftChanged && !rightChanged {
                // Equal
                rows.append(.equal(ln: ln, rn: rn, text: left[li]))
                li += 1; ri += 1; ln += 1; rn += 1

            } else if leftChanged || rightChanged {
                // Collect contiguous block
                var removed: [String] = []
                var inserted: [String] = []
                while li < left.count  && removedSet.contains(li)  { removed.append(left[li]);   li += 1 }
                while ri < right.count && insertedSet.contains(ri) { inserted.append(right[ri]); ri += 1 }

                let pairs = min(removed.count, inserted.count)
                for k in 0..<pairs {
                    if removed[k] == inserted[k] {
                        rows.append(.equal(ln: ln, rn: rn, text: removed[k]))
                    } else {
                        rows.append(.changed(ln: ln, rn: rn, left: removed[k], right: inserted[k]))
                    }
                    ln += 1; rn += 1
                }
                for k in pairs..<removed.count  { rows.append(.removed(ln: ln, text: removed[k]));   ln += 1 }
                for k in pairs..<inserted.count { rows.append(.added(rn: rn, text: inserted[k]));   rn += 1 }

            } else if li < left.count {
                rows.append(.removed(ln: ln, text: left[li])); li += 1; ln += 1
            } else {
                rows.append(.added(rn: rn, text: right[ri])); ri += 1; rn += 1
            }
        }
        return rows
    }
}
