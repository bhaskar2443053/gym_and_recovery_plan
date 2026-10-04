import Foundation

/// Messages exchanged between the iPhone app and the Watch app over WatchConnectivity.
/// Encoded as JSON in a `["payload": Data]` dictionary so both sides share one schema.
enum WatchMessage: Codable, Equatable {
    /// Phone → Watch: a set is about to start; the Watch shows it and marks the timeline.
    case setStarted(SetContext)
    /// Phone → Watch: the set finished; the Watch starts the rest timer.
    case setEnded(setId: String, restSeconds: Int)
    /// Watch → Phone: user tapped "Set done" on the wrist.
    case setDoneTapped(setId: String)
    /// Watch → Phone: live metrics sample, sent about once per second during a workout.
    case liveMetrics(LiveMetrics)
    /// Phone → Watch: the session is over.
    case workoutEnded

    struct SetContext: Codable, Equatable {
        var setId: String
        var exerciseName: String
        var setIndex: Int
        var totalSets: Int
        var targetReps: Int
        var weightKg: Double?
    }

    struct LiveMetrics: Codable, Equatable {
        var heartRate: Double
        var activeEnergyKcal: Double
        var elapsedSeconds: Double
        var timestamp: Date
    }

    static let payloadKey = "payload"

    func encoded() -> [String: Any] {
        let data = (try? JSONEncoder.forge.encode(self)) ?? Data()
        return [Self.payloadKey: data]
    }

    init?(dictionary: [String: Any]) {
        guard let data = dictionary[Self.payloadKey] as? Data,
              let message = try? JSONDecoder.forge.decode(WatchMessage.self, from: data) else { return nil }
        self = message
    }
}

/// Heart-rate training zones as a share of max heart rate.
enum HeartRateZone: Int, CaseIterable, Codable {
    case one = 1, two, three, four, five

    static func zone(for bpm: Double, maxHeartRate: Double) -> HeartRateZone {
        let pct = bpm / max(maxHeartRate, 1)
        switch pct {
        case ..<0.6: return .one
        case ..<0.7: return .two
        case ..<0.8: return .three
        case ..<0.9: return .four
        default: return .five
        }
    }
}

extension JSONEncoder {
    static let forge: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let forge: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
