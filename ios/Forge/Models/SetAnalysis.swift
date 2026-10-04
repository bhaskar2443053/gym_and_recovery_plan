import Foundation

/// Cloud analysis result for one set. Mirrors the `analysis` map the backend writes to
/// Firestore at `users/{uid}/sessions/{sessionId}/sets/{setId}` (see backend/README.md).
struct SetAnalysis: Codable, Equatable {
    var detectedExercise: String
    var exerciseConfidence: Double
    var reps: Int
    var repTimestamps: [Double]
    var partialReps: Int
    var avgRepDurationSec: Double
    var tempo: Tempo
    var rangeOfMotionScore: Int
    var formScore: Int
    var formIssues: [FormIssue]
    var estimatedWeightKg: Double?
    var estimatedRPE: Double?
    var velocityLossPct: Double?
    var restBeforeSec: Double?
    var idleSecInVideo: Double
    var setDurationSec: Double
    var framesAnalyzed: Int
    var poseVisibility: Double
    var coachingTip: String

    struct Tempo: Codable, Equatable {
        var eccentricSec: Double
        var concentricSec: Double
    }

    struct FormIssue: Codable, Equatable, Identifiable {
        var code: String
        var severity: Severity
        var message: String
        var atSec: Double?

        var id: String { "\(code)-\(atSec ?? -1)" }

        enum Severity: String, Codable { case low, medium, high }
    }

    var detectedExerciseName: String {
        Exercise.byId(detectedExercise)?.name ?? "Unrecognised exercise"
    }

    /// Per-rep relative speed (1.0 = first rep) derived from rep spacing, for the velocity chart.
    var relativeRepSpeeds: [Double] {
        guard repTimestamps.count > 1 else { return Array(repeating: 1, count: reps) }
        let gaps = zip(repTimestamps.dropFirst(), repTimestamps).map { $0 - $1 }
        guard let first = gaps.first, first > 0 else { return [] }
        return [1] + gaps.map { first / max($0, 0.01) }
    }
}

extension SetAnalysis {
    static let sample = SetAnalysis(
        detectedExercise: "squat", exerciseConfidence: 0.97, reps: 6,
        repTimestamps: [3.1, 6.4, 9.8, 13.4, 17.2, 21.3], partialReps: 0,
        avgRepDurationSec: 3.0, tempo: .init(eccentricSec: 2.1, concentricSec: 0.9),
        rangeOfMotionScore: 92, formScore: 78,
        formIssues: [
            .init(code: "knee_valgus", severity: .medium, message: "Left knee caves in on the way up. Push knees out over the toes.", atSec: 21.0),
        ],
        estimatedWeightKg: 100, estimatedRPE: 8.5, velocityLossPct: 22,
        restBeforeSec: 161, idleSecInVideo: 5.2, setDurationSec: 28, framesAnalyzed: 420,
        poseVisibility: 0.93, coachingTip: "Drive your knees out as you stand up on the last two reps."
    )
}
