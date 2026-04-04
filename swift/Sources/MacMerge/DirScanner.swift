import Foundation

struct DirScanner {

    // MARK: - Public

    static func compare(left: URL, right: URL) -> [DirCompareEntry] {
        let leftTree  = scanTree(in: left)
        let rightTree = scanTree(in: right)

        let allDirPaths  = Set(leftTree.dirs.keys).union(Set(rightTree.dirs.keys))
        let allFilePaths = Set(leftTree.files.keys).union(Set(rightTree.files.keys))

        var fileStatusByPath: [String: DirEntryStatus] = [:]
        for rel in allFilePaths {
            let lURL = leftTree.files[rel]
            let rURL = rightTree.files[rel]
            if lURL == nil {
                fileStatusByPath[rel] = .rightOnly
            } else if rURL == nil {
                fileStatusByPath[rel] = .leftOnly
            } else {
                let (same, binary) = compareContents(lURL!, rURL!)
                fileStatusByPath[rel] = same ? .same : (binary ? .binaryDiff : .changed)
            }
        }

        var dirHasDiff = Set<String>()
        for (filePath, status) in fileStatusByPath where status != .same {
            for anc in ancestors(of: filePath) { dirHasDiff.insert(anc) }
        }
        for dirPath in allDirPaths {
            let leftExists = leftTree.dirs[dirPath] != nil
            let rightExists = rightTree.dirs[dirPath] != nil
            if leftExists != rightExists {
                for anc in ancestorsIncludingSelf(of: dirPath) { dirHasDiff.insert(anc) }
            }
        }

        return buildTreeEntries(
            allDirPaths: allDirPaths,
            allFilePaths: allFilePaths,
            leftDirs: leftTree.dirs,
            rightDirs: rightTree.dirs,
            leftFiles: leftTree.files,
            rightFiles: rightTree.files,
            fileStatusByPath: fileStatusByPath,
            dirHasDiff: dirHasDiff
        )
    }

    // MARK: - Private

    private struct ScannedTree {
        var files: [String: URL]
        var dirs: [String: URL]
    }

    /// Returns files and directories recursively under base.
    private static func scanTree(in base: URL) -> ScannedTree {
        var files: [String: URL] = [:]
        var dirs: [String: URL] = [:]
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: []
        ) else { return ScannedTree(files: files, dirs: dirs) }

        for case let url as URL in enumerator {
            guard let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else { continue }
            // Drop base.path + "/" prefix to get relative path
            let rel = String(url.path.dropFirst(base.path.count + 1))
            if rv.isDirectory == true {
                dirs[rel] = url
            } else if rv.isRegularFile == true {
                files[rel] = url
                for parent in ancestors(of: rel) where dirs[parent] == nil {
                    dirs[parent] = base.appendingPathComponent(parent)
                }
            }
        }
        return ScannedTree(files: files, dirs: dirs)
    }

    /// Compare two files. Returns (identical, isBinary).
    private static func compareContents(_ url1: URL, _ url2: URL) -> (same: Bool, binary: Bool) {
        let fm = FileManager.default
        let size1 = (try? fm.attributesOfItem(atPath: url1.path)[.size] as? Int) ?? -1
        let size2 = (try? fm.attributesOfItem(atPath: url2.path)[.size] as? Int) ?? -2

        // Read left file (mmap for large files)
        let d1 = (try? Data(contentsOf: url1, options: .mappedIfSafe)) ?? Data()
        let binary = isBinary(d1)

        if size1 != size2 { return (false, binary) }

        let d2 = (try? Data(contentsOf: url2, options: .mappedIfSafe)) ?? Data()
        return (d1 == d2, binary)
    }

    /// Detect binary: check first 8 KB for null bytes.
    private static func isBinary(_ data: Data) -> Bool {
        return data.prefix(min(data.count, 8192)).contains(0)
    }

    private static func makeEntry(relativePath: String,
                                  status: DirEntryStatus,
                                  leftURL: URL?,
                                  rightURL: URL?) -> DirCompareEntry {
        let comps = relativePath.split(separator: "/")
        let name = comps.last.map(String.init) ?? relativePath
        let depth = max(comps.count - 1, 0)
        return DirCompareEntry(
            relativePath: relativePath,
            name: name,
            depth: depth,
            status: status,
            isDirectory: false,
            leftURL: leftURL,
            rightURL: rightURL
        )
    }

    private static func buildTreeEntries(allDirPaths: Set<String>,
                                         allFilePaths: Set<String>,
                                         leftDirs: [String: URL],
                                         rightDirs: [String: URL],
                                         leftFiles: [String: URL],
                                         rightFiles: [String: URL],
                                         fileStatusByPath: [String: DirEntryStatus],
                                         dirHasDiff: Set<String>) -> [DirCompareEntry] {
        var dirChildren: [String: [String]] = [:]
        var fileChildren: [String: [String]] = [:]
        let rootKey = ""

        for dirPath in allDirPaths {
            let parent = parentPath(of: dirPath) ?? rootKey
            dirChildren[parent, default: []].append(dirPath)
        }
        for filePath in allFilePaths {
            let parent = parentPath(of: filePath) ?? rootKey
            fileChildren[parent, default: []].append(filePath)
        }
        for key in dirChildren.keys {
            dirChildren[key]?.sort { lastPathName($0).localizedCaseInsensitiveCompare(lastPathName($1)) == .orderedAscending }
        }
        for key in fileChildren.keys {
            fileChildren[key]?.sort { lastPathName($0).localizedCaseInsensitiveCompare(lastPathName($1)) == .orderedAscending }
        }

        var out: [DirCompareEntry] = []

        func appendChildren(of parent: String?, depth: Int) {
            let key = parent ?? rootKey
            for dirPath in dirChildren[key] ?? [] {
                let hasDiff = dirHasDiff.contains(dirPath)
                out.append(DirCompareEntry(
                    relativePath: dirPath,
                    name: lastPathName(dirPath),
                    depth: depth,
                    status: hasDiff ? .changed : .same,
                    isDirectory: true,
                    leftURL: leftDirs[dirPath],
                    rightURL: rightDirs[dirPath],
                    isExpanded: false,
                    hasDescendantDiff: hasDiff
                ))
                appendChildren(of: dirPath, depth: depth + 1)
            }
            for filePath in fileChildren[key] ?? [] {
                out.append(DirCompareEntry(
                    relativePath: filePath,
                    name: lastPathName(filePath),
                    depth: depth,
                    status: fileStatusByPath[filePath] ?? .same,
                    isDirectory: false,
                    leftURL: leftFiles[filePath],
                    rightURL: rightFiles[filePath]
                ))
            }
        }

        appendChildren(of: nil, depth: 0)
        return out
    }

    private static func ancestors(of relativePath: String) -> [String] {
        let parts = relativePath.split(separator: "/")
        guard parts.count >= 2 else { return [] }
        var out: [String] = []
        for i in 1..<parts.count {
            out.append(parts.prefix(i).joined(separator: "/"))
        }
        return out
    }

    private static func ancestorsIncludingSelf(of directoryPath: String) -> [String] {
        var out = ancestors(of: directoryPath + "/x")
        out.append(directoryPath)
        return out
    }

    private static func parentPath(of relativePath: String) -> String? {
        guard let idx = relativePath.lastIndex(of: "/") else { return nil }
        return String(relativePath[..<idx])
    }

    private static func lastPathName(_ relativePath: String) -> String {
        relativePath.split(separator: "/").last.map(String.init) ?? relativePath
    }
}
