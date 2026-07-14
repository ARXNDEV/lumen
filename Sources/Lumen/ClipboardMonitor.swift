import AppKit

/// Polls the general pasteboard and keeps a searchable text history.
/// Skips concealed content (password managers mark entries with
/// org.nspasteboard.ConcealedType).
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private(set) var items: [String] = []
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    private let maxItems = 200
    private let maxPersisted = 50
    private let defaultsKey = "clipboardHistory"

    private init() {
        items = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        if pb.types?.contains(concealed) == true { return }

        guard let s = pb.string(forType: .string),
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              s.count < 20_000
        else { return }

        items.removeAll { $0 == s }
        items.insert(s, at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        UserDefaults.standard.set(Array(items.prefix(maxPersisted)), forKey: defaultsKey)
    }
}
