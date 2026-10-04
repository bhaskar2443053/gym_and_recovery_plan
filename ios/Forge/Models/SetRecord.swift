import Foundation

/// What actually happened for one performed set, including its video and cloud analysis.
struct SetRecord: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var sessionId: String
    var exerciseId: String
    var setIndex: Int
    var plannedReps: Int
    var loggedWeightKg: Double?
    var startedAt: Date
    var endedAt: Date
    var previousSetEndedAt: Date?
    var localVideoURL: URL?
    var heartRateAvg: Double?
    var heartRateMax: Double?
    var uploadState: UploadState = .pending
    var analysisStatus: AnalysisStatus = .notStarted
    var analysis: SetAnalysis?

    enum UploadState: String, Codable { case pending, uploading, uploaded, failed }
    enum AnalysisStatus: String, Codable { case notStarted, processing, done, failed }

    var restBeforeSeconds: Double? {
        previousSetEndedAt.map { startedAt.timeIntervalSince($0) }
    }

    var exercise: Exercise? { Exercise.byId(exerciseId) }
}

struct WorkoutSession: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var dayId: UUID
    var dayName: String
    var startedAt: Date
    var endedAt: Date?
    var sets: [SetRecord] = []

    var totalVolumeKg: Double {
        sets.reduce(0) { total, set in
            let reps = Double(set.analysis?.reps ?? set.plannedReps)
            return total + reps * (set.analysis?.estimatedWeightKg ?? set.loggedWeightKg ?? 0)
        }
    }

    /// Volume per muscle, primary muscles counted fully and secondary at half.
    var muscleLoad: [MuscleGroup: Double] {
        var load: [MuscleGroup: Double] = [:]
        for set in sets {
            guard let ex = set.exercise else { continue }
            let reps = Double(set.analysis?.reps ?? set.plannedReps)
            let weight = set.analysis?.estimatedWeightKg ?? set.loggedWeightKg ?? 20
            let volume = reps * weight
            ex.primary.forEach { load[$0, default: 0] += volume }
            ex.secondary.forEach { load[$0, default: 0] += volume * 0.5 }
        }
        return load
    }
}
