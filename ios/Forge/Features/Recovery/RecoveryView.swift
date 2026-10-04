import SwiftUI

struct RecoveryView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let last = store.sessions.first {
                            Text("After \(last.dayName) · \(Int(last.totalVolumeKg)) kg volume").eyebrow()
                        }
                        Text("RECOVER").font(.display(40)).foregroundStyle(Theme.glacier)
                    }
                    .padding(.top, 8)

                    if let plan = store.recovery {
                        topCards(plan)
                        stretches(plan)
                        activities(plan)
                        HStack(spacing: 12) {
                            Image(systemName: "moon.stars").foregroundStyle(Theme.glacier)
                            Text("Aim for \(String(format: "%.1f", plan.sleepHoursTarget)) h sleep. Next hard session in about \(plan.nextHardSessionInHours) h.")
                                .font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                        }
                        .forgeCard(fill: Theme.glacierWash, stroke: .clear)
                    } else {
                        Text("Finish a workout and Forge builds a recovery plan for the muscles you trained: stretches, protein, and sauna, massage or meditation.")
                            .foregroundStyle(Theme.textMuted).forgeCard(fill: Theme.glacierWash)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 32)
            }
            .background(Theme.groundRecovery)
            .refreshable { store.refreshRecovery() }
        }
    }

    private func topCards(_ plan: RecoveryPlan) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Protein today").eyebrow()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(plan.nutrition.proteinGrams)").font(.display(32))
                    Text("g").foregroundStyle(Theme.textMuted)
                }
                ForEach(plan.nutrition.servings, id: \.self) { s in
                    HStack {
                        Text(s.label).font(.system(size: 11)).foregroundStyle(Theme.textMuted).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(s.grams) g").font(.mono(11))
                    }
                }
                Text("\(String(format: "%.1f", plan.nutrition.waterLiters)) L water · \(plan.nutrition.carbsGrams) g carbs").font(.system(size: 11)).foregroundStyle(Theme.glacier)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeCard(fill: Theme.glacierWash)

            VStack(alignment: .leading, spacing: 8) {
                Text("Muscle load").eyebrow()
                let top = plan.muscleLoad.sorted { $0.value > $1.value }.prefix(5)
                let maxLoad = top.first?.value ?? 1
                ForEach(Array(top), id: \.key) { entry in
                    let muscle = entry.key, value = entry.value
                    HStack(spacing: 6) {
                        Text(muscle.displayName).font(.system(size: 11)).foregroundStyle(Theme.textMuted).frame(width: 64, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(Theme.surfaceRaised)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Theme.ember.opacity(0.5 + 0.5 * value / maxLoad)).frame(width: geo.size.width * value / maxLoad)
                                }
                        }
                        .frame(height: 6)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeCard(fill: Theme.glacierWash)
        }
    }

    private func stretches(_ plan: RecoveryPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Targeted stretches", detail: "\(store.completedStretchIds.count)/\(plan.stretches.count) done")
            ForEach(plan.stretches) { stretch in
                let done = store.completedStretchIds.contains(stretch.id)
                Button { store.toggleStretch(stretch.id) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().stroke(done ? Theme.glacier : Theme.stroke, lineWidth: 2).frame(width: 40, height: 40)
                            if done { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.glacier) }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stretch.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                            Text("\(stretch.targets.map(\.displayName).joined(separator: ", ")) · \(stretch.sets) × \(stretch.holdSeconds) s\(stretch.perSide ? " / side" : "")")
                                .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                            Text(stretch.cue).font(.system(size: 11)).foregroundStyle(Theme.textMuted.opacity(0.8))
                        }
                        Spacer(minLength: 0)
                    }
                    .forgeCard(fill: Theme.glacierWash)
                }
                .buttonStyle(.plain)
                .accessibilityValue(done ? "Done" : "Not done")
            }
        }
    }

    private func activities(_ plan: RecoveryPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Relax and restore")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(plan.activities) { act in
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: act.modality.systemImage).font(.system(size: 20))
                            .foregroundStyle(act.modality == .sauna ? Theme.emberSoft : Theme.glacier)
                        Text(act.modality.displayName).font(.system(size: 14, weight: .bold))
                        Text("\(act.minutes) min · \(act.detail)").font(.mono(11)).foregroundStyle(Theme.textMuted)
                        Text(act.reason).font(.system(size: 11)).foregroundStyle(Theme.textMuted.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .forgeCard(fill: act.modality == .sauna ? Theme.emberWash : Theme.glacierWash)
                }
            }
        }
    }
}
