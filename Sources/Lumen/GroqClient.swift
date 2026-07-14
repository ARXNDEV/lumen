import AppKit

// MARK: - Chat message

struct ChatMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    let role: String // "user" | "assistant"
    var content: String
    /// Optional attached screenshot (base64 PNG) for vision questions.
    var imageBase64: String?
}

// MARK: - AI client (OpenAI-compatible, streaming, multi-key rotation)

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

    /// Vision-capable model used automatically when a message has an image.
    static let visionModel = "meta-llama/llama-4-scout-17b-16e-instruct"

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

    // MARK: Key pool
    //
    // Multiple service keys are baked into the app at build time
    // (LumenAIKeys in Info.plist — see make-app.sh). Each install starts on a
    // random key so users are spread across the pool, and the client rotates
    // to the next key automatically on auth/rate-limit errors.

    var storedKey: String? {
        let k = UserDefaults.standard.string(forKey: "groqAPIKey")
        return (k?.isEmpty == false) ? k : nil
    }

    func setKey(_ key: String) {
        UserDefaults.standard.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "groqAPIKey")
    }

    private var bundledKeys: [String] {
        if let arr = Bundle.main.object(forInfoDictionaryKey: "LumenAIKeys") as? [String] {
            let keys = arr.filter { !$0.isEmpty }
            if !keys.isEmpty { return keys }
        }
        if let one = Bundle.main.object(forInfoDictionaryKey: "LumenAIKey") as? String, !one.isEmpty {
            return [one]
        }
        return []
    }

    var keyPool: [String] {
        if let override = storedKey { return [override] }
        var pool = bundledKeys
        if let env = ProcessInfo.processInfo.environment["GROQ_API_KEY"], !env.isEmpty {
            pool.append(env)
        }
        return pool
    }

    private var keyIndex: Int {
        get { UserDefaults.standard.integer(forKey: "aiKeyIndex") }
        set { UserDefaults.standard.set(newValue, forKey: "aiKeyIndex") }
    }

    private init() {
        // Spread new installs randomly across the key pool.
        if UserDefaults.standard.object(forKey: "aiKeyIndex") == nil {
            UserDefaults.standard.set(Int.random(in: 0..<1024), forKey: "aiKeyIndex")
        }
    }

    var apiKey: String? {
        let pool = keyPool
        guard !pool.isEmpty else { return nil }
        return pool[keyIndex % pool.count]
    }

    func rotateKey() {
        guard keyPool.count > 1 else { return }
        keyIndex = (keyIndex + 1) % keyPool.count
    }

    private func shouldRotate(status: Int, attempt: Int) -> Bool {
        [401, 403, 429].contains(status)
            && keyPool.count > 1
            && attempt + 1 < min(keyPool.count, 4)
    }

    // MARK: Prompts

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

    private func makeRequest(key: String, model: String, messages: [ChatMessage], stream: Bool) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let hasImage = messages.contains { $0.imageBase64 != nil }

        var msgs: [[String: Any]] = [["role": "system", "content": Self.systemPrompt]]
        for m in messages {
            if let img = m.imageBase64 {
                // OpenAI-compatible multimodal content array.
                msgs.append([
                    "role": m.role,
                    "content": [
                        ["type": "text", "text": m.content.isEmpty ? "What's in this screenshot?" : m.content],
                        ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(img)"]],
                    ],
                ])
            } else {
                msgs.append(["role": m.role, "content": m.content])
            }
        }

        var body: [String: Any] = [
            // Force the vision model whenever an image is present.
            "model": hasImage ? Self.visionModel : model,
            "messages": msgs,
            "temperature": Self.temperature,
        ]
        if stream { body["stream"] = true }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    // MARK: Non-streaming completion (Quick Fix and one-shot features)

    func complete(model: String, messages: [ChatMessage], attempt: Int = 0) async -> String? {
        guard let key = apiKey else { return nil }
        let req = makeRequest(key: key, model: model, messages: messages, stream: false)

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse
        else { return nil }

        if !(200..<300).contains(http.statusCode) {
            if shouldRotate(status: http.statusCode, attempt: attempt) {
                rotateKey()
                return await complete(model: model, messages: messages, attempt: attempt + 1)
            }
            return nil
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { return nil }
        return Self.clean(content)
    }

    // MARK: Streaming completion

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
            await self.runStream(model: model, messages: messages, attempt: 0,
                                 onDelta: onDelta, onComplete: onComplete)
        }
    }

    private func runStream(
        model: String,
        messages: [ChatMessage],
        attempt: Int,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String?, String?) -> Void
    ) async {
        func finish(_ text: String?, _ err: String?) {
            DispatchQueue.main.async { onComplete(text, err) }
        }

        guard let key = apiKey else {
            finish(nil, "**Lumen AI isn't configured on this build.** Please contact support, or (admin) set a key via the ✨ menu-bar icon → *AI Settings…*")
            return
        }

        let req = makeRequest(key: key, model: model, messages: messages, stream: true)

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: req)

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                if shouldRotate(status: http.statusCode, attempt: attempt) {
                    rotateKey()
                    await runStream(model: model, messages: messages, attempt: attempt + 1,
                                    onDelta: onDelta, onComplete: onComplete)
                    return
                }
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

// MARK: - Admin key override prompt

enum APIKeyPrompt {
    static func show() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "AI Settings (Admin)"
            alert.informativeText = "Override the built-in AI service key for this Mac. End users normally never need this — leave empty to use the built-in keys."
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
