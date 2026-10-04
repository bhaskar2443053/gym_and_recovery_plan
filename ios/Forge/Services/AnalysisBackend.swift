import Foundation

/// Where set videos go and where their analysis comes back from.
/// The default implementation is Firebase (Storage + Firestore); `MockAnalysisBackend` runs offline.
protocol AnalysisBackend: AnyObject {
    /// Uploads the video for a set. Progress is reported 0...1.
    func upload(set: SetRecord, bodyMassKg: Double?, progress: @escaping @Sendable (Double) -> Void) async throws
    /// Streams status and analysis updates for a set until it is done or failed.
    func analysisUpdates(for set: SetRecord) -> AsyncStream<(SetRecord.AnalysisStatus, SetAnalysis?)>
}

enum StoragePaths {
    static func video(uid: String, sessionId: String, setId: String) -> String {
        "videos/\(uid)/\(sessionId)/\(setId).mov"
    }
    static func setDocument(uid: String, sessionId: String, setId: String) -> String {
        "users/\(uid)/sessions/\(sessionId)/sets/\(setId)"
    }
}

extension SetRecord {
    /// Custom metadata attached to the uploaded video. Keys match backend/README.md.
    func uploadMetadata(bodyMassKg: Double?) -> [String: String] {
        let iso = ISO8601DateFormatter()
        var meta: [String: String] = [
            "exerciseId": exerciseId,
            "exerciseName": exercise?.name ?? exerciseId,
            "plannedReps": String(plannedReps),
            "loggedWeightKg": loggedWeightKg.map { String($0) } ?? "",
            "setIndex": String(setIndex),
            "startedAt": iso.string(from: startedAt),
            "endedAt": iso.string(from: endedAt),
            "previousSetEndedAt": previousSetEndedAt.map { iso.string(from: $0) } ?? "",
        ]
        if let bodyMassKg { meta["bodyMassKg"] = String(bodyMassKg) }
        if let heartRateAvg { meta["heartRateAvg"] = String(Int(heartRateAvg)) }
        if let heartRateMax { meta["heartRateMax"] = String(Int(heartRateMax)) }
        return meta
    }
}

/// Offline backend for previews, the simulator and running without Firebase configured.
/// Returns a plausible analysis built from what was planned.
final class MockAnalysisBackend: AnalysisBackend {
    func upload(set: SetRecord, bodyMassKg: Double?, progress: @escaping @Sendable (Double) -> Void) async throws {
        for step in 1...10 {
            try await Task.sleep(for: .milliseconds(120))
            progress(Double(step) / 10)
        }
    }

    func analysisUpdates(for set: SetRecord) -> AsyncStream<(SetRecord.AnalysisStatus, SetAnalysis?)> {
        AsyncStream { continuation in
            Task {
                continuation.yield((.processing, nil))
                try? await Task.sleep(for: .seconds(2))
                var analysis = SetAnalysis.sample
                analysis.detectedExercise = set.exerciseId
                analysis.reps = set.plannedReps
                analysis.repTimestamps = (0..<set.plannedReps).map { 3 + Double($0) * 3.4 }
                analysis.estimatedWeightKg = set.loggedWeightKg
                analysis.restBeforeSec = set.restBeforeSeconds
                analysis.setDurationSec = set.endedAt.timeIntervalSince(set.startedAt)
                continuation.yield((.done, analysis))
                continuation.finish()
            }
        }
    }
}
