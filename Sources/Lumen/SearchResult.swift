import AppKit

struct SearchResult: Identifiable {
    enum Kind {
        case app, file, calc, system, clipboard, web, ai
        case snippet, quicklink, emoji, window
        case calendar, reminder, notion

        var label: String {
            switch self {
            case .app: return "Application"
            case .file: return "File"
            case .calc: return "Calculator"
            case .system: return "Command"
            case .clipboard: return "Clipboard"
            case .web: return "Web"
            case .ai: return "AI"
            case .snippet: return "Snippet"
            case .quicklink: return "Quicklink"
            case .emoji: return "Emoji"
            case .window: return "Window"
            case .calendar: return "Event"
            case .reminder: return "Reminder"
            case .notion: return "Notion"
            }
        }

        var sectionTitle: String {
            switch self {
            case .app: return "Applications"
            case .file: return "Files"
            case .calc: return "Calculator"
            case .system: return "Commands"
            case .clipboard: return "Clipboard History"
            case .web: return "Web"
            case .ai: return "AI"
            case .snippet: return "Snippets"
            case .quicklink: return "Quicklinks"
            case .emoji: return "Emoji"
            case .window: return "Window Management"
            case .calendar: return "Calendar"
            case .reminder: return "Reminders"
            case .notion: return "Notion"
            }
        }
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let icon: NSImage?
    let symbolName: String?
    let score: Double
    let action: () -> Void
}
