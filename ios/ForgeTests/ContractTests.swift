import XCTest
@testable import Forge

/// Guards the app ↔ backend contract documented in backend/README.md.
final class ContractTests: XCTestCase {
    func testDecodesBackendAnalysisMap() throws {
        let json = """
        {"detectedExercise":"squat","exerciseConfidence":0.94,"reps":5,"repTimestamps":[2.0,4.5,7.1,9.8,12.6],
         "partialReps":1,"avgRepDurationSec":2.6,"tempo":{"eccentricSec":1.6,"concentricSec":1.0},
         "rangeOfMotionScore":88,"formScore":81,
         "formIssues":[{"code":"knee_valgus","severity":"medium","message":"Knees cave in.","atSec":9.8},
                       {"code":"excessive_lean","severity":"low","message":"Chest drops.","atSec":null}],
         "estimatedWeightKg":100.0,"estimatedRPE":8.0,"velocityLossPct":18.5,"restBeforeSec":150.0,
         "idleSecInVideo":4.1,"setDurationSec":16.0,"framesAnalyzed":240,"poseVisibility":0.91,
         "coachingTip":"Push your knees out."}
        """.data(using: .utf8)!
        let a = try JSONDecoder().decode(SetAnalysis.self, from: json)
        XCTAssertEqual(a.reps, 5)
        XCTAssertEqual(a.formIssues.count, 2)
        XCTAssertNil(a.formIssues[1].atSec)
        XCTAssertEqual(a.detectedExerciseName, "Back squat")
        XCTAssertEqual(a.relativeRepSpeeds.count, 5)
    }

    func testNullableFieldsMayBeNull() throws {
        let json = """
        {"detectedExercise":"pull_up","exerciseConfidence":0.7,"reps":8,"repTimestamps":[],"partialReps":0,
         "avgRepDurationSec":2.0,"tempo":{"eccentricSec":1.0,"concentricSec":1.0},"rangeOfMotionScore":70,
         "formScore":75,"formIssues":[],"estimatedWeightKg":null,"estimatedRPE":null,"velocityLossPct":null,
         "restBeforeSec":null,"idleSecInVideo":0,"setDurationSec":20,"framesAnalyzed":300,"poseVisibility":0.8,
         "coachingTip":""}
        """.data(using: .utf8)!
        let a = try JSONDecoder().decode(SetAnalysis.self, from: json)
        XCTAssertNil(a.estimatedWeightKg)
        XCTAssertNil(a.restBeforeSec)
    }

    func testUploadMetadataKeys() {
        let start = Date(timeIntervalSince1970: 1_000)
        let set = SetRecord(sessionId: "s1", exerciseId: "squat", setIndex: 2, plannedReps: 6, loggedWeightKg: 100,
                            startedAt: start, endedAt: start.addingTimeInterval(30), previousSetEndedAt: start.addingTimeInterval(-150))
        let meta = set.uploadMetadata(bodyMassKg: 80)
        for key in ["exerciseId", "exerciseName", "plannedReps", "loggedWeightKg", "setIndex", "startedAt", "endedAt", "previousSetEndedAt", "bodyMassKg"] {
            XCTAssertNotNil(meta[key], key)
        }
        XCTAssertEqual(StoragePaths.video(uid: "u", sessionId: "s1", setId: set.id), "videos/u/s1/\(set.id).mov")
        XCTAssertEqual(set.restBeforeSeconds, 150)
    }

    func testExerciseIdsMatchBackendList() {
        let backend: Set<String> = ["squat", "deadlift", "bench_press", "overhead_press", "barbell_row", "pull_up", "push_up",
                                    "lunge", "bicep_curl", "romanian_deadlift", "hip_thrust", "lateral_raise"]
        XCTAssertEqual(Set(Exercise.catalog.map(\.id)), backend)
    }

    func testWatchMessageRoundTrip() {
        let msg = WatchMessage.setStarted(.init(setId: "a", exerciseName: "Back squat", setIndex: 0, totalSets: 4, targetReps: 6, weightKg: 100))
        XCTAssertEqual(WatchMessage(dictionary: msg.encoded()), msg)
    }
}
