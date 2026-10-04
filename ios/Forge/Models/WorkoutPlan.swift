import Foundation

enum TrainingGoal: String, Codable, CaseIterable, Identifiable {
    case strength, hypertrophy, endurance, generalFitness
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .hypertrophy: return "Muscle growth"
        case .endurance: return "Endurance"
        case .generalFitness: return "General fitness"
        }
    }
}

enum ExperienceLevel: String, Codable, CaseIterable, Identifiable {
    case beginner, intermediate, advanced
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct UserProfile: Codable, Equatable {
    var name: String = ""
    var bodyMassKg: Double = 75
    var goal: TrainingGoal = .hypertrophy
    var experience: ExperienceLevel = .intermediate
    var daysPerWeek: Int = 4
    var sessionMinutes: Int = 60
    var age: Int = 30
    /// Known or estimated one-rep maxes by exercise id, used to set working weights.
    var oneRepMaxKg: [String: Double] = [:]

    var maxHeartRate: Double { 208 - 0.7 * Double(age) }
}

/// One prescribed set in a planned workout.
struct PlannedSet: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var targetReps: Int
    var weightKg: Double?
    /// Target rest after this set, seconds.
    var restSeconds: Int
}

struct PlannedExercise: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var exercise: Exercise
    var sets: [PlannedSet]
    var notes: String?
}

struct WorkoutDay: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var weekday: Int // 1 = Sunday ... 7 = Saturday, Calendar convention
    var exercises: [PlannedExercise]

    var estimatedMinutes: Int {
        let seconds = exercises.flatMap(\.sets).reduce(0) { $0 + $1.restSeconds + $1.targetReps * 4 + 15 }
        return Int((Double(seconds) / 60).rounded())
    }

    var musclesWorked: Set<MuscleGroup> {
        Set(exercises.flatMap { $0.exercise.allMuscles })
    }
}

struct WorkoutPlan: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var goal: TrainingGoal
    var weeks: Int
    var startDate: Date
    var days: [WorkoutDay]

    func day(for date: Date, calendar: Calendar = .current) -> WorkoutDay? {
        let weekday = calendar.component(.weekday, from: date)
        return days.first { $0.weekday == weekday }
    }

    func week(of date: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: calendar.startOfDay(for: date)).day ?? 0
        return min(max(days / 7 + 1, 1), weeks)
    }
}
