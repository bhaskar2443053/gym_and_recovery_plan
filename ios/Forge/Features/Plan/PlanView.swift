import SwiftUI

struct PlanView: View {
    @Environment(AppStore.self) private var store
    @State private var editingProfile = false

    private let weekdaySymbols = Calendar.current.weekdaySymbols

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let plan = store.plan {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Week \(plan.week(of: .now)) of \(plan.weeks) · deload every 4th week").eyebrow()
                            Text(plan.name.uppercased()).font(.display(36)).foregroundStyle(Theme.text)
                        }
                        .padding(.top, 8)
                        ForEach(plan.days.sorted { $0.weekday < $1.weekday }) { day in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(weekdaySymbols[day.weekday - 1]).eyebrow()
                                    Spacer()
                                    Text("~\(day.estimatedMinutes) min").font(.mono(11)).foregroundStyle(Theme.textMuted)
                                }
                                Text(day.name).font(.system(size: 17, weight: .bold))
                                ForEach(day.exercises) { ex in
                                    HStack {
                                        Text(ex.exercise.name).font(.system(size: 14))
                                        Spacer()
                                        Text("\(ex.sets.count) × \(ex.sets.first?.targetReps ?? 0) · \(formatWeight(ex.sets.first?.weightKg))")
                                            .font(.mono(12)).foregroundStyle(Theme.textMuted)
                                    }
                                }
                            }
                            .forgeCard()
                        }
                    }
                    Button("Edit goals and rebuild plan") { editingProfile = true }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, 20).padding(.bottom, 32)
            }
            .background(Theme.ground)
            .sheet(isPresented: $editingProfile) { ProfileEditor() }
        }
    }
}

private struct ProfileEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var profile = UserProfile()
    @State private var oneRMText: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Goal", selection: $profile.goal) { ForEach(TrainingGoal.allCases) { Text($0.displayName).tag($0) } }
                Picker("Experience", selection: $profile.experience) { ForEach(ExperienceLevel.allCases) { Text($0.displayName).tag($0) } }
                Stepper("\(profile.daysPerWeek) days per week", value: $profile.daysPerWeek, in: 2...6)
                Stepper("\(profile.sessionMinutes) min sessions", value: $profile.sessionMinutes, in: 30...120, step: 5)
                Section("Known 1-rep max (kg, optional)") {
                    ForEach(Exercise.catalog.filter { $0.equipment == .barbell }) { ex in
                        HStack {
                            Text(ex.name)
                            Spacer()
                            TextField("auto", text: Binding(get: { oneRMText[ex.id] ?? "" }, set: { oneRMText[ex.id] = $0 }))
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        }
                    }
                }
            }
            .navigationTitle("Training goals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rebuild") {
                        profile.oneRepMaxKg = oneRMText.compactMapValues { Double($0) }
                        store.profile = profile
                        store.regeneratePlan()
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let p = store.profile { profile = p }
                oneRMText = profile.oneRepMaxKg.mapValues { String(Int($0)) }
            }
        }
    }
}
