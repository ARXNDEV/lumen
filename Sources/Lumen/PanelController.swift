import AppKit
import SwiftUI
import Combine
import QuartzCore

/// Borderless floating panel that can become key without activating the app
/// (Spotlight-style).
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelController: NSObject, NSWindowDelegate {
    let panel: LauncherPanel
    let viewModel = SearchViewModel()

    private var topY: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()
    private var lastCount = 0

    private let width: CGFloat = 720
    private let headerHeight: CGFloat = 58
    private let rowHeight: CGFloat = 45
    private let sectionHeaderHeight: CGFloat = 30
    private let footerHeight: CGFloat = 41
    private let maxVisibleRows = 9
    private var keyMonitor: Any?

    override init() {
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.delegate = self

        let hosting = NSHostingView(rootView: ContentView(model: viewModel))
        panel.contentView = hosting

        viewModel.onDismiss = { [weak self] in self?.hide() }
        viewModel.$results
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                guard let self else { return }
                self.lastCount = results.count
                self.applySize()
            }
            .store(in: &cancellables)
        viewModel.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applySize()
            }
            .store(in: &cancellables)
        viewModel.$aiContentHeight
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.viewModel.mode == .ai else { return }
                self.applySize()
            }
            .store(in: &cancellables)

        // ⌘1…⌘9 opens the corresponding result (matches the number badges).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.panel.isKeyWindow,
                  self.viewModel.mode == .search,
                  event.modifierFlags.contains(.command),
                  let chars = event.charactersIgnoringModifiers,
                  let n = Int(chars), (1...9).contains(n),
                  self.viewModel.results.indices.contains(n - 1)
            else { return event }
            self.viewModel.execute(self.viewModel.results[n - 1])
            return nil
        }
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        topY = sf.maxY - sf.height * 0.2

        // Start a fresh Quick AI chat after 10 minutes of inactivity.
        if viewModel.mode == .ai,
           Date().timeIntervalSince(viewModel.lastAIActivity) > 600 {
            viewModel.newAIChat()
        }

        // Pick up snippets/quicklinks edited directly in their JSON files.
        SnippetStore.shared.reload()
        QuicklinkStore.shared.reload()

        // Refresh calendar/reminders/weather widgets.
        WidgetDataStore.shared.refresh()

        viewModel.reset()
        applySize()

        // Soft fade-in.
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.13
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.async {
            FocusProxy.shared.focus()
        }
    }

    func hide() {
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private func applySize() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame

        var h: CGFloat
        if viewModel.mode == .ai {
            // Hug the conversation height instead of leaving dead space.
            if viewModel.aiMessages.isEmpty && !viewModel.isStreaming {
                h = 300
            } else {
                let content = viewModel.aiContentHeight
                h = min(max(headerHeight + 1 + content + 1 + 43, 260), 620)
            }
        } else {
            let n = min(lastCount, maxVisibleRows)
            h = headerHeight + 1
            if n > 0 {
                let headers = viewModel.sectionTitles.keys.filter { $0 < n }.count
                let widgets: CGFloat = viewModel.query
                    .trimmingCharacters(in: .whitespaces).isEmpty ? 68 : 0
                let listHeight = CGFloat(n) * rowHeight
                    + CGFloat(headers) * sectionHeaderHeight + 8
                h += widgets + min(listHeight, 470) + 1 + footerHeight
            }
        }

        let x = sf.midX - width / 2
        let frame = NSRect(x: x, y: topY - h, width: width, height: h)

        if panel.isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.13
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// Set by --demo mode so screenshots can be taken while other apps are frontmost.
    var disableAutoHide = false

    func windowDidResignKey(_ notification: Notification) {
        guard !disableAutoHide else { return }
        hide()
    }
}
