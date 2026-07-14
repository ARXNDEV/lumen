import AppKit

// MARK: - Helpers

enum Shell {
    static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
    }

    static func appleScript(_ script: String) {
        run("/usr/bin/osascript", ["-e", script])
    }
}

// MARK: - Applications

enum AppProvider {
    static func results(for q: String) -> [SearchResult] {
        let scored: [(AppEntry, Double)] = AppIndex.shared.apps.compactMap { app in
            guard var s = Fuzzy.score(q, app.name) else { return nil }
            s += log2(Double(AppIndex.shared.launchCount(app.url) + 1)) * 0.08
            return (app, s)
        }
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(10)
            .map { app, s in result(for: app, score: 1.0 + s) }
    }

    /// Apps people actually reach for, used until real usage data exists.
    private static let starterSuggestions = [
        "Safari", "Google Chrome", "Arc", "Finder", "Mail", "Messages",
        "Calendar", "Notes", "System Settings", "Terminal", "Visual Studio Code",
        "Music", "Photos", "FaceTime",
    ]

    static func defaultResults() -> [SearchResult] {
        let apps = AppIndex.shared.apps
        let used = apps
            .filter { AppIndex.shared.launchCount($0.url) > 0 }
            .sorted { AppIndex.shared.launchCount($0.url) > AppIndex.shared.launchCount($1.url) }

        var picks = Array(used.prefix(7))

        // Fill remaining slots with well-known apps instead of an
        // alphabetical dump ("AppEraser", "AirPort Utility"…).
        if picks.count < 7 {
            for name in starterSuggestions {
                guard picks.count < 7 else { break }
                if let app = apps.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
                   !picks.contains(where: { $0.url == app.url }) {
                    picks.append(app)
                }
            }
        }

        var results = picks.enumerated().map { i, app in
            result(for: app, score: 1.0 - Double(i) * 0.01)
        }

        results.append(SearchResult(
            id: "sys:suggested-chat",
            kind: .system,
            title: "Open AI Chat",
            subtitle: "Lumen AI",
            icon: nil,
            symbolName: "bubble.left.and.bubble.right.fill",
            score: 0.9,
            action: { ChatWindowController.shared.open() }
        ))
        return results
    }

    static func result(for app: AppEntry, score: Double) -> SearchResult {
        SearchResult(
            id: "app:\(app.url.path)",
            kind: .app,
            title: app.name,
            subtitle: "",
            icon: NSWorkspace.shared.icon(forFile: app.url.path),
            symbolName: nil,
            score: score,
            action: {
                AppIndex.shared.recordLaunch(app.url)
                NSWorkspace.shared.openApplication(at: app.url, configuration: .init(), completionHandler: nil)
            }
        )
    }
}

// MARK: - Calculator

enum CalculatorProvider {
    static func results(for q: String) -> [SearchResult] {
        // Unit conversions: "10 km to mi", "72 f to c", "2 gb to mb"
        if let converted = Units.convert(q) {
            let value = converted.components(separatedBy: " = ").last ?? converted
            return [
                SearchResult(
                    id: "unit:\(q)",
                    kind: .calc,
                    title: converted,
                    subtitle: "Press ⏎ to copy",
                    icon: nil,
                    symbolName: "arrow.left.arrow.right.square.fill",
                    score: 10,
                    action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                    }
                )
            ]
        }

        guard Calculator.isMathExpression(q), let v = Calculator.evaluate(q) else { return [] }
        let str = Calculator.format(v)
        return [
            SearchResult(
                id: "calc:\(q)",
                kind: .calc,
                title: "= \(str)",
                subtitle: "Press ⏎ to copy the result",
                icon: nil,
                symbolName: "equal.square.fill",
                score: 10,
                action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(str, forType: .string)
                }
            )
        ]
    }
}

// MARK: - System commands

enum SystemProvider {
    struct Command {
        let name: String
        let subtitle: String
        let symbol: String
        let run: () -> Void
    }

    static let commands: [Command] = [
        Command(name: "Sleep", subtitle: "Put the Mac to sleep", symbol: "moon.fill",
                run: { Shell.run("/usr/bin/pmset", ["sleepnow"]) }),
        Command(name: "Sleep Display", subtitle: "Turn the display off", symbol: "display",
                run: { Shell.run("/usr/bin/pmset", ["displaysleepnow"]) }),
        Command(name: "Empty Trash", subtitle: "Empty the Finder trash", symbol: "trash",
                run: { Shell.appleScript("tell application \"Finder\" to empty trash") }),
        Command(name: "Toggle Dark Mode", subtitle: "Switch between light and dark appearance", symbol: "circle.lefthalf.filled",
                run: { Shell.appleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode") }),
        Command(name: "Open AI Chat", subtitle: "Full Lumen AI chat window", symbol: "bubble.left.and.bubble.right.fill",
                run: { ChatWindowController.shared.open() }),
        Command(name: "AI Settings", subtitle: "Advanced — override the built-in AI access", symbol: "key.fill",
                run: { APIKeyPrompt.show() }),
        Command(name: "Lumen Pro", subtitle: "Subscription, trial status and license", symbol: "crown.fill",
                run: { PaywallController.shared.show() }),
        Command(name: "Edit AI Profile", subtitle: "Personalize AI answers (role, style, languages)", symbol: "person.crop.circle.badge.checkmark",
                run: { ProfilePrompt.show() }),
        Command(name: "New Snippet", subtitle: "Create a reusable text snippet", symbol: "text.badge.plus",
                run: {
                    FormPrompt.show(
                        title: "New Snippet",
                        message: "Snippets paste their content into any app when selected.",
                        fields: ["Name (e.g. Work Email)", "Keyword (e.g. @email)", "Content"]
                    ) { values in
                        SnippetStore.shared.add(name: values[0], keyword: values[1], content: values[2])
                    }
                }),
        Command(name: "Manage Snippets", subtitle: "Open snippets.json (multiline edits)", symbol: "folder.badge.gearshape",
                run: { NSWorkspace.shared.open(SnippetStore.shared.fileURL) }),
        Command(name: "Add Quicklink", subtitle: "Custom URL shortcut, {query} for search terms", symbol: "link.badge.plus",
                run: {
                    FormPrompt.show(
                        title: "Add Quicklink",
                        message: "Use {query} where the search terms go, e.g. https://www.youtube.com/results?search_query={query}",
                        fields: ["Name (e.g. YouTube)", "URL template"]
                    ) { values in
                        QuicklinkStore.shared.add(name: values[0], template: values[1])
                    }
                }),
        Command(name: "Manage Quicklinks", subtitle: "Open quicklinks.json", symbol: "folder.badge.gearshape",
                run: { NSWorkspace.shared.open(QuicklinkStore.shared.fileURL) }),
        Command(name: "Enable Accessibility Access", subtitle: "Needed for paste-back, Quick Fix and window management", symbol: "accessibility",
                run: { SelectionService.requestAccess() }),
        Command(name: "Connect Google Calendar", subtitle: "Add your Google account in Internet Accounts — events appear in Lumen", symbol: "calendar.badge.plus",
                run: {
                    let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!
                    if !NSWorkspace.shared.open(url) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                    }
                }),
        Command(name: "Set Notion Token", subtitle: "Search your Notion pages from Lumen", symbol: "n.square.fill",
                run: { NotionService.promptForToken() }),
        Command(name: "Open Reminders", subtitle: "Apple Reminders", symbol: "checklist",
                run: { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app")) }),
        Command(name: "Open Calendar", subtitle: "Today's schedule", symbol: "calendar",
                run: { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }),
        Command(name: "Rebuild App Index", subtitle: "Rescan the application folders", symbol: "arrow.clockwise",
                run: { AppIndex.shared.reload() }),
        Command(name: "Quit Lumen", subtitle: "Quit this launcher", symbol: "power",
                run: { NSApp.terminate(nil) }),
    ]

    static func results(for q: String) -> [SearchResult] {
        commands.compactMap { cmd in
            guard let s = Fuzzy.score(q, cmd.name) else { return nil }
            return SearchResult(
                id: "sys:\(cmd.name)",
                kind: .system,
                title: cmd.name,
                subtitle: cmd.subtitle,
                icon: nil,
                symbolName: cmd.symbol,
                score: 0.75 + s * 0.5,
                action: cmd.run
            )
        }
    }
}

// MARK: - Clipboard history

enum ClipboardProvider {
    static func results(for q: String) -> [SearchResult] {
        let lower = q.lowercased()
        let items = ClipboardMonitor.shared.items

        var clipMode = false
        var filter = ""
        if lower == "clip" || lower.hasPrefix("clip ") {
            clipMode = true
            filter = String(lower.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }

        let matched: [(Int, String)]
        if clipMode {
            matched = items.enumerated()
                .filter { filter.isEmpty || $0.element.lowercased().contains(filter) }
                .prefix(8)
                .map { ($0.offset, $0.element) }
        } else {
            guard q.count >= 3 else { return [] }
            matched = items.enumerated()
                .filter { $0.element.lowercased().contains(lower) }
                .prefix(3)
                .map { ($0.offset, $0.element) }
        }

        return matched.map { idx, item in
            let oneLine = item
                .replacingOccurrences(of: "\n", with: " ⏎ ")
                .trimmingCharacters(in: .whitespaces)
            return SearchResult(
                id: "clip:\(idx):\(item.hashValue)",
                kind: .clipboard,
                title: String(oneLine.prefix(70)),
                subtitle: "Press ⏎ to copy to clipboard",
                icon: nil,
                symbolName: "doc.on.clipboard",
                score: clipMode ? 5.0 - Double(idx) * 0.01 : 0.45,
                action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item, forType: .string)
                }
            )
        }
    }
}

// MARK: - Web

enum WebProvider {
    static func results(for q: String) -> [SearchResult] {
        var out: [SearchResult] = []

        if !q.contains(" "), q.contains("."),
           let url = URL(string: q.hasPrefix("http") ? q : "https://\(q)"),
           url.host != nil {
            out.append(SearchResult(
                id: "url:\(q)",
                kind: .web,
                title: "Open \(url.absoluteString)",
                subtitle: "Open in default browser",
                icon: nil,
                symbolName: "link",
                score: 0.9,
                action: { NSWorkspace.shared.open(url) }
            ))
        }

        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        if let g = URL(string: "https://www.google.com/search?q=\(encoded)") {
            out.append(SearchResult(
                id: "web:\(q)",
                kind: .web,
                title: "Search Google for “\(q)”",
                subtitle: "Web search",
                icon: nil,
                symbolName: "globe",
                score: 0.005,
                action: { NSWorkspace.shared.open(g) }
            ))
        }
        return out
    }
}

// MARK: - Files (Spotlight index via mdfind)

enum FileProvider {
    /// Runs mdfind off the main thread and returns matching paths.
    static func search(_ q: String, completion: @escaping ([String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let safe = q
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: "\\", with: "")
            guard !safe.isEmpty else {
                completion([])
                return
            }

            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", "mdfind -name '\(safe)' 2>/dev/null | grep -v '\\.app$' | head -10"]
            let pipe = Pipe()
            p.standardOutput = pipe

            do {
                try p.run()
            } catch {
                completion([])
                return
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()

            let paths = String(data: data, encoding: .utf8)?
                .split(separator: "\n")
                .map(String.init) ?? []
            completion(paths)
        }
    }
}
