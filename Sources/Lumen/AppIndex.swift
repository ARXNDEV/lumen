import AppKit

struct AppEntry {
    let name: String
    let url: URL
}

/// Scans standard application folders and tracks launch counts (frecency)
/// so frequently used apps rank higher.
final class AppIndex {
    static let shared = AppIndex()

    private(set) var apps: [AppEntry] = []
    private var launchCounts: [String: Int]

    private init() {
        launchCounts = UserDefaults.standard.dictionary(forKey: "launchCounts") as? [String: Int] ?? [:]
    }

    func reload() {
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let dirs = [
                "/Applications",
                "/Applications/Utilities",
                "/System/Applications",
                "/System/Applications/Utilities",
                "/System/Library/CoreServices/Applications",
                NSHomeDirectory() + "/Applications",
            ]

            var found: [AppEntry] = []
            var seen = Set<String>()

            func add(_ path: String) {
                guard !seen.contains(path) else { return }
                seen.insert(path)
                let name = fm.displayName(atPath: path)
                found.append(AppEntry(name: name, url: URL(fileURLWithPath: path)))
            }

            for dir in dirs {
                guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                for item in items {
                    let path = dir + "/" + item
                    if item.hasSuffix(".app") {
                        add(path)
                    } else if dir == "/Applications" {
                        // One level of vendor subfolders, e.g. /Applications/Adobe */
                        var isDir: ObjCBool = false
                        if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
                           let sub = try? fm.contentsOfDirectory(atPath: path) {
                            for s in sub where s.hasSuffix(".app") {
                                add(path + "/" + s)
                            }
                        }
                    }
                }
            }

            // Finder lives outside the standard app folders.
            add("/System/Library/CoreServices/Finder.app")

            let sorted = found.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            DispatchQueue.main.async {
                self.apps = sorted
            }
        }
    }

    func launchCount(_ url: URL) -> Int {
        launchCounts[url.path] ?? 0
    }

    func recordLaunch(_ url: URL) {
        launchCounts[url.path, default: 0] += 1
        UserDefaults.standard.set(launchCounts, forKey: "launchCounts")
    }
}
