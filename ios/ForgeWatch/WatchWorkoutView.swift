import SwiftUI

private let ember = Color(red: 1, green: 0.478, blue: 0.271)
private let glacier = Color(red: 0.424, green: 0.788, blue: 0.878)
private let heart = Color(red: 1, green: 0.353, blue: 0.431)
private let muted = Color(red: 0.655, green: 0.69, blue: 0.741)

struct WatchWorkoutView: View {
    @Environment(WatchWorkoutManager.self) private var workout

    var body: some View {
        if workout.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                running(now: context.date)
            }
        } else {
            VStack(spacing: 10) {
                Text("FORGE").font(.system(size: 32, weight: .black).width(.compressed)).foregroundStyle(ember)
                Text("Start a set on your iPhone, or begin here.").font(.footnote).foregroundStyle(muted).multilineTextAlignment(.center)
                Button("Start workout") { workout.startWorkout() }.tint(ember)
            }
        }
    }

    private func running(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(workout.currentSet.map { "\($0.exerciseName.uppercased()) \($0.setIndex + 1)/\($0.totalSets)" } ?? "WORKOUT")
                    .font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(ember).lineLimit(1)
                Spacer()
                if let start = workout.startDate {
                    Text(Duration.seconds(now.timeIntervalSince(start)).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 13, design: .monospaced)).foregroundStyle(muted)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Image(systemName: "heart.fill").foregroundStyle(heart)
                Text(workout.heartRate > 0 ? "\(Int(workout.heartRate))" : "--")
                    .font(.system(size: 56, weight: .black).width(.compressed))
                Text("bpm").font(.footnote).foregroundStyle(muted)
            }
            HStack(spacing: 3) {
                ForEach(HeartRateZone.allCases, id: \.self) { z in
                    Capsule().fill(z == workout.zone ? ember : (z.rawValue < workout.zone.rawValue ? glacier.opacity(0.7) : Color.gray.opacity(0.3)))
                        .frame(height: 6)
                }
            }
            if let restEnds = workout.restEndsAt {
                let remaining = max(0, restEnds.timeIntervalSince(now))
                Text(remaining > 0 ? "Rest \(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))" : "Rest over, next set")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(remaining > 0 ? glacier : ember)
            } else {
                Text("Zone \(workout.zone.rawValue) · \(Int(workout.activeEnergy)) kcal").font(.footnote).foregroundStyle(muted)
            }
            Spacer(minLength: 2)
            if workout.currentSet != nil && workout.restEndsAt == nil {
                Button("Set done") { workout.setDoneTapped() }
                    .tint(ember)
            } else {
                Button("End workout", role: .destructive) { workout.endWorkout() }
            }
        }
    }
}
