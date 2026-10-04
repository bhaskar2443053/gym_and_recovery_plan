import SwiftUI

struct InsightsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("INSIGHTS").font(.display(40)).foregroundStyle(Theme.text).padding(.top, 8)
                    summary
                    SectionHeader(title: "Analysed sets", detail: "\(allSets.count) sets")
                    if allSets.isEmpty {
                        Text("Record a set and its analysis appears here: reps, form score, tempo and rest.")
                            .foregroundStyle(Theme.textMuted).forgeCard()
                    }
                    ForEach(allSets) { set in
                        NavigationLink(value: set.id) { SetRow(set: set) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 32)
            }
            .background(Theme.ground)
            .navigationDestination(for: String.self) { id in
                if let set = allSets.first(where: { $0.id == id }) { SetAnalysisView(set: set) }
            }
        }
    }

    private var allSets: [SetRecord] {
        Array((store.activeSession?.sets ?? []).reversed()) + store.sessions.flatMap { Array($0.sets.reversed()) }
    }

    private var summary: some View {
        let analysed = allSets.compactMap(\.analysis)
        let avgForm = analysed.isEmpty ? nil : analysed.map(\.formScore).reduce(0, +) / analysed.count
        let week = store.sessions.filter { $0.startedAt > .now.addingTimeInterval(-7 * 86_400) }
        let volume = week.reduce(0) { $0 + $1.totalVolumeKg }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatTile(label: "Sessions 7d", value: "\(week.count)")
            StatTile(label: "Avg form", value: avgForm.map(String.init) ?? "–", tint: (avgForm ?? 100) >= 85 ? Theme.good : Theme.emberSoft)
            StatTile(label: "Volume 7d", value: volume >= 1000 ? String(format: "%.1f", volume / 1000) : "\(Int(volume))", unit: volume >= 1000 ? "t" : "kg")
        }
    }
}

struct SetRow: View {
    @Environment(AppStore.self) private var store
    var set: SetRecord

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(set.exercise?.name ?? set.exerciseId).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                Text("Set \(set.setIndex + 1) · \(formatWeight(set.loggedWeightKg)) · \(set.startedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.mono(11)).foregroundStyle(Theme.textMuted)
            }
            Spacer()
            status
        }
        .forgeCard()
    }

    @ViewBuilder private var status: some View {
        if let a = set.analysis {
            Pill(text: "\(a.reps) reps", fg: Theme.text, bg: Theme.surfaceRaised)
            Pill(text: "\(a.formScore)", fg: a.formScore >= 85 ? Theme.good : Theme.emberSoft, bg: a.formScore >= 85 ? Theme.goodWash : Theme.emberWash)
        } else if set.uploadState == .failed {
            Button("Retry") { store.retryUpload(setId: set.id) }.font(.system(size: 13, weight: .bold))
        } else {
            ProgressView().tint(Theme.glacier)
        }
    }
}
