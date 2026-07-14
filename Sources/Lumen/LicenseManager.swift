import SwiftUI
import AppKit
import CryptoKit

/// ArxOne licensing: one $1/month subscription unlocks EVERY ARXNDEV app.
/// The license lives in a shared folder (~/Library/Application Support/ArxOne)
/// so future apps (Launchpad, Notch, …) read the same entitlement.
/// 7-day free trial starts on first launch.
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    static let priceLine = "$1/month · 7-day free trial"
    // TODO: replace with the real checkout page (Stripe/Lemon Squeezy/Gumroad).
    static let checkoutURL = URL(string: "https://github.com/ARXNDEV/lumen#subscribe")!

    private static let salt = "arxone-2026-suite-salt-v1"
    private static let trialDays = 7

    private let fileURL: URL

    @Published private(set) var licenseKey: String?
    @Published private(set) var trialStart: Date?

    private struct State: Codable {
        var trialStart: Date?
        var licenseKey: String?
    }

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ArxOne", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("license.json")

        if let data = try? Data(contentsOf: fileURL),
           let state = try? JSONDecoder().decode(State.self, from: data) {
            trialStart = state.trialStart
            licenseKey = state.licenseKey
        }
    }

    private func save() {
        let state = State(trialStart: trialStart, licenseKey: licenseKey)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: fileURL)
        }
    }

    func ensureTrialStarted() {
        guard trialStart == nil else { return }
        trialStart = Date()
        save()
    }

    var isLicensed: Bool {
        guard let key = licenseKey else { return false }
        return Self.isValid(key)
    }

    var trialDaysLeft: Int {
        guard let start = trialStart else { return Self.trialDays }
        let used = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return max(0, Self.trialDays - used)
    }

    var entitled: Bool {
        isLicensed || trialDaysLeft > 0
    }

    @discardableResult
    func activate(_ key: String) -> Bool {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard Self.isValid(k) else { return false }
        licenseKey = k
        save()
        return true
    }

    /// Keys look like ARX1-XXXX-XXXX-CCCC where CCCC is a checksum.
    /// Generate them with scripts/gen-license.sh. (Offline validation for v1;
    /// move to server-side validation with the backend proxy.)
    static func isValid(_ key: String) -> Bool {
        let parts = key.split(separator: "-").map(String.init)
        guard parts.count == 4, parts[0] == "ARX1" else { return false }
        let body = parts[0...2].joined(separator: "-")
        let digest = SHA256.hash(data: Data((body + salt).utf8))
        let hex = digest.map { String(format: "%02X", $0) }.joined()
        return String(hex.prefix(4)) == parts[3]
    }
}

// MARK: - Paywall window

final class PaywallController {
    static let shared = PaywallController()
    private var window: NSWindow?

    func show() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if self.window == nil {
                let w = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
                    styleMask: [.titled, .closable],
                    backing: .buffered,
                    defer: false
                )
                w.title = "Lumen Pro"
                w.appearance = NSAppearance(named: .darkAqua)
                w.titlebarAppearsTransparent = true
                w.isReleasedWhenClosed = false
                w.center()
                w.contentView = NSHostingView(rootView: PaywallView())
                self.window = w
            }
            self.window?.makeKeyAndOrderFront(nil)
        }
    }
}

struct PaywallView: View {
    @ObservedObject var license = LicenseManager.shared
    @State private var keyInput = ""
    @State private var activationFailed = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Theme.gradient)
                .shadow(color: Theme.violet.opacity(0.5), radius: 14)
                .padding(.top, 6)

            Text("Lumen Pro")
                .font(.system(size: 24, weight: .bold))
            Text("One subscription. Every ARXNDEV app.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$1")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(Theme.gradient)
                Text("/ month")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                bullet("Unlimited Lumen AI — chat, commands, Quick Fix")
                bullet("Calendar, Notion, widgets & every launcher feature")
                bullet("All future ARXNDEV apps included")
                bullet("Cancel anytime")
            }
            .padding(.vertical, 4)

            statusPill

            Button {
                NSWorkspace.shared.open(LicenseManager.checkoutURL)
            } label: {
                Text("Subscribe — \(LicenseManager.priceLine)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Capsule().fill(Theme.gradient))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                TextField("License key  (ARX1-XXXX-XXXX-XXXX)", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Button("Activate") {
                    activationFailed = !license.activate(keyInput)
                }
            }

            if license.isLicensed {
                Text("✓ Pro is active — thank you!")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            } else if activationFailed {
                Text("That key doesn't look valid.")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 420, height: 540)
    }

    private var statusPill: some View {
        Group {
            if license.isLicensed {
                Text("PRO ACTIVE")
                    .foregroundStyle(.green)
            } else if license.trialDaysLeft > 0 {
                Text("FREE TRIAL — \(license.trialDaysLeft) DAY\(license.trialDaysLeft == 1 ? "" : "S") LEFT")
                    .foregroundStyle(.orange)
            } else {
                Text("TRIAL ENDED")
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 10.5, weight: .bold))
        .tracking(0.8)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.gradient)
            Text(text)
                .font(.system(size: 12.5))
        }
    }
}
