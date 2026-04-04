import Foundation

final class AppSettings {
    static let shared = AppSettings()
    static let didChangeNotification = Notification.Name("MacMerge.AppSettings.didChange")

    private enum Key {
        static let showDiffBoundaryMessage = "showDiffBoundaryMessage"
        static let crossFileDiffNavigation = "crossFileDiffNavigation"
    }

    private let defaults = UserDefaults.standard

    private init() {}

    var showDiffBoundaryMessage: Bool {
        get {
            if defaults.object(forKey: Key.showDiffBoundaryMessage) == nil {
                return true
            }
            return defaults.bool(forKey: Key.showDiffBoundaryMessage)
        }
        set {
            defaults.set(newValue, forKey: Key.showDiffBoundaryMessage)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    var crossFileDiffNavigation: Bool {
        get { defaults.bool(forKey: Key.crossFileDiffNavigation) }
        set {
            defaults.set(newValue, forKey: Key.crossFileDiffNavigation)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }
}
