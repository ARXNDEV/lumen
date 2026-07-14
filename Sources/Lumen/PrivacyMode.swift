import AppKit

/// Controls whether Lumen's windows appear in screen recordings and
/// screen-sharing (Zoom, Meet, QuickTime, etc). When on, macOS excludes the
/// windows from capture entirely — you still see them, viewers don't.
final class PrivacyMode {
    static let shared = PrivacyMode()

    private let key = "hiddenFromCapture"

    private init() {
        // Default ON — the whole point of this build is stealth.
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    var hiddenFromCapture: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            apply()
        }
    }

    func toggle() {
        hiddenFromCapture.toggle()
    }

    /// Pushes the current setting to every open window.
    func apply() {
        let type: NSWindow.SharingType = hiddenFromCapture ? .none : .readOnly
        for window in NSApp.windows {
            window.sharingType = type
        }
    }
}
