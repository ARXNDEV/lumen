import SwiftUI
import AppKit

// MARK: - Typography (flat SF Pro, Raycast-style)

extension Font {
    static func lumen(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension NSFont {
    static func lumenRounded(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }
}

// MARK: - Background blur

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Small building blocks

/// Keycap like Raycast's: rounded square with a key label.
struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, label.count > 1 ? 7 : 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
    }
}

// MARK: - Focus plumbing

final class FocusProxy {
    static let shared = FocusProxy()
    weak var field: NSTextField?

    func focus(retries: Int = 5) {
        guard let field, let window = field.window else {
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.focus(retries: retries - 1)
                }
            }
            return
        }
        window.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        if let editor = field.currentEditor() as? NSTextView {
            editor.insertionPointColor = NSColor(
                red: 0.62, green: 0.45, blue: 0.99, alpha: 1
            )
        }
    }
}

// MARK: - Query field

struct QueryField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onMove: (Int) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void
    var onTab: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.isBordered = false
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.font = .systemFont(ofSize: 22, weight: .regular)
        tf.textColor = .white
        tf.placeholderString = placeholder
        tf.delegate = context.coordinator
        FocusProxy.shared.field = tf
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        context.coordinator.parent = self
        if tf.stringValue != text {
            tf.stringValue = text
        }
        if tf.placeholderString != placeholder {
            tf.placeholderString = placeholder
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QueryField

        init(parent: QueryField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.onTab()
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Result row (Raycast layout: inline subtitle, type label, number badge)

struct ResultRow: View {
    let result: SearchResult
    let selected: Bool
    let hovered: Bool
    let shortcutNumber: Int?

    var body: some View {
        HStack(spacing: 11) {
            iconView
                .frame(width: 28, height: 28)

            Text(result.title)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(2)

            if !result.subtitle.isEmpty {
                Text(result.subtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .layoutPriority(0)
            }

            Spacer(minLength: 12)

            Text(result.kind.label)
                .font(.system(size: 12.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .layoutPriority(1)

            if let n = shortcutNumber {
                Text("\(n)")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(selected ? 0.11 : hovered ? 0.05 : 0))
        )
        .animation(.easeOut(duration: 0.1), value: selected)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = result.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 26, height: 26)
        } else if result.kind == .emoji,
                  let char = result.title.split(separator: " ").first {
            Text(String(char))
                .font(.system(size: 19))
        } else {
            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                .fill(Theme.color(for: result.kind).gradient)
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: result.symbolName ?? "questionmark")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

// MARK: - Quick AI view

struct AIContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct QuickAIView: View {
    @ObservedObject var model: SearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            if model.aiMessages.isEmpty && !model.isStreaming {
                emptyState
            } else {
                messageList
            }
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            toolbar
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Theme.gradient)
            Text("Ask anything")
                .font(.system(size: 16, weight: .semibold))
            Text("Lumen AI · \(GroqClient.name(for: model.aiModel))")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
            if GroqClient.shared.apiKey == nil {
                Text("Lumen AI isn't configured on this build. Admin: use the ✨ menu-bar icon → AI Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(model.aiMessages) { msg in
                        MessageBubble(message: msg)
                    }
                    if model.isStreaming {
                        if model.streamingText.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                AISignature()
                                ThinkingDots()
                            }
                        } else {
                            MessageBubble(message: ChatMessage(
                                role: "assistant",
                                content: model.streamingText
                            ))
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: AIContentHeightKey.self, value: geo.size.height)
                    }
                )
            }
            .onPreferenceChange(AIContentHeightKey.self) { model.aiContentHeight = $0 }
            .onChange(of: model.streamingText) { _ in proxy.scrollTo("bottom") }
            .onChange(of: model.aiMessages.count) { _ in proxy.scrollTo("bottom") }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(GroqClient.models, id: \.id) { m in
                    Button {
                        model.aiModel = m.id
                        GroqClient.setDefaultModel(m.id)
                    } label: {
                        if m.id == model.aiModel {
                            Label(m.name, systemImage: "checkmark")
                        } else {
                            Text(m.name)
                        }
                    }
                }
            } label: {
                Label(GroqClient.name(for: model.aiModel), systemImage: "cpu")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .chip(prominent: true)

            Spacer()

            if model.isStreaming {
                chipButton("Stop", symbol: "stop.fill") { model.stopStreaming() }
            }
            if !model.aiMessages.isEmpty && !model.isStreaming {
                chipButton("Regenerate", symbol: "arrow.clockwise") { model.regenerate() }
                chipButton("Copy", symbol: "doc.on.doc") { model.copyLastAnswer() }
                if SelectionService.accessibilityGranted {
                    chipButton("Paste", symbol: "text.insert") { model.pasteLastAnswer() }
                }
                chipButton("Chat", symbol: "bubble.left.and.bubble.right") { model.continueInChat() }
                chipButton("New", symbol: "plus") { model.newAIChat() }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    private func chipButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .chip()
    }
}

// MARK: - Main view

struct ContentView: View {
    @ObservedObject var model: SearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)

            if model.mode == .ai {
                QuickAIView(model: model)
            } else if !model.results.isEmpty {
                if model.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    WidgetBar()
                }
                resultsList
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                footer
            }
        }
        .frame(width: 720)
        .background(
            ZStack {
                VisualEffect()
                Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.87)
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            QueryField(
                text: $model.query,
                placeholder: model.mode == .ai
                    ? "Ask a follow-up…"
                    : "Search for apps and commands…",
                onMove: { model.move($0) },
                onSubmit: { model.submit() },
                onCancel: { model.cancel() },
                onTab: { model.handleTab() }
            )
            .frame(height: 30)

            if model.mode == .search {
                HStack(spacing: 8) {
                    Text("Ask AI")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Keycap(label: "Tab")
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.gradient)
                    Keycap(label: "esc")
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    @State private var hoveredID: String?

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { i, r in
                        if let title = model.sectionTitles[i] {
                            SectionHeader(title: title)
                        }
                        ResultRow(
                            result: r,
                            selected: i == model.selection,
                            hovered: hoveredID == r.id,
                            shortcutNumber: i < 9 ? i + 1 : nil
                        )
                        .id(r.id)
                        .onTapGesture { model.execute(r) }
                        .onHover { inside in
                            if inside {
                                hoveredID = r.id
                            } else if hoveredID == r.id {
                                hoveredID = nil
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: .infinity)
            .onChange(of: model.selection) { newValue in
                if model.results.indices.contains(newValue) {
                    proxy.scrollTo(model.results[newValue].id)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.gradient)

            Spacer()

            HStack(spacing: 7) {
                Text("Open")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Keycap(label: "↵")
            }

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 14)

            HStack(spacing: 7) {
                Text("Ask AI")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Keycap(label: "Tab")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }
}
