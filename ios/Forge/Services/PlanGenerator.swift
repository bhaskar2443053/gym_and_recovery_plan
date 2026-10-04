import Foundation

/// Builds a weekly training plan from the user's profile. Pure and deterministic so it is unit-testable.
struct PlanGenerator {
    struct Prescription: Equatable {
        var sets: Int
        var reps: Int
        var intensity: Double // fraction of 1RM
        var restSeconds: Int
    }

    func prescription(for goal: TrainingGoal, compound: Bool, experience: ExperienceLevel) -> Prescription {
        let extraSet = experience == .advanced ? 1 : 0
        switch (goal, compound) {
        case (.strength, true): return .init(sets: 4 + extraSet, reps: 5, intensity: 0.82, restSeconds: 180)
        case (.strength, false): return .init(sets: 3, reps: 8, intensity: 0.70, restSeconds: 90)
        case (.hypertrophy, true): return .init(sets: 3 + extraSet, reps: 8, intensity: 0.72, restSeconds: 150)
        case (.hypertrophy, false): return .init(sets: 3, reps: 12, intensity: 0.62, restSeconds: 75)
        case (.endurance, _): return .init(sets: 3, reps: 15, intensity: 0.55, restSeconds: 60)
        case (.generalFitness, true): return .init(sets: 3, reps: 10, intensity: 0.65, restSeconds: 120)
        case (.generalFitness, false): return .init(sets: 2 + extraSet, reps: 12, intensity: 0.60, restSeconds: 75)
        }
    }

    /// Split templates by training days per week.
    func split(daysPerWeek: Int) -> [(name: String, exercises: [Exercise])] {
        let fullA: [Exercise] = [.squat, .benchPress, .barbellRow, .lateralRaise]
        let fullB: [Exercise] = [.deadlift, .overheadPress, .pullUp, .lunge]
        let fullC: [Exercise] = [.romanianDeadlift, .pushUp, .barbellRow, .bicepCurl]
        let lowerA: [Exercise] = [.squat, .romanianDeadlift, .lunge, .hipThrust]
        let upperA: [Exercise] = [.benchPress, .barbellRow, .overheadPress, .bicepCurl]
        let lowerB: [Exercise] = [.deadlift, .squat, .hipThrust, .lunge]
        let upperB: [Exercise] = [.overheadPress, .pullUp, .pushUp, .lateralRaise]
        switch daysPerWeek {
        case ...2: return [("Full body A", fullA), ("Full body B", fullB)]
        case 3: return [("Full body A", fullA), ("Full body B", fullB), ("Full body C", fullC)]
        case 4: return [("Lower body A", lowerA), ("Upper body A", upperA), ("Lower body B", lowerB), ("Upper body B", upperB)]
        default: return [("Lower body A", lowerA), ("Upper body A", upperA), ("Full body C", fullC), ("Lower body B", lowerB), ("Upper body B", upperB)]
        }
    }

    /// Spreads training days across the week, avoiding back-to-back days where possible.
    func weekdays(for count: Int) -> [Int] {
        switch count {
        case ...1: return [2]
        case 2: return [2, 5]
        case 3: return [2, 4, 6]
        case 4: return [2, 3, 5, 6]
        case 5: return [2, 3, 4, 6, 7]
        default: return [2, 3, 4, 5, 6, 7]
        }
    }

    /// Fallback 1RM when the user hasn't entered one: body-mass multiples by experience.
    func estimatedOneRepMax(for exercise: Exercise, profile: UserProfile) -> Double? {
        guard exercise.equipment != .bodyweight else { return nil }
        let ratios: [String: Double] = [
            "squat": 1.25, "deadlift": 1.5, "bench_press": 0.9, "overhead_press": 0.55,
            "barbell_row": 0.75, "lunge": 0.35, "bicep_curl": 0.18, "romanian_deadlift": 1.0,
            "hip_thrust": 1.3, "lateral_raise": 0.1,
        ]
        let level: Double = switch profile.experience {
        case .beginner: 0.7
        case .intermediate: 1.0
        case .advanced: 1.35
        }
        return ratios[exercise.id].map { $0 * profile.bodyMassKg * level }
    }

    func workingWeight(for exercise: Exercise, profile: UserProfile, intensity: Double, week: Int) -> Double? {
        guard let oneRM = profile.oneRepMaxKg[exercise.id] ?? estimatedOneRepMax(for: exercise, profile: profile) else { return nil }
        // Simple linear progression: +2.5% intensity per week, deload every 4th week.
        let progression = week % 4 == 0 ? -0.1 : 0.025 * Double((week - 1) % 4)
        let raw = oneRM * (intensity + progression)
        let increment = exercise.equipment == .dumbbell ? 2.0 : 2.5
        return max(increment, (raw / increment).rounded() * increment)
    }

    func makePlan(for profile: UserProfile, startDate: Date = .now, weeks: Int = 8, week: Int = 1) -> WorkoutPlan {
        let template = split(daysPerWeek: profile.daysPerWeek)
        let days = zip(template, weekdays(for: template.count)).map { entry, weekday in
            WorkoutDay(name: entry.name, weekday: weekday, exercises: entry.exercises.map { ex in
                let rx = prescription(for: profile.goal, compound: ex.isCompound, experience: profile.experience)
                let weight = workingWeight(for: ex, profile: profile, intensity: rx.intensity, week: week)
                let sets = (0..<rx.sets).map { _ in PlannedSet(targetReps: rx.reps, weightKg: weight, restSeconds: rx.restSeconds) }
                return PlannedExercise(exercise: ex, sets: sets)
            })
        }
        let trimmed = days.map { trim($0, toMinutes: profile.sessionMinutes) }
        return WorkoutPlan(name: "\(profile.goal.displayName) · \(profile.daysPerWeek) days", goal: profile.goal, weeks: weeks, startDate: startDate, days: trimmed)
    }

    /// Drops trailing accessory sets until the session fits the user's time budget.
    func trim(_ day: WorkoutDay, toMinutes limit: Int) -> WorkoutDay {
        var day = day
        while day.estimatedMinutes > limit, let idx = day.exercises.lastIndex(where: { $0.sets.count > 2 }) {
            day.exercises[idx].sets.removeLast()
        }
        return day
    }
}
