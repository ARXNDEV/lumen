import AppKit

// MARK: - Chat message

struct ChatMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    let role: String // "user" | "assistant"
    var content: String
}

// MARK: - Groq API client (OpenAI-compatible, streaming)

final class GroqClient {
    static let shared = GroqClient()

    struct Model {
        let id: String
        let name: String
    }

    static let models: [Model] = [
        Model(id: "llama-3.3-70b-versatile", name: "Llama 3.3 70B"),
        Model(id: "groq/compound", name: "Compound (live web search)"),
        Model(id: "groq/compound-mini", name: "Compound Mini (web search)"),
        Model(id: "llama-3.1-8b-instant", name: "Llama 3.1 8B (fastest)"),
        Model(id: "openai/gpt-oss-120b", name: "GPT-OSS 120B"),
        Model(id: "openai/gpt-oss-20b", name: "GPT-OSS 20B"),
        Model(id: "qwen/qwen3-32b", name: "Qwen3 32B"),
        Model(id: "moonshotai/kimi-k2-instruct", name: "Kimi K2"),
        Model(id: "deepseek-r1-distill-llama-70b", name: "DeepSeek R1 70B (reasoning)"),
    ]

    static func name(for id: String) -> String {
        models.first { $0.id == id }?.name ?? id
    }

    static func currentDefaultModel() -> String {
        UserDefaults.standard.string(forKey: "defaultModel") ?? "llama-3.3-70b-versatile"
    }

    static func setDefaultModel(_ id: String) {
        UserDefaults.standard.set(id, forKey: "defaultModel")
    }

    // MARK: Creativity (temperature)

    static let creativityLevels: [(name: String, value: Double)] = [
        ("Precise", 0.2), ("Balanced", 0.7), ("Creative", 1.0),
    ]

    static var temperature: Double {
        let t = UserDefaults.standard.double(forKey: "aiTemperature")
        return t == 0 ? 0.7 : t
    }

    static var creativityName: String {
        creativityLevels.min { abs($0.value - temperature) < abs($1.value - temperature) }?.name ?? "Balanced"
    }

    static func setTemperature(_ t: Double) {
        UserDefaults.standard.set(t, forKey: "aiTemperature")
    }

    // MARK: Key management

    var storedKey: String? {
        let k = UserDefaults.standard.string(forKey: "groqAPIKey")
        return (k?.isEmpty == false) ? k : nil
    }

    /// Built into the app bundle at build time (see make-app.sh), so end
    /// users never configure anything. A locally stored key overrides it.
    private var bundledKey: String? {
        let k = Bundle.main.object(forInfoDictionaryKey: "LumenAIKey") as? String
        return (k?.isEmpty == false) ? k : nil
    }

    var apiKey: String? {
        storedKey ?? bundledKey ?? ProcessInfo.processInfo.environment["GROQ_API_KEY"]
    }

    func setKey(_ key: String) {
        UserDefaults.standard.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "groqAPIKey")
    }

    // MARK: Streaming completion

    private static var systemPrompt: String {
        var s = """
        You are Lumen AI, a helpful assistant built into the Lumen launcher on macOS. \
        Be concise and direct. Use Markdown formatting and put code in fenced code blocks.
        """
        if let profile = UserDefaults.standard.string(forKey: "aiProfile"),
           !profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            s += "\n\nAbout the user (personalization profile — tailor answers accordingly):\n" + profile
        }
        return s
    }

    /// Strips reasoning-model chain-of-thought (<think>…</think>) and trims.
    static func clean(_ s: String) -> String {
        s.replacingOccurrences(
            of: "<think>[\\s\\S]*?</think>",
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Non-streaming completion (used by Quick Fix and other one-shot features).
    func complete(model: String, messages: [ChatMessage]) async -> String? {
        guard let key = apiKey else { return nil }
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var msgs: [[String: String]] = [["role": "system", "content": Self.systemPrompt]]
        msgs += messages.map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = [
            "model": model,
            "messages": msgs,
            "temperature": Self.temperature,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { return nil }
        return Self.clean(content)
    }

    /// Streams a chat completion. Callbacks are delivered on the main queue.
    /// onComplete(fullText, errorMessage) — exactly one is non-nil.
    @discardableResult
    func stream(
        model: String,
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String?, String?) -> Void
    ) -> Task<Void, Never> {
        Task {
            func finish(_ text: String?, _ err: String?) {
                DispatchQueue.main.async { onComplete(text, err) }
            }

            guard let key = apiKey else {
                finish(nil, "**Lumen AI isn't configured on this build.** Please contact support, or (admin) set a key via the ✨ menu-bar icon → *AI Settings…*")
                return
            }

            var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
            req.httpMethod = "POST"
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")

            var msgs: [[String: String]] = [["role": "system", "content": Self.systemPrompt]]
            msgs += messages.map { ["role": $0.role, "content": $0.content] }
            let body: [String: Any] = [
                "model": model,
                "messages": msgs,
                "stream": true,
                "temperature": Self.temperature,
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: req)

                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    var errBody = ""
                    for try await line in bytes.lines {
                        errBody += line
                        if errBody.count > 500 { break }
                    }
                    finish(nil, "AI service error (HTTP \(http.statusCode)): \(String(errBody.prefix(400)))")
                    return
                }

                var full = ""
                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))
                    if payload == "[DONE]" { break }
                    guard let data = payload.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = obj["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any],
                          let content = delta["content"] as? String,
                          !content.isEmpty
                    else { continue }
                    full += content
                    let chunk = content
                    DispatchQueue.main.async { onDelta(chunk) }
                }
                if Task.isCancelled { return }
                finish(Self.clean(full), nil)
            } catch {
                if !Task.isCancelled {
                    finish(nil, "Network error: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - API key prompt

enum APIKeyPrompt {
    static func show() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "AI Settings (Admin)"
            alert.informativeText = "Override the built-in AI service key for this Mac. End users normally never need this — leave empty to use the built-in key."
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
            field.placeholderString = "Service key…"
            alert.accessoryView = field
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
            if alert.runModal() == .alertFirstButtonReturn {
                GroqClient.shared.setKey(field.stringValue)
            }
        }
    }
}
