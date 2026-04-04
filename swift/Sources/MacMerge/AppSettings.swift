import Foundation

final class AppSettings {
    static let shared = AppSettings()
    static let didChangeNotification = Notification.Name("MacMerge.AppSettings.didChange")

    private struct Store: Codable {
        var showDiffBoundaryMessage: Bool = true
        var crossFileDiffNavigation: Bool = false
    }

    private let fileURL: URL
    private var store: Store

    private init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let dirURL = appSupport.appendingPathComponent("MacMerge", isDirectory: true)
        fileURL = dirURL.appendingPathComponent("settings.json", isDirectory: false)

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(Store.self, from: data) {
            store = loaded
        } else {
            store = Store()
            try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            save()
        }
    }

    var showDiffBoundaryMessage: Bool {
        get { store.showDiffBoundaryMessage }
        set {
            store.showDiffBoundaryMessage = newValue
            save()
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    var crossFileDiffNavigation: Bool {
        get { store.crossFileDiffNavigation }
        set {
            store.crossFileDiffNavigation = newValue
            save()
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    private func save() {
        let fm = FileManager.default
        let dirURL = fileURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
