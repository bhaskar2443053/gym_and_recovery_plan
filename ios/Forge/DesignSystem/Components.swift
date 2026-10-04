import SwiftUI

/// Two concentric rings: outer = readiness (ember), inner = sleep (glacier).
struct ReadinessRings: View {
    var readiness: Int
    var sleepFraction: Double

    var body: some View {
        ZStack {
            ring(progress: Double(readiness) / 100, color: Theme.ember, width: 12)
                .frame(width: 124, height: 124)
            ring(progress: sleepFraction, color: Theme.glacier, width: 8)
                .frame(width: 84, height: 84)
            VStack(spacing: 0) {
                Text("\(readiness)").font(.display(40)).foregroundStyle(Theme.text)
                Text("READINESS").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Theme.textMuted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness \(readiness) out of 100")
    }

    private func ring(progress: Double, color: Color, width: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Theme.surfaceRaised, lineWidth: width)
            Circle().trim(from: 0, to: max(0.02, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct StatTile: View {
    var label: String
    var value: String
    var unit: String? = nil
    var tint: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).eyebrow()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.display(34)).foregroundStyle(tint)
                if let unit { Text(unit).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textMuted) }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeCard(radius: 16)
    }
}

struct Pill: View {
    var text: String
    var fg: Color
    var bg: Color
    var body: some View {
        Text(text).font(.system(size: 12, weight: .bold)).foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(bg, in: Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.ember
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Theme.ground)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SetDots: View {
    var done: Int
    var total: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                Circle().fill(i < done ? Theme.ember : Theme.ember.opacity(0.2)).frame(width: 8, height: 8)
            }
        }
        .accessibilityLabel("\(done) of \(total) sets done")
    }
}

struct SectionHeader: View {
    var title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
            Spacer()
            if let detail { Text(detail).eyebrow() }
        }
    }
}
