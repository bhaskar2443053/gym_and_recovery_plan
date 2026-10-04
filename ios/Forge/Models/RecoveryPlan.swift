import Foundation

struct Stretch: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var targets: [MuscleGroup]
    var holdSeconds: Int
    var sets: Int
    var perSide: Bool
    var cue: String
}

enum RecoveryModality: String, Codable, CaseIterable, Identifiable {
    case sauna, coldPlunge, massage, foamRolling, meditation, breathwork, walk, yogaNidra
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .sauna: return "Sauna"
        case .coldPlunge: return "Cold plunge"
        case .massage: return "Massage"
        case .foamRolling: return "Foam roll"
        case .meditation: return "Meditate"
        case .breathwork: return "Breathwork"
        case .walk: return "Easy walk"
        case .yogaNidra: return "Yoga nidra"
        }
    }
    var systemImage: String {
        switch self {
        case .sauna: return "flame"
        case .coldPlunge: return "snowflake"
        case .massage: return "hand.raised"
        case .foamRolling: return "cylinder"
        case .meditation: return "figure.mind.and.body"
        case .breathwork: return "wind"
        case .walk: return "figure.walk"
        case .yogaNidra: return "moon.zzz"
        }
    }
}

struct RecoveryActivity: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var modality: RecoveryModality
    var minutes: Int
    var detail: String
    var reason: String
}

struct NutritionTarget: Codable, Equatable {
    var proteinGrams: Int
    /// Suggested protein servings spread through the day.
    var servings: [Serving]
    var waterLiters: Double
    var carbsGrams: Int

    struct Serving: Codable, Equatable, Hashable {
        var label: String
        var grams: Int
    }
}

struct RecoveryPlan: Codable, Equatable {
    var createdAt: Date
    var basedOnSessionId: String?
    var stretches: [Stretch]
    var activities: [RecoveryActivity]
    var nutrition: NutritionTarget
    var sleepHoursTarget: Double
    var muscleLoad: [MuscleGroup: Double]
    var nextHardSessionInHours: Int
    var summary: String
}
