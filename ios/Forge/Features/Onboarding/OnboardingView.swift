import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var profile = UserProfile()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FORGE").font(.display(56)).foregroundStyle(Theme.ember)
                        Text("Plan your training, record every set, and recover with intent.")
                            .foregroundStyle(Theme.textMuted)
                    }
                    .listRowBackground(Color.clear)
                }
                Section("You") {
                    TextField("Name", text: $profile.name)
                    Stepper("Age \(profile.age)", value: $profile.age, in: 14...90)
                    Stepper("Body mass \(Int(profile.bodyMassKg)) kg", value: $profile.bodyMassKg, in: 35...200, step: 1)
                }
                Section("Training") {
                    Picker("Goal", selection: $profile.goal) {
                        ForEach(TrainingGoal.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Experience", selection: $profile.experience) {
                        ForEach(ExperienceLevel.allCases) { Text($0.displayName).tag($0) }
                    }
                    Stepper("\(profile.daysPerWeek) days per week", value: $profile.daysPerWeek, in: 2...6)
                    Stepper("\(profile.sessionMinutes) min sessions", value: $profile.sessionMinutes, in: 30...120, step: 5)
                }
                Section {
                    Button("Build my plan") { store.completeOnboarding(with: profile) }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("Forge asks for camera access to record sets and Health access for heart rate, HRV and sleep from your Apple Watch.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
        }
    }
}
