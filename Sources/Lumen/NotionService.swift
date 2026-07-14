import AppKit

/// Searches the user's Notion workspace via an internal integration token
/// (notion.so/my-integrations → create integration → share pages with it).
enum NotionService {
    static var token: String? {
        let t = UserDefaults.standard.string(forKey: "notionToken")
        return (t?.isEmpty == false) ? t : nil
    }

    static func setToken(_ t: String) {
        UserDefaults.standard.set(t.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "notionToken")
    }

    struct Page {
        let title: String
        let url: String
        let isDatabase: Bool
    }

    static func search(_ query: String, completion: @escaping ([Page]) -> Void) {
        guard let token else {
            completion([])
            return
        }
        var req = URLRequest(url: URL(string: "https://api.notion.com/v1/search")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 6
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "query": query,
            "page_size": 5,
        ])

        URLSession.shared.dataTask(with: req) { data, response, _ in
            guard let data,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = obj["results"] as? [[String: Any]]
            else {
                completion([])
                return
            }
            let pages = results.compactMap { r -> Page? in
                guard let url = r["url"] as? String else { return nil }
                let isDatabase = (r["object"] as? String) == "database"
                var title = "Untitled"
                if isDatabase, let t = r["title"] as? [[String: Any]] {
                    title = t.compactMap { $0["plain_text"] as? String }.joined()
                } else if let props = r["properties"] as? [String: Any] {
                    for value in props.values {
                        if let v = value as? [String: Any],
                           (v["type"] as? String) == "title",
                           let t = v["title"] as? [[String: Any]] {
                            let joined = t.compactMap { $0["plain_text"] as? String }.joined()
                            if !joined.isEmpty { title = joined }
                            break
                        }
                    }
                }
                return Page(title: title.isEmpty ? "Untitled" : title, url: url, isDatabase: isDatabase)
            }
            completion(pages)
        }.resume()
    }

    static func promptForToken() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Notion Integration Token"
            alert.informativeText = "Create an internal integration at notion.so/my-integrations, share the pages you want searchable with it, then paste the secret here. Stored locally, sent only to api.notion.com."
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
            field.placeholderString = "ntn_… or secret_…"
            alert.accessoryView = field
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
            if alert.runModal() == .alertFirstButtonReturn {
                setToken(field.stringValue)
            }
        }
    }
}
