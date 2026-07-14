import SwiftUI

/// Lumen's visual identity: violet→blue→cyan gradient, deep dark glass,
/// pill-shaped controls.
enum Theme {
    static let violet = Color(red: 0.58, green: 0.36, blue: 0.98)
    static let blue = Color(red: 0.30, green: 0.53, blue: 0.99)
    static let cyan = Color(red: 0.25, green: 0.78, blue: 0.92)

    static let gradient = LinearGradient(
        colors: [violet, blue, cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let selectionGradient = LinearGradient(
        colors: [violet.opacity(0.20), blue.opacity(0.12), cyan.opacity(0.08)],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Deep dark tint layered over the window blur so the panel looks like
    /// dark glass regardless of the wallpaper behind it.
    static let panelTint = Color(red: 0.06, green: 0.06, blue: 0.10).opacity(0.45)

    static func color(for kind: SearchResult.Kind) -> Color {
        switch kind {
        case .app: return .blue
        case .file: return .gray
        case .calc: return .orange
        case .system: return violet
        case .clipboard: return .teal
        case .web: return .green
        case .ai: return violet
        case .snippet: return .pink
        case .quicklink: return .indigo
        case .emoji: return .yellow
        case .window: return .cyan
        case .calendar: return .red
        case .reminder: return .orange
        case .notion: return Color(white: 0.35)
        }
    }
}

/// Rounded gradient tile holding an SF Symbol — used for non-app results.
struct IconTile: View {
    let symbol: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(color.gradient)
            .frame(width: 30, height: 30)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: color.opacity(0.4), radius: 4, y: 1)
    }
}

/// Keycap-styled shortcut hint, e.g. [⇥] Ask AI
struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.lumen(9, .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            Text(label)
                .font(.lumen(10, .medium))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Pill chip used for toolbar buttons and menus.
struct Chip: ViewModifier {
    var prominent = false

    func body(content: Content) -> some View {
        content
            .font(.lumen(10.5, .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(prominent ? AnyShapeStyle(Theme.selectionGradient) : AnyShapeStyle(Color.white.opacity(0.07)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func chip(prominent: Bool = false) -> some View {
        modifier(Chip(prominent: prominent))
    }
}

/// The "✦ Lumen AI" gradient signature shown above AI answers.
struct AISignature: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkle")
                .font(.system(size: 8, weight: .bold))
            Text("Lumen AI")
                .font(.system(size: 10, weight: .heavy))
        }
        .foregroundStyle(Theme.gradient)
    }
}

/// Animated typing indicator shown while the model is thinking.
struct ThinkingDots: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 5, height: 5)
                    .opacity(animating ? 1 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.16),
                        value: animating
                    )
            }
        }
        .padding(.vertical, 4)
        .onAppear { animating = true }
    }
}
