import AppKit
import ApplicationServices

/// Reads the selected text of the frontmost app and pastes text back into it.
/// Uses the Accessibility API when possible, falling back to simulated ⌘C/⌘V.
/// Requires the user to grant Accessibility access to Lumen.
enum SelectionService {
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt asking the user to grant Accessibility access.
    static func requestAccess() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Selected text of the frontmost app, or nil.
    static func selectedText() -> String? {
        guard accessibilityGranted else { return nil }

        // 1. Ask the focused UI element directly (works in native text fields).
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused {
            let element = focused as! AXUIElement
            var sel: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &sel) == .success,
               let s = sel as? String, !s.isEmpty {
                return s
            }
        }

        // 2. Fall back to simulating ⌘C (restores the previous clipboard).
        return copySelectionViaKeystroke()
    }

    /// Selection if available, otherwise current clipboard text.
    static func selectedTextOrClipboard() -> String {
        if let s = selectedText(), !s.isEmpty { return s }
        return NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func copySelectionViaKeystroke() -> String? {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        let previousCount = pb.changeCount

        postKeystroke(keyCode: 0x08, flags: .maskCommand) // ⌘C

        let deadline = Date().addingTimeInterval(0.35)
        while pb.changeCount == previousCount, Date() < deadline {
            usleep(20_000)
        }
        guard pb.changeCount != previousCount else { return nil }
        let text = pb.string(forType: .string)

        if let previous {
            pb.clearContents()
            pb.setString(previous, forType: .string)
        }
        return text
    }

    /// Puts text on the clipboard and simulates ⌘V into the frontmost app.
    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        guard accessibilityGranted else { return }
        usleep(60_000)
        postKeystroke(keyCode: 0x09, flags: .maskCommand) // ⌘V
    }

    private static func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

/// Quick Fix: double-press Right Shift to fix spelling & grammar of the
/// current selection in ANY app and paste the corrected text back in place.
final class QuickFix {
    private var monitor: Any?
    private var lastShiftPress = Date.distantPast
    private var busy = false

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self,
                  event.keyCode == 60, // right shift
                  event.modifierFlags.contains(.shift)
            else { return }
            let now = Date()
            if now.timeIntervalSince(self.lastShiftPress) < 0.45 {
                self.lastShiftPress = .distantPast
                self.trigger()
            } else {
                self.lastShiftPress = now
            }
        }
    }

    private func trigger() {
        guard !busy, SelectionService.accessibilityGranted else { return }
        guard LicenseManager.shared.entitled else {
            PaywallController.shared.show()
            return
        }
        guard let text = SelectionService.selectedText(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        busy = true
        let prompt = "Fix all spelling and grammar mistakes in the following text. Keep the meaning, tone, formatting and language exactly. Return ONLY the corrected text, nothing else.\n\n" + text
        Task {
            let fixed = await GroqClient.shared.complete(
                model: "llama-3.1-8b-instant",
                messages: [ChatMessage(role: "user", content: prompt)]
            )
            DispatchQueue.main.async {
                if let fixed, !fixed.isEmpty {
                    SelectionService.paste(fixed)
                }
                self.busy = false
            }
        }
    }
}
