import AppKit
import SwiftUI

/// Omarchy's default tokyo-night palette and type scale, so the panel reads like the Linux widget.
enum Theme {
    static let background = Color(hex: 0x1A1B26)
    static let foreground = Color(hex: 0xA9B1D6)
    static let accent = Color(hex: 0x7AA2F7)
    static let urgent = Color(hex: 0xF7768E)
    static let claudeOrange = Color(hex: 0xD97757)
    /// Omarchy derives these by darkening the foreground (×1.55 dim, ×1.4 headers).
    static let dim = Color(hex: 0x6D7289)
    static let header = Color(hex: 0x797E99)
    static let track = foreground.opacity(0.18)
    static let separator = foreground.opacity(0.12)

    static let panelWidth: CGFloat = 380
    static let padding: CGFloat = 14
    static let sectionSpacing: CGFloat = 12

    enum Size {
        static let caption: CGFloat = 10
        static let bodySmall: CGFloat = 11
        static let body: CGFloat = 12
        static let title: CGFloat = 14
    }

    /// JetBrains Mono is Omarchy's default; teammates without it get the system monospace.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let family = monoFamily {
            return .custom(family, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    private static let monoFamily: String? = {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        return ["JetBrainsMono Nerd Font", "JetBrainsMono NFM", "JetBrains Mono"].first { installed.contains($0) }
    }()
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
