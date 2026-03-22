import Foundation

enum AppVersion {
    static func displayTitle(base: String = "MacMerge") -> String {
        guard let version = resolveVersion(), !version.isEmpty else { return base }
        return "\(base) \(version)"
    }

    private static func resolveVersion() -> String? {
        if let changelogVersion = resolveFromChangelog() {
            return changelogVersion
        }
        if let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !bundleVersion.isEmpty {
            return "v\(bundleVersion)"
        }
        return nil
    }

    private static func resolveFromChangelog() -> String? {
        for url in changelogCandidates() {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("## v") else { continue }
                let value = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private static func changelogCandidates() -> [URL] {
        var urls: [URL] = []

        if let bundled = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") {
            urls.append(bundled)
        }

        let fm = FileManager.default
        urls.append(URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("CHANGELOG.md"))

        if let executableURL = Bundle.main.executableURL {
            var current = executableURL.deletingLastPathComponent()
            for _ in 0..<8 {
                urls.append(current.appendingPathComponent("CHANGELOG.md"))
                current.deleteLastPathComponent()
            }
        }

        var unique: [URL] = []
        var seen: Set<String> = []
        for url in urls {
            if seen.insert(url.path).inserted {
                unique.append(url)
            }
        }
        return unique
    }
}
