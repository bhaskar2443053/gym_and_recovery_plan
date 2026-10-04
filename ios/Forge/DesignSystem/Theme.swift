import SwiftUI

/// Forge visual language: graphite ground, ember orange for training, glacier blue for recovery.
enum Theme {
    static let ground = Color(hex: 0x0D1015)
    static let groundRecovery = Color(hex: 0x0B1117)
    static let surface = Color(hex: 0x151A21)
    static let surfaceRaised = Color(hex: 0x1C222B)
    static let stroke = Color(hex: 0x222833)
    static let text = Color(hex: 0xE9EDF2)
    static let textMuted = Color(hex: 0x8A94A3)
    static let ember = Color(hex: 0xFF7A45)
    static let emberSoft = Color(hex: 0xFFB08A)
    static let emberWash = Color(hex: 0x1B1410)
    static let glacier = Color(hex: 0x6CC9E0)
    static let glacierWash = Color(hex: 0x111B23)
    static let good = Color(hex: 0x7BE0B0)
    static let goodWash = Color(hex: 0x10201C)
    static let heart = Color(hex: 0xFF5A6E)
    static let record = Color(hex: 0xFF4D4D)

    static let radius: CGFloat = 18
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension Font {
    /// Tall condensed numerals and headings.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black).width(.compressed) }
    /// Small uppercase data labels.
    static let label = Font.system(size: 11, weight: .medium, design: .monospaced)
    static func mono(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

extension View {
    func forgeCard(fill: Color = Theme.surface, stroke: Color = Theme.stroke, radius: CGFloat = Theme.radius) -> some View {
        padding(14)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(stroke, lineWidth: 1))
    }

    func eyebrow() -> some View {
        font(.label).tracking(1.3).foregroundStyle(Theme.textMuted).textCase(.uppercase)
    }
}

func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    return String(format: "%d:%02d", s / 60, s % 60)
}

func formatWeight(_ kg: Double?) -> String {
    guard let kg else { return "BW" }
    return kg.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(kg)) kg" : String(format: "%.1f kg", kg)
}
