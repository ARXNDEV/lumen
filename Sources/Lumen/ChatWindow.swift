import AppKit
import SwiftUI

// MARK: - Window controller

final class ChatWindowController: NSObject {
    static let shared = ChatWindowController()

    private var window: NSWindow?
    private var viewModel: ChatViewModel?

    func open(conversationID: UUID? = nil) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            if self.window == nil {
                let vm = ChatViewModel()
                self.viewModel = vm
                let w = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 940, height: 640),
                    styleMask: [.titled, .closable, .miniaturizable, .resizable],
                    backing: .buffered,
                    defer: false
                )
                w.title = "Lumen AI Chat"
                w.appearance = NSAppearance(named: .darkAqua)
                w.titlebarAppearsTransparent = true
                w.titleVisibility = .hidden
                w.styleMask.insert(.fullSizeContentView)
                w.isReleasedWhenClosed = false
                w.contentMinSize = NSSize(width: 700, height: 420)
                w.center()
                w.contentView = NSHostingView(rootView: ChatView(vm: vm))
                self.window = w
            }

            if let id = conversationID {
                self.viewModel?.select(id)
            } else if self.viewModel?.selectedID == nil {
                // Resume the most recent chat instead of spawning a new
                // empty one on every open.
                if let recent = ChatStore.shared.conversations.first(where: { !$0.isArchived }) {
                    self.viewModel?.select(recent.id)
                } else {
                    self.viewModel?.newChat()
                }
            }
            self.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// Toggles always-on-top; returns the new state.
    func toggleAlwaysOnTop() -> Bool {
        guard let window else { return false }
        let floating = window.level != .floating
        window.level = floating ? .floating : .normal
        return floating
    }
}

// MARK: - View model

final class ChatViewModel: ObservableObject {
    @Published var selectedID: UUID?
    @Published var input = ""
    @Published var searchText = ""
    @Published var isStreaming = false
    @Published var streamingText = ""

    let store = ChatStore.shared
    private var task: Task<Void, Never>?

    var current: Conversation? {
        selectedID.flatMap { store.conversation($0) }
    }

    func newChat() {
        cancelStream()
        // Reuse the current chat if it's still empty — don't pile up blanks.
        if let c = current, c.messages.isEmpty, !c.isArchived { return }
        if let empty = store.conversations.first(where: { $0.messages.isEmpty && !$0.isArchived }) {
            selectedID = empty.id
            return
        }
        let convo = store.create(model: GroqClient.currentDefaultModel())
        selectedID = convo.id
    }

    func select(_ id: UUID) {
        guard id != selectedID else { return }
        cancelStream()
        selectedID = id
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        if selectedID == nil { newChat() }
        guard let id = selectedID else { return }
        input = ""
        store.append(id, ChatMessage(role: "user", content: text))
        stream(id)
    }

    func regenerate() {
        guard let id = selectedID,
              let convo = store.conversation(id),
              convo.messages.last?.role == "assistant",
              !isStreaming
        else { return }
        store.removeLast(id)
        stream(id)
    }

    func cancelStream() {
        task?.cancel()
        task = nil
        isStreaming = false
        streamingText = ""
    }

    private func stream(_ id: UUID) {
        guard let convo = store.conversation(id) else { return }
        isStreaming = true
        streamingText = ""
        task = GroqClient.shared.stream(
            model: convo.model,
            messages: convo.messages,
            onDelta: { [weak self] delta in
                self?.streamingText += delta
            },
            onComplete: { [weak self] full, error in
                guard let self else { return }
                self.isStreaming = false
                self.streamingText = ""
                let content = error ?? full ?? ""
                if !content.isEmpty {
                    self.store.append(id, ChatMessage(role: "assistant", content: content))
                }
            }
        )
    }
}

// MARK: - Chat view

struct ChatView: View {
    @ObservedObject var vm: ChatViewModel
    @ObservedObject var store = ChatStore.shared

    @State private var pinnedOnTop = false
    @State private var renamingID: UUID?
    @State private var renameText = ""

    @State private var showArchived = false

    private var filtered: [Conversation] {
        let base = store.conversations
            .filter { $0.isArchived == showArchived }
            .sorted {
                if $0.pinned != $1.pinned { return $0.pinned }
                return $0.updatedAt > $1.updatedAt
            }
        let q = vm.searchText.lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { convo in
            convo.title.lowercased().contains(q)
                || convo.messages.contains { $0.content.lowercased().contains(q) }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 240)
                .background(.ultraThinMaterial)
            Divider().opacity(0.5)
            detail
        }
        .frame(minWidth: 700, minHeight: 420)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .bold))
                Text("Lumen AI")
                    .font(.lumen(12, .heavy))
            }
            .foregroundStyle(Theme.gradient)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 82) // clear the traffic-light buttons
            .padding(.top, 12)

            HStack(spacing: 6) {
                TextField("Search chats…", text: $vm.searchText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    vm.newChat()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("New chat")
                Button {
                    showArchived.toggle()
                } label: {
                    Image(systemName: showArchived ? "archivebox.fill" : "archivebox")
                }
                .help(showArchived ? "Showing archived chats" : "Show archived chats")
            }
            .padding(.horizontal, 10)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { convo in
                        sidebarRow(convo)
                    }
                }
                .padding(.horizontal, 6)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func sidebarRow(_ convo: Conversation) -> some View {
        let selected = convo.id == vm.selectedID
        HStack(spacing: 6) {
            if convo.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            if renamingID == convo.id {
                TextField("Title", text: $renameText, onCommit: {
                    store.rename(convo.id, to: renameText)
                    renamingID = nil
                })
                .textFieldStyle(.roundedBorder)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(convo.title)
                        .font(.lumen(12, selected ? .bold : .medium))
                        .lineLimit(1)
                    Text(convo.updatedAt, style: .relative)
                        .font(.lumen(10, .regular))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? AnyShapeStyle(Theme.selectionGradient) : AnyShapeStyle(Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { vm.select(convo.id) }
        .contextMenu {
            Button(convo.pinned ? "Unpin" : "Pin") { store.togglePin(convo.id) }
            Button("Rename") {
                renameText = convo.title
                renamingID = convo.id
            }
            Button(convo.isArchived ? "Unarchive" : "Archive") {
                if vm.selectedID == convo.id { vm.selectedID = nil }
                store.toggleArchive(convo.id)
            }
            Divider()
            Button("Delete", role: .destructive) {
                if vm.selectedID == convo.id { vm.selectedID = nil }
                store.delete(convo.id)
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let convo = vm.current {
            VStack(spacing: 0) {
                header(convo)
                Divider()
                messageList(convo)
                inputBar
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Theme.gradient)
                Text("Select a chat or create a new one")
                    .font(.lumen(14, .semibold))
                    .foregroundStyle(.secondary)
                Button("New Chat") { vm.newChat() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ convo: Conversation) -> some View {
        HStack(spacing: 12) {
            Text(convo.title)
                .font(.lumen(13, .bold))
                .lineLimit(1)

            Spacer()

            if convo.messages.last?.role == "assistant", !vm.isStreaming {
                Button {
                    vm.regenerate()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .font(.lumen(11, .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Regenerate the last answer")
            }

            Menu {
                ForEach(GroqClient.models, id: \.id) { m in
                    Button {
                        store.setModel(convo.id, m.id)
                        GroqClient.setDefaultModel(m.id)
                    } label: {
                        if m.id == convo.model {
                            Label(m.name, systemImage: "checkmark")
                        } else {
                            Text(m.name)
                        }
                    }
                }
            } label: {
                Label(GroqClient.name(for: convo.model), systemImage: "cpu")
                    .font(.lumen(11, .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                ForEach(GroqClient.creativityLevels, id: \.name) { level in
                    Button {
                        GroqClient.setTemperature(level.value)
                    } label: {
                        if level.name == GroqClient.creativityName {
                            Label(level.name, systemImage: "checkmark")
                        } else {
                            Text(level.name)
                        }
                    }
                }
            } label: {
                Label(GroqClient.creativityName, systemImage: "flame")
                    .font(.lumen(11, .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Creativity level")

            Button {
                pinnedOnTop = ChatWindowController.shared.toggleAlwaysOnTop()
            } label: {
                Image(systemName: pinnedOnTop ? "pin.fill" : "pin")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Keep window on top")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .frame(height: 52)
    }

    private func messageList(_ convo: Conversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(convo.messages) { msg in
                        MessageBubble(message: msg)
                            .contextMenu {
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(msg.content, forType: .string)
                                }
                                if msg.role == "user", !vm.isStreaming {
                                    Button("Edit & Resend") {
                                        vm.input = msg.content
                                        store.truncate(convo.id, fromMessage: msg.id)
                                    }
                                }
                            }
                    }
                    if vm.isStreaming {
                        if vm.streamingText.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                AISignature()
                                ThinkingDots()
                            }
                        } else {
                            MessageBubble(message: ChatMessage(
                                role: "assistant",
                                content: vm.streamingText
                            ))
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .onChange(of: vm.streamingText) { _ in proxy.scrollTo("bottom") }
            .onChange(of: convo.messages.count) { _ in proxy.scrollTo("bottom") }
        }
    }

    private func attachFile() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let clipped = String(content.prefix(20_000))
        vm.input += (vm.input.isEmpty ? "" : "\n\n")
            + "Attached file \(url.lastPathComponent):\n```\n\(clipped)\n```\n\n"
    }

    private var canSend: Bool {
        !vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button {
                attachFile()
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Attach a text or code file")

            TextField("Message Lumen AI…", text: $vm.input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .font(.system(size: 13))
                .onSubmit { vm.send() }

            if vm.isStreaming {
                Button {
                    vm.cancelStream()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("Stop generating")
            } else {
                Button {
                    vm.send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle().fill(
                                canSend
                                    ? AnyShapeStyle(Theme.gradient)
                                    : AnyShapeStyle(Color.white.opacity(0.12))
                            )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Message bubble (shared with Quick AI)

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        if message.role == "user" {
            // You: right-aligned minimal bubble
            HStack {
                Spacer(minLength: 60)
                Text(message.content)
                    .font(.lumen(13, .medium))
                    .lineSpacing(2)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.selectionGradient)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.violet.opacity(0.25), lineWidth: 1)
                    )
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            // Lumen AI: plain text with a gradient signature
            VStack(alignment: .leading, spacing: 6) {
                AISignature()
                MarkdownText(content: message.content)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Block-level Markdown renderer: headings, bullet lists, numbered lists and
/// fenced code blocks are rendered as native views; inline Markdown
/// (bold/italic/inline code) is handled by AttributedString.
struct MarkdownText: View {
    let content: String

    private struct Block: Identifiable {
        enum Kind {
            case paragraph
            case heading(Int)
            case bullet
            case numbered(String)
            case code
        }

        let id = UUID()
        let kind: Kind
        let text: String
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var codeBuffer: [String] = []
        var paraBuffer: [String] = []
        var inCode = false

        func flushPara() {
            guard !paraBuffer.isEmpty else { return }
            out.append(Block(kind: .paragraph, text: paraBuffer.joined(separator: "\n")))
            paraBuffer = []
        }

        for raw in content.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inCode {
                    out.append(Block(kind: .code, text: codeBuffer.joined(separator: "\n")))
                    codeBuffer = []
                } else {
                    flushPara()
                }
                inCode.toggle()
                continue
            }
            if inCode {
                codeBuffer.append(raw)
                continue
            }
            if line.isEmpty {
                flushPara()
                continue
            }
            if line.hasPrefix("#") {
                flushPara()
                let level = line.prefix(while: { $0 == "#" }).count
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                out.append(Block(kind: .heading(min(level, 3)), text: text))
                continue
            }
            if line.hasPrefix("* ") || line.hasPrefix("- ") || line.hasPrefix("• ") {
                flushPara()
                out.append(Block(kind: .bullet, text: String(line.dropFirst(2))))
                continue
            }
            if let match = line.range(of: #"^\d+[.)]\s"#, options: .regularExpression) {
                flushPara()
                let num = String(line[..<match.upperBound]).trimmingCharacters(in: .whitespaces)
                out.append(Block(kind: .numbered(num), text: String(line[match.upperBound...])))
                continue
            }
            paraBuffer.append(line)
        }

        if inCode, !codeBuffer.isEmpty {
            out.append(Block(kind: .code, text: codeBuffer.joined(separator: "\n")))
        }
        flushPara()
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block.kind {
        case .paragraph:
            Text(attributed(block.text))
                .font(.lumen(13, .regular))
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .heading(let level):
            Text(attributed(block.text))
                .font(.lumen(level == 1 ? 17 : level == 2 ? 15 : 14, .bold))
                .padding(.top, 3)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bullet:
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.lumen(13, .bold))
                    .foregroundStyle(Color.accentColor)
                Text(attributed(block.text))
                    .font(.lumen(13, .regular))
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .numbered(let num):
            HStack(alignment: .top, spacing: 8) {
                Text(num)
                    .font(.lumen(13, .bold))
                    .foregroundStyle(Color.accentColor)
                Text(attributed(block.text))
                    .font(.lumen(13, .regular))
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .code:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.text)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.28))
            )
        }
    }

    private func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(text)
    }
}
