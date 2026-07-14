import AppKit
import Combine

final class SearchViewModel: ObservableObject {
    enum Mode {
        case search
        case ai
    }

    @Published var query: String = "" {
        didSet { if mode == .search { refresh() } }
    }
    @Published var results: [SearchResult] = []
    @Published var selection: Int = 0
    @Published var mode: Mode = .search
    /// Raycast-style section headers: row index → header title shown above it.
    @Published var sectionTitles: [Int: String] = [:]

    // Quick AI state
    @Published var aiMessages: [ChatMessage] = []
    @Published var streamingText = ""
    @Published var isStreaming = false
    @Published var aiModel: String = GroqClient.currentDefaultModel()
    /// Measured height of the Quick AI transcript, used to size the panel.
    @Published var aiContentHeight: CGFloat = 0
    var lastAIActivity = Date()

    /// Set by PanelController to hide the panel.
    var onDismiss: (() -> Void)?

    private var syncResults: [SearchResult] = []
    private var fileResults: [SearchResult] = []
    private var notionResults: [SearchResult] = []
    private var pendingFileWork: DispatchWorkItem?
    private var pendingNotionWork: DispatchWorkItem?
    private var streamTask: Task<Void, Never>?

    func reset() {
        // Always clear the input field; in AI mode this only clears the
        // follow-up box (the conversation itself is kept).
        query = ""
    }

    func move(_ delta: Int) {
        guard mode == .search, !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    func submit() {
        switch mode {
        case .search:
            guard results.indices.contains(selection) else { return }
            execute(results[selection])
        case .ai:
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !isStreaming else { return }
            query = ""
            send(text)
        }
    }

    func cancel() {
        switch mode {
        case .search:
            onDismiss?()
        case .ai:
            exitAI()
        }
    }

    func execute(_ result: SearchResult) {
        if result.kind == .ai {
            // AI results keep the panel open and switch it into AI mode.
            result.action()
            return
        }
        onDismiss?()
        result.action()
    }

    // MARK: - Quick AI

    func handleTab() {
        guard mode == .search else { return }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !Calculator.isMathExpression(q) else { return }
        enterAI(prompt: q)
    }

    func enterAI(prompt: String?) {
        mode = .ai
        query = ""
        if let p = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            send(p)
        }
    }

    func exitAI() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        streamingText = ""
        mode = .search
        query = ""
        refresh()
    }

    func newAIChat() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        streamingText = ""
        aiMessages = []
    }

    func send(_ text: String) {
        guard !isStreaming else { return }
        lastAIActivity = Date()
        aiMessages.append(ChatMessage(role: "user", content: text))
        stream()
    }

    func regenerate() {
        guard !isStreaming, aiMessages.last?.role == "assistant" else { return }
        aiMessages.removeLast()
        stream()
    }

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        if !streamingText.isEmpty {
            aiMessages.append(ChatMessage(role: "assistant", content: streamingText))
        }
        streamingText = ""
    }

    private func stream() {
        isStreaming = true
        streamingText = ""
        streamTask = GroqClient.shared.stream(
            model: aiModel,
            messages: aiMessages,
            onDelta: { [weak self] delta in
                self?.streamingText += delta
            },
            onComplete: { [weak self] full, error in
                guard let self else { return }
                self.isStreaming = false
                self.streamingText = ""
                self.lastAIActivity = Date()
                let content = error ?? full ?? ""
                if !content.isEmpty {
                    self.aiMessages.append(ChatMessage(role: "assistant", content: content))
                }
            }
        )
    }

    func copyLastAnswer() {
        guard let last = aiMessages.last(where: { $0.role == "assistant" }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(last.content, forType: .string)
    }

    /// Pastes the last answer into the previously active app.
    func pasteLastAnswer() {
        guard let last = aiMessages.last(where: { $0.role == "assistant" }) else { return }
        onDismiss?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            SelectionService.paste(last.content)
        }
    }

    func continueInChat() {
        guard !aiMessages.isEmpty else { return }
        let convo = ChatStore.shared.create(
            model: aiModel,
            messages: aiMessages,
            title: aiMessages.first?.content ?? ""
        )
        newAIChat()
        exitAI()
        onDismiss?()
        ChatWindowController.shared.open(conversationID: convo.id)
    }

    // MARK: - Search pipeline

    private func refresh() {
        pendingFileWork?.cancel()
        pendingNotionWork?.cancel()
        fileResults = []
        notionResults = []

        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            syncResults = AppProvider.defaultResults()
            rebuild(resetSelection: true)
            return
        }

        var out: [SearchResult] = []
        out += CalculatorProvider.results(for: q)
        out += AppProvider.results(for: q)
        out += SystemProvider.results(for: q)
        out += WindowProvider.results(for: q)
        out += SnippetProvider.results(for: q)
        out += QuicklinkProvider.results(for: q)
        out += EmojiProvider.results(for: q)
        out += CalendarProvider.results(for: q)
        out += ReminderProvider.results(for: q)
        out += ClipboardProvider.results(for: q)
        out += aiResults(for: q)
        out += WebProvider.results(for: q)
        syncResults = out
        rebuild(resetSelection: true)

        scheduleFileSearch(q)
        scheduleNotionSearch(q)
    }

    private func scheduleNotionSearch(_ q: String) {
        guard q.count >= 3, NotionService.token != nil, !Calculator.isMathExpression(q) else { return }
        let work = DispatchWorkItem { [weak self] in
            NotionProvider.search(q) { results in
                DispatchQueue.main.async {
                    guard let self,
                          self.mode == .search,
                          self.query.trimmingCharacters(in: .whitespaces) == q
                    else { return }
                    self.notionResults = results
                    self.rebuild(resetSelection: false)
                }
            }
        }
        pendingNotionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: AI search results (Ask AI + AI Commands)

    private static let aiCommands: [(String, String)] = [
        ("Improve Writing",
         "Improve the writing of the following text. Keep the meaning and language, make it clearer and more polished. Return only the improved text."),
        ("Fix Spelling and Grammar",
         "Fix all spelling and grammar mistakes in the following text. Keep the meaning, tone and language. Return only the corrected text."),
        ("Explain This in Simple Terms",
         "Explain the following in simple terms a non-expert can understand."),
        ("Change Tone to Professional",
         "Rewrite the following text in a professional tone. Return only the rewritten text."),
        ("Change Tone to Friendly",
         "Rewrite the following text in a friendly, casual tone. Return only the rewritten text."),
        ("Find Bugs in Code",
         "Review the following code for bugs and issues. List each problem with a short explanation and a suggested fix."),
        ("Summarize Clipboard",
         "Summarize the following text concisely."),
    ]

    private func aiResults(for q: String) -> [SearchResult] {
        var out: [SearchResult] = []

        if !Calculator.isMathExpression(q) {
            out.append(SearchResult(
                id: "ai:ask",
                kind: .ai,
                title: "Ask AI: “\(q)”",
                subtitle: "Press ⇥ — Lumen AI · \(GroqClient.name(for: aiModel))",
                icon: nil,
                symbolName: "sparkles",
                score: 0.55,
                action: { [weak self] in self?.enterAI(prompt: q) }
            ))
        }

        for (name, instruction) in Self.aiCommands {
            guard let s = Fuzzy.score(q, name) else { continue }
            out.append(SearchResult(
                id: "aicmd:\(name)",
                kind: .ai,
                title: name,
                subtitle: "Runs on selected text or clipboard — Lumen AI",
                icon: nil,
                symbolName: "wand.and.stars",
                score: 0.7 + s * 0.4,
                action: { [weak self] in
                    guard let self else { return }
                    let source = SelectionService.selectedTextOrClipboard()
                    guard !source.isEmpty else { return }
                    self.newAIChat()
                    self.enterAI(prompt: instruction + "\n\n---\n\n" + source)
                }
            ))
        }
        return out
    }

    // MARK: Files

    private func scheduleFileSearch(_ q: String) {
        guard q.count >= 3, !Calculator.isMathExpression(q) else { return }

        let work = DispatchWorkItem { [weak self] in
            FileProvider.search(q) { paths in
                DispatchQueue.main.async {
                    guard let self,
                          self.mode == .search,
                          self.query.trimmingCharacters(in: .whitespaces) == q
                    else { return }
                    self.fileResults = paths.enumerated().map { i, path in
                        SearchResult(
                            id: "file:\(path)",
                            kind: .file,
                            title: (path as NSString).lastPathComponent,
                            subtitle: (path as NSString).abbreviatingWithTildeInPath,
                            icon: NSWorkspace.shared.icon(forFile: path),
                            symbolName: nil,
                            score: 0.35 - Double(i) * 0.005,
                            action: { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                        )
                    }
                    self.rebuild(resetSelection: false)
                }
            }
        }
        pendingFileWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func rebuild(resetSelection: Bool) {
        let flat = Array((syncResults + fileResults + notionResults).sorted { $0.score > $1.score }.prefix(40))

        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            sectionTitles = flat.isEmpty ? [:] : [0: "Suggestions"]
            results = flat
        } else {
            // Group results by kind, ordering groups by their best hit
            // (flat is already score-sorted, so first occurrence = best).
            var kindOrder: [SearchResult.Kind] = []
            for r in flat where !kindOrder.contains(r.kind) {
                kindOrder.append(r.kind)
            }
            var grouped: [SearchResult] = []
            var titles: [Int: String] = [:]
            for kind in kindOrder {
                titles[grouped.count] = kind.sectionTitle
                grouped += flat.filter { $0.kind == kind }
            }
            sectionTitles = titles
            results = grouped
        }

        if resetSelection {
            selection = 0
        } else if selection >= results.count {
            selection = max(results.count - 1, 0)
        }
    }
}
