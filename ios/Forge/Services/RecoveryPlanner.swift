import Foundation

/// Turns a finished session (and the user's physiology) into a recovery plan:
/// workout-specific stretches, protein targets and relaxation such as sauna, massage or meditation.
struct RecoveryPlanner {
    struct Readiness: Equatable {
        var restingHeartRate: Double?
        var hrvMs: Double?
        var sleepHours: Double?
        var baselineRestingHeartRate: Double?
        var baselineHrvMs: Double?

        /// 0-100 readiness score blending HRV, resting HR and sleep against the user's baselines.
        var score: Int {
            var parts: [Double] = []
            if let hrv = hrvMs, let base = baselineHrvMs, base > 0 { parts.append(min(max(hrv / base, 0.5), 1.3) / 1.3) }
            if let rhr = restingHeartRate, let base = baselineRestingHeartRate, rhr > 0 { parts.append(min(max(base / rhr, 0.7), 1.15) / 1.15) }
            if let sleep = sleepHours { parts.append(min(sleep / 8, 1)) }
            guard !parts.isEmpty else { return 70 }
            return Int((parts.reduce(0, +) / Double(parts.count) * 100).rounded())
        }
    }

    static let stretchLibrary: [Stretch] = [
        .init(id: "couch", name: "Couch stretch", targets: [.quads, .hipFlexors], holdSeconds: 45, sets: 2, perSide: true, cue: "Squeeze the glute of the back leg and keep ribs down."),
        .init(id: "pigeon", name: "Pigeon pose", targets: [.glutes], holdSeconds: 60, sets: 2, perSide: true, cue: "Square the hips and fold forward slowly."),
        .init(id: "ham_fold", name: "Seated hamstring fold", targets: [.hamstrings], holdSeconds: 30, sets: 3, perSide: false, cue: "Hinge from the hips with a long spine."),
        .init(id: "calf_wall", name: "Wall calf stretch", targets: [.calves], holdSeconds: 30, sets: 2, perSide: true, cue: "Keep the back heel down and knee straight."),
        .init(id: "doorway_pec", name: "Doorway pec stretch", targets: [.chest, .shoulders], holdSeconds: 30, sets: 2, perSide: true, cue: "Elbow at shoulder height, step through gently."),
        .init(id: "lat_hang", name: "Child's pose lat reach", targets: [.lats, .back], holdSeconds: 45, sets: 2, perSide: false, cue: "Walk the hands to one side to bias each lat."),
        .init(id: "thread_needle", name: "Thread the needle", targets: [.back, .shoulders], holdSeconds: 30, sets: 2, perSide: true, cue: "Rotate through the upper back, not the low back."),
        .init(id: "cross_body", name: "Cross-body shoulder", targets: [.shoulders], holdSeconds: 30, sets: 2, perSide: true, cue: "Pull the arm across without shrugging."),
        .init(id: "overhead_tri", name: "Overhead triceps", targets: [.triceps], holdSeconds: 30, sets: 2, perSide: true, cue: "Keep the elbow pointing up."),
        .init(id: "wall_biceps", name: "Wall biceps stretch", targets: [.biceps], holdSeconds: 30, sets: 2, perSide: true, cue: "Thumb down, turn the chest away from the wall."),
        .init(id: "cobra", name: "Cobra", targets: [.core, .hipFlexors], holdSeconds: 30, sets: 2, perSide: false, cue: "Press up only as far as the hips stay down."),
    ]

    /// Protein: 1.6–2.2 g/kg/day depending on how hard the session was; spread over 4 feedings.
    func nutrition(bodyMassKg: Double, sessionVolumeKg: Double, goal: TrainingGoal) -> NutritionTarget {
        let base: Double = goal == .hypertrophy || goal == .strength ? 1.8 : 1.6
        let hardDayBump = min(sessionVolumeKg / 20_000, 1) * 0.4
        let protein = Int((bodyMassKg * (base + hardDayBump)).rounded())
        let post = min(max(Int((bodyMassKg * 0.4).rounded()), 25), 45)
        let rest = max(protein - post, 0)
        let servings: [NutritionTarget.Serving] = [
            .init(label: "Within 2 h after training", grams: post),
            .init(label: "Next main meal", grams: rest / 3),
            .init(label: "Following meal", grams: rest / 3),
            .init(label: "Before bed (casein, yoghurt)", grams: rest - 2 * (rest / 3)),
        ]
        let carbs = Int((bodyMassKg * (sessionVolumeKg > 10_000 ? 5 : 3.5)).rounded())
        return .init(proteinGrams: protein, servings: servings, waterLiters: (bodyMassKg * 0.035 * 10).rounded() / 10 + 0.5, carbsGrams: carbs)
    }

    func stretches(for load: [MuscleGroup: Double], limit: Int = 4) -> [Stretch] {
        let ranked = load.sorted { $0.value > $1.value }.map(\.key)
        var picked: [Stretch] = []
        for muscle in ranked {
            for stretch in Self.stretchLibrary where stretch.targets.contains(muscle) && !picked.contains(stretch) {
                picked.append(stretch)
                break
            }
            if picked.count == limit { break }
        }
        return picked
    }

    func activities(readiness: Readiness, sessionIntensity: Double, topMuscles: [MuscleGroup], peakHeartRateFraction: Double?) -> [RecoveryActivity] {
        var list: [RecoveryActivity] = []
        let score = readiness.score
        let muscleText = topMuscles.prefix(2).map(\.displayName).joined(separator: " and ").lowercased()

        if !topMuscles.isEmpty {
            list.append(.init(modality: .foamRolling, minutes: 8, detail: "Slow passes on \(muscleText)", reason: "Highest load in today's session."))
        }
        // Heat helps relaxation and perceived soreness; skip if HR is still elevated or readiness very low.
        if score >= 50 {
            list.append(.init(modality: .sauna, minutes: sessionIntensity > 0.7 ? 15 : 20, detail: "80–90°C, 1–2 rounds, hydrate after", reason: "Promotes relaxation and circulation after strength work."))
        }
        if sessionIntensity > 0.8 || (peakHeartRateFraction ?? 0) > 0.9 {
            list.append(.init(modality: .massage, minutes: 30, detail: "Sports massage or percussion gun on \(muscleText)", reason: "Hard session, peak heart rate near max."))
        }
        if score < 60 {
            list.append(.init(modality: .yogaNidra, minutes: 20, detail: "Guided body scan before bed", reason: "Readiness is low; prioritise the nervous system."))
        } else {
            list.append(.init(modality: .meditation, minutes: 10, detail: "Box breathing 4-4-4-4, then quiet sitting", reason: "Brings heart rate down and improves sleep onset."))
        }
        list.append(.init(modality: .walk, minutes: 20, detail: "Easy pace, zone 1", reason: "Light movement clears soreness without adding fatigue."))
        // Cold right after hypertrophy work can blunt adaptation, so only suggest it on low-intensity days.
        if sessionIntensity < 0.5 {
            list.append(.init(modality: .coldPlunge, minutes: 3, detail: "10–15°C", reason: "Low-intensity day, so cold won't blunt muscle gains."))
        }
        return list
    }

    func makePlan(session: WorkoutSession, profile: UserProfile, readiness: Readiness, nextHardSessionInHours: Int = 48) -> RecoveryPlan {
        let load = session.muscleLoad
        let top = load.sorted { $0.value > $1.value }.map(\.key)
        let rpes = session.sets.compactMap { $0.analysis?.estimatedRPE }
        let intensity = rpes.isEmpty ? 0.7 : min((rpes.reduce(0, +) / Double(rpes.count)) / 10, 1)
        let peakHR = session.sets.compactMap(\.heartRateMax).max()
        let peakFraction = peakHR.map { $0 / profile.maxHeartRate }
        let sleep: Double = readiness.score < 60 || intensity > 0.8 ? 8.5 : 8
        let summary = "Focus on \(top.prefix(2).map(\.displayName).joined(separator: " and ").lowercased()). Readiness \(readiness.score)."
        return RecoveryPlan(
            createdAt: .now,
            basedOnSessionId: session.id,
            stretches: stretches(for: load),
            activities: activities(readiness: readiness, sessionIntensity: intensity, topMuscles: top, peakHeartRateFraction: peakFraction),
            nutrition: nutrition(bodyMassKg: profile.bodyMassKg, sessionVolumeKg: session.totalVolumeKg, goal: profile.goal),
            sleepHoursTarget: sleep,
            muscleLoad: load,
            nextHardSessionInHours: nextHardSessionInHours,
            summary: summary
        )
    }
}
