import AppKit

// MARK: - Generic JSON store

private func appSupportURL(_ file: String) -> URL {
    let dir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Lumen", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(file)
}

// MARK: - Snippets

struct Snippet: Codable, Identifiable {
    var id = UUID()
    var name: String
    var keyword: String
    var content: String
}

final class SnippetStore {
    static let shared = SnippetStore()
    private(set) var items: [Snippet] = []
    let fileURL = appSupportURL("snippets.json")

    private init() { load() }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let s = try? JSONDecoder().decode([Snippet].self, from: data) {
            items = s
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL)
        }
    }

    func add(name: String, keyword: String, content: String) {
        guard !name.isEmpty, !content.isEmpty else { return }
        items.append(Snippet(name: name, keyword: keyword, content: content))
        save()
    }

    func reload() { load() }
}

enum SnippetProvider {
    static func results(for q: String) -> [SearchResult] {
        SnippetStore.shared.items.compactMap { snippet in
            let score = Fuzzy.score(q, snippet.name) ?? Fuzzy.score(q, snippet.keyword)
            guard let s = score else { return nil }
            return SearchResult(
                id: "snip:\(snippet.id)",
                kind: .snippet,
                title: snippet.name,
                subtitle: String(snippet.content.replacingOccurrences(of: "\n", with: " ").prefix(60)),
                icon: nil,
                symbolName: "text.badge.plus",
                score: 0.85 + s * 0.4,
                action: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        SelectionService.paste(snippet.content)
                    }
                }
            )
        }
    }
}

// MARK: - Quicklinks

struct Quicklink: Codable, Identifiable {
    var id = UUID()
    var name: String
    var template: String // may contain {query}
}

final class QuicklinkStore {
    static let shared = QuicklinkStore()
    private(set) var items: [Quicklink] = []
    let fileURL = appSupportURL("quicklinks.json")

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let q = try? JSONDecoder().decode([Quicklink].self, from: data) {
            items = q
        } else {
            items = [
                Quicklink(name: "YouTube", template: "https://www.youtube.com/results?search_query={query}"),
                Quicklink(name: "GitHub", template: "https://github.com/search?q={query}"),
                Quicklink(name: "Wikipedia", template: "https://en.wikipedia.org/wiki/Special:Search?search={query}"),
            ]
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL)
        }
    }

    func add(name: String, template: String) {
        guard !name.isEmpty, !template.isEmpty else { return }
        items.append(Quicklink(name: name, template: template))
        save()
    }

    func reload() {
        if let data = try? Data(contentsOf: fileURL),
           let q = try? JSONDecoder().decode([Quicklink].self, from: data) {
            items = q
        }
    }
}

enum QuicklinkProvider {
    static func results(for q: String) -> [SearchResult] {
        let parts = q.split(separator: " ", maxSplits: 1).map(String.init)
        guard let first = parts.first else { return [] }
        let rest = parts.count > 1 ? parts[1] : ""

        return QuicklinkStore.shared.items.compactMap { link in
            guard let s = Fuzzy.score(first, link.name) ?? Fuzzy.score(q, link.name) else { return nil }
            let encoded = rest.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? rest
            let urlString = link.template.replacingOccurrences(of: "{query}", with: encoded)
            guard let url = URL(string: urlString) else { return nil }
            return SearchResult(
                id: "ql:\(link.id)",
                kind: .quicklink,
                title: rest.isEmpty ? link.name : "\(link.name): “\(rest)”",
                subtitle: urlString,
                icon: nil,
                symbolName: "link.circle.fill",
                score: 0.8 + s * 0.3,
                action: { NSWorkspace.shared.open(url) }
            )
        }
    }
}

// MARK: - Simple multi-field prompt dialogs

enum FormPrompt {
    static func show(title: String, message: String, fields: [String], onSave: @escaping ([String]) -> Void) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message

            let rowHeight: CGFloat = 30
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: rowHeight * CGFloat(fields.count)))
            var textFields: [NSTextField] = []
            for (i, placeholder) in fields.enumerated() {
                let y = container.frame.height - rowHeight * CGFloat(i + 1) + 3
                let tf = NSTextField(frame: NSRect(x: 0, y: y, width: 360, height: 24))
                tf.placeholderString = placeholder
                container.addSubview(tf)
                textFields.append(tf)
            }
            alert.accessoryView = container
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = textFields.first
            if alert.runModal() == .alertFirstButtonReturn {
                onSave(textFields.map { $0.stringValue })
            }
        }
    }
}

enum ProfilePrompt {
    static func show() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "AI Personalization Profile"
            alert.informativeText = "Tell Lumen AI about yourself (role, preferred languages, style). This is added to every AI request so answers fit you."

            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
            let textView = NSTextView(frame: scroll.bounds)
            textView.font = .systemFont(ofSize: 12)
            textView.string = UserDefaults.standard.string(forKey: "aiProfile") ?? ""
            textView.isRichText = false
            scroll.documentView = textView
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            alert.accessoryView = scroll

            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                UserDefaults.standard.set(textView.string, forKey: "aiProfile")
            }
        }
    }
}
