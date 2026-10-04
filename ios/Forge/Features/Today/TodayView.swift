import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var recordingTarget: RecordTarget?

    struct RecordTarget: Identifiable {
        let day: WorkoutDay
        var id: UUID { day.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    readinessCard
                    if let next = store.nextWorkout {
                        planSection(next.day, isToday: Calendar.current.isDateInToday(next.date))
                    } else {
                        Text("No workouts scheduled. Build a plan in the Plan tab.").foregroundStyle(Theme.textMuted)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Theme.ground)
            .fullScreenCover(item: $recordingTarget) { target in
                RecordSetView(day: target.day)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerEyebrow).eyebrow()
                Text((store.nextWorkout?.day.name ?? "Rest day").uppercased())
                    .font(.display(40)).foregroundStyle(Theme.text)
            }
            Spacer()
            if store.watch.isPaired {
                Image(systemName: store.watch.isReachable ? "applewatch.radiowaves.left.and.right" : "applewatch")
                    .foregroundStyle(store.watch.isReachable ? Theme.glacier : Theme.textMuted)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .accessibilityLabel(store.watch.isReachable ? "Watch connected" : "Watch not reachable")
            }
        }
        .padding(.top, 8)
    }

    private var headerEyebrow: String {
        let date = Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        guard let plan = store.plan else { return date }
        return "\(date) · Week \(plan.week(of: .now)) of \(plan.weeks)"
    }

    private var readinessCard: some View {
        let r = store.readiness
        return HStack(spacing: 16) {
            ReadinessRings(readiness: r.score, sleepFraction: (r.sleepHours ?? 0) / 8)
            VStack(alignment: .leading, spacing: 10) {
                metricRow("Resting HR", r.restingHeartRate.map { "\(Int($0)) bpm" })
                metricRow("HRV", r.hrvMs.map { "\(Int($0)) ms" })
                metricRow("Sleep", r.sleepHours.map { "\(Int($0))h \(Int(($0 - floor($0)) * 60))m" })
                Label("From Apple Health", systemImage: "heart.fill").font(.system(size: 12)).foregroundStyle(Theme.glacier)
            }
        }
        .forgeCard(radius: 22)
    }

    private func metricRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textMuted)
            Spacer()
            Text(value ?? "–").font(.mono(13)).foregroundStyle(Theme.text)
        }
        .font(.system(size: 13))
    }

    private func planSection(_ day: WorkoutDay, isToday: Bool) -> some View {
        let next = store.nextSet(in: day)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: isToday ? "Today's plan" : "Next session", detail: "\(day.exercises.count) exercises · ~\(day.estimatedMinutes) min")
            ForEach(Array(day.exercises.enumerated()), id: \.element.id) { index, ex in
                ExerciseRow(index: index + 1, exercise: ex, done: store.completedSetCount(for: ex), isCurrent: next?.0.id == ex.id)
            }
            if isToday {
                Button {
                    store.startSession(for: day)
                    recordingTarget = RecordTarget(day: day)
                } label: {
                    Label(next.map { "Record set \($0.1 + 1) of \($0.0.exercise.name.lowercased())" } ?? "All sets recorded", systemImage: "record.circle")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(next == nil)
                if store.activeSession != nil {
                    Button("Finish workout and plan recovery") { store.finishSession() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.glacier)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
    }
}

struct ExerciseRow: View {
    var index: Int
    var exercise: PlannedExercise
    var done: Int
    var isCurrent: Bool

    var body: some View {
        let first = exercise.sets.first
        HStack(spacing: 14) {
            Text("\(index)").font(.display(22))
                .foregroundStyle(isCurrent ? Theme.ground : Theme.text)
                .frame(width: 44, height: 44)
                .background(isCurrent ? Theme.ember : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.exercise.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                Text("\(exercise.sets.count) × \(first?.targetReps ?? 0) @ \(formatWeight(first?.weightKg)) · rest \(formatDuration(Double(first?.restSeconds ?? 0)))")
                    .font(.mono(12)).foregroundStyle(isCurrent ? Theme.emberSoft : Theme.textMuted)
            }
            Spacer(minLength: 0)
            SetDots(done: done, total: exercise.sets.count)
        }
        .forgeCard(fill: isCurrent ? Theme.emberWash : Theme.surface, stroke: isCurrent ? Theme.ember : Theme.stroke)
    }
}
