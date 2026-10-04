import SwiftUI
import AVKit

struct SetAnalysisView: View {
    var set: SetRecord
    @State private var player: AVPlayer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                video
                if let a = set.analysis {
                    stats(a)
                    velocity(a)
                    formNotes(a)
                    Text(a.coachingTip).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.glacier)
                        .forgeCard(fill: Theme.glacierWash)
                } else {
                    HStack { ProgressView().tint(Theme.glacier); Text("Analysis in progress").foregroundStyle(Theme.textMuted) }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 32)
        }
        .background(Theme.ground)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if let url = set.localVideoURL, FileManager.default.fileExists(atPath: url.path) { player = AVPlayer(url: url) } }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Set \(set.setIndex + 1) · analysed in cloud").eyebrow()
                Text((set.analysis?.detectedExerciseName ?? set.exercise?.name ?? "").uppercased()).font(.display(32)).foregroundStyle(Theme.text)
            }
            Spacer()
            if let a = set.analysis {
                Pill(text: "\(Int(a.exerciseConfidence * 100))% match", fg: Theme.good, bg: Theme.goodWash)
            }
        }
    }

    @ViewBuilder private var video: some View {
        if let player {
            VideoPlayer(player: player)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private func stats(_ a: SetAnalysis) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            StatTile(label: "Reps", value: "\(a.reps)", unit: "/\(set.plannedReps)")
            StatTile(label: "Form", value: "\(a.formScore)", tint: a.formScore >= 85 ? Theme.good : Theme.emberSoft)
            StatTile(label: "Est. RPE", value: a.estimatedRPE.map { String(format: "%.1f", $0) } ?? "–")
            StatTile(label: "Load", value: a.estimatedWeightKg.map { "\(Int($0))" } ?? "BW", unit: a.estimatedWeightKg == nil ? nil : "kg")
            StatTile(label: "Rest", value: a.restBeforeSec.map(formatDuration) ?? "–")
            StatTile(label: "Peak HR", value: set.heartRateMax.map { "\(Int($0))" } ?? "–", tint: Theme.heart)
        }
    }

    private func velocity(_ a: SetAnalysis) -> some View {
        let speeds = a.relativeRepSpeeds
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Rep speed").font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(a.velocityLossPct.map { "−\(Int($0))% loss · " } ?? "")tempo \(String(format: "%.1f / %.1f s", a.tempo.eccentricSec, a.tempo.concentricSec))")
                    .font(.mono(11)).foregroundStyle(Theme.textMuted)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(speeds.enumerated()), id: \.offset) { _, speed in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(speed < 0.85 ? Theme.ember : Theme.glacier)
                        .frame(height: 64 * min(max(speed, 0.2), 1.1) / 1.1)
                }
            }
            .frame(height: 64, alignment: .bottom)
            .accessibilityLabel("Rep speed falls \(Int(a.velocityLossPct ?? 0)) percent across the set")
        }
        .forgeCard()
    }

    private func formNotes(_ a: SetAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Form notes").font(.system(size: 14, weight: .bold))
            if a.formIssues.isEmpty {
                note(color: Theme.good, wash: Theme.goodWash, title: "Clean set", detail: "No form issues detected. Range of motion \(a.rangeOfMotionScore)/100.")
            }
            ForEach(a.formIssues) { issue in
                note(color: issue.severity == .low ? Theme.emberSoft : Theme.ember, wash: Theme.emberWash,
                     title: issue.code.replacingOccurrences(of: "_", with: " ").capitalized + (issue.atSec.map { " at \(formatDuration($0))" } ?? ""),
                     detail: issue.message)
            }
        }
    }

    private func note(color: Color, wash: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .bold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(wash, in: RoundedRectangle(cornerRadius: 14))
    }
}
