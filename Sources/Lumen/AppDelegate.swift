import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkey: HotkeyManager!
    private var quickFix: QuickFix!
    private(set) var panelController: PanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        LicenseManager.shared.ensureTrialStarted()
        AppIndex.shared.reload()
        ClipboardMonitor.shared.start()

        panelController = PanelController()
        hotkey = HotkeyManager { [weak self] in
            self?.panelController.toggle()
        }
        quickFix = QuickFix()
        quickFix.start()

        setupMainMenu()
        setupStatusItem()

        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.panelController.show()
            }
        }

        // Debug/design mode: keep the panel visible with a sample query so it
        // can be screenshotted while another app is frontmost.
        if let i = CommandLine.arguments.firstIndex(of: "--demo") {
            let demoQuery = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                self.panelController.disableAutoHide = true
                self.panelController.show()
                if demoQuery == "--ai" {
                    self.panelController.viewModel.enterAI(prompt: nil)
                    self.panelController.viewModel.aiMessages = [
                        ChatMessage(role: "user", content: "what is remote browser isolation"),
                        ChatMessage(role: "assistant", content: "**Remote Browser Isolation (RBI)** runs your browser in a remote sandbox so threats never reach your device.\n\n### Key Benefits\n- Isolates web-based threats from the local device\n- Reduces the risk of malware and ransomware\n\n```\n1. User requests a webpage\n2. Remote browser renders it\n```\nOnly safe pixels reach your machine."),
                    ]
                } else if !demoQuery.hasPrefix("--") && !demoQuery.isEmpty {
                    self.panelController.viewModel.query = demoQuery
                }
            }
        }
    }

    /// Menu-bar apps have no main menu by default, which silently breaks all
    /// standard key equivalents (⌘C, ⌘V, ⌘A, ⌘Z, ⌘W…). Install a minimal one.
    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Lumen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: "Lumen"
        )

        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Show Lumen  (⌥ Space)", action: #selector(showPanel), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let chatItem = NSMenuItem(title: "Open AI Chat", action: #selector(openChat), keyEquivalent: "")
        chatItem.target = self
        menu.addItem(chatItem)

        let proItem = NSMenuItem(title: "Lumen Pro…", action: #selector(showPaywall), keyEquivalent: "")
        proItem.target = self
        menu.addItem(proItem)

        let keyItem = NSMenuItem(title: "AI Settings…", action: #selector(setAPIKey), keyEquivalent: "")
        keyItem.target = self
        menu.addItem(keyItem)

        let rebuildItem = NSMenuItem(title: "Rebuild App Index", action: #selector(rebuildIndex), keyEquivalent: "")
        rebuildItem.target = self
        menu.addItem(rebuildItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Lumen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func showPanel() {
        panelController.show()
    }

    @objc private func rebuildIndex() {
        AppIndex.shared.reload()
    }

    @objc private func openChat() {
        ChatWindowController.shared.open()
    }

    @objc private func setAPIKey() {
        APIKeyPrompt.show()
    }

    @objc private func showPaywall() {
        PaywallController.shared.show()
    }
}
