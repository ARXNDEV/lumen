import Foundation

struct Conversation: Codable, Identifiable {
    var id = UUID()
    var title: String
    var model: String
    var messages: [ChatMessage]
    var pinned = false
    var archived: Bool? // optional so old saved files still decode
    var updatedAt = Date()

    var isArchived: Bool { archived ?? false }
}

/// Persists AI chat conversations as JSON in ~/Library/Application Support/Lumen.
final class ChatStore: ObservableObject {
    static let shared = ChatStore()

    @Published private(set) var conversations: [Conversation] = []

    private let fileURL: URL

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("conversations.json")

        if let data = try? Data(contentsOf: fileURL),
           let items = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = items
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(conversations) {
            try? data.write(to: fileURL)
        }
    }

    func conversation(_ id: UUID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    private func index(_ id: UUID) -> Int? {
        conversations.firstIndex { $0.id == id }
    }

    @discardableResult
    func create(model: String, messages: [ChatMessage] = [], title: String = "") -> Conversation {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let convo = Conversation(
            title: trimmed.isEmpty ? "New Chat" : String(trimmed.prefix(48)),
            model: model,
            messages: messages
        )
        conversations.insert(convo, at: 0)
        save()
        return convo
    }

    func append(_ id: UUID, _ message: ChatMessage) {
        guard let i = index(id) else { return }
        conversations[i].messages.append(message)
        if conversations[i].title == "New Chat", message.role == "user" {
            conversations[i].title = String(message.content.prefix(48))
        }
        conversations[i].updatedAt = Date()
        save()
    }

    func removeLast(_ id: UUID) {
        guard let i = index(id), !conversations[i].messages.isEmpty else { return }
        conversations[i].messages.removeLast()
        save()
    }

    func rename(_ id: UUID, to title: String) {
        guard let i = index(id) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        conversations[i].title = String(t.prefix(64))
        save()
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        save()
    }

    func togglePin(_ id: UUID) {
        guard let i = index(id) else { return }
        conversations[i].pinned.toggle()
        save()
    }

    func setModel(_ id: UUID, _ model: String) {
        guard let i = index(id) else { return }
        conversations[i].model = model
        save()
    }

    func toggleArchive(_ id: UUID) {
        guard let i = index(id) else { return }
        conversations[i].archived = !(conversations[i].archived ?? false)
        save()
    }

    /// Removes the given message and everything after it (for edit & resend).
    func truncate(_ id: UUID, fromMessage messageID: UUID) {
        guard let i = index(id),
              let m = conversations[i].messages.firstIndex(where: { $0.id == messageID })
        else { return }
        conversations[i].messages.removeSubrange(m...)
        save()
    }
}
