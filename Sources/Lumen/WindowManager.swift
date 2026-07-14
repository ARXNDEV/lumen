import AppKit
import ApplicationServices

/// Moves/resizes the frontmost app's window via the Accessibility API.
enum WindowManager {
    struct Action {
        let name: String
        let symbol: String
        let rect: (NSRect) -> NSRect // visibleFrame -> target (Cocoa coords)
    }

    static let actions: [Action] = [
        Action(name: "Left Half", symbol: "rectangle.lefthalf.filled") {
            NSRect(x: $0.minX, y: $0.minY, width: $0.width / 2, height: $0.height)
        },
        Action(name: "Right Half", symbol: "rectangle.righthalf.filled") {
            NSRect(x: $0.midX, y: $0.minY, width: $0.width / 2, height: $0.height)
        },
        Action(name: "Top Half", symbol: "rectangle.tophalf.filled") {
            NSRect(x: $0.minX, y: $0.midY, width: $0.width, height: $0.height / 2)
        },
        Action(name: "Bottom Half", symbol: "rectangle.bottomhalf.filled") {
            NSRect(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height / 2)
        },
        Action(name: "Maximize Window", symbol: "rectangle.fill") { $0 },
        Action(name: "Center Window", symbol: "rectangle.center.inset.filled") {
            NSRect(x: $0.minX + $0.width * 0.15, y: $0.minY + $0.height * 0.1,
                   width: $0.width * 0.7, height: $0.height * 0.8)
        },
        Action(name: "Top Left Quarter", symbol: "rectangle.inset.topleft.filled") {
            NSRect(x: $0.minX, y: $0.midY, width: $0.width / 2, height: $0.height / 2)
        },
        Action(name: "Top Right Quarter", symbol: "rectangle.inset.topright.filled") {
            NSRect(x: $0.midX, y: $0.midY, width: $0.width / 2, height: $0.height / 2)
        },
        Action(name: "Bottom Left Quarter", symbol: "rectangle.inset.bottomleft.filled") {
            NSRect(x: $0.minX, y: $0.minY, width: $0.width / 2, height: $0.height / 2)
        },
        Action(name: "Bottom Right Quarter", symbol: "rectangle.inset.bottomright.filled") {
            NSRect(x: $0.midX, y: $0.minY, width: $0.width / 2, height: $0.height / 2)
        },
    ]

    static func apply(_ action: Action) {
        guard SelectionService.accessibilityGranted else {
            SelectionService.requestAccess()
            return
        }
        guard let screen = NSScreen.main,
              let window = frontmostWindow()
        else { return }

        let target = action.rect(screen.visibleFrame)

        // Convert Cocoa (bottom-left origin) to AX (top-left of primary display).
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        var position = CGPoint(x: target.minX, y: primaryHeight - target.maxY)
        var size = CGSize(width: target.width, height: target.height)

        if let posValue = AXValueCreate(.cgPoint, &position),
           let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            // Set size twice: some apps clamp position based on the old size.
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    private static func frontmostWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window
        else { return nil }
        return (window as! AXUIElement)
    }
}

enum WindowProvider {
    static func results(for q: String) -> [SearchResult] {
        WindowManager.actions.compactMap { action in
            guard let s = Fuzzy.score(q, action.name) else { return nil }
            return SearchResult(
                id: "win:\(action.name)",
                kind: .window,
                title: action.name,
                subtitle: SelectionService.accessibilityGranted
                    ? "Move the frontmost window"
                    : "Requires Accessibility access — ⏎ to grant",
                icon: nil,
                symbolName: action.symbol,
                score: 0.72 + s * 0.45,
                action: { WindowManager.apply(action) }
            )
        }
    }
}
