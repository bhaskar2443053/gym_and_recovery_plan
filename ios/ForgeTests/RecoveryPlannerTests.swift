import XCTest
@testable import Forge

final class RecoveryPlannerTests: XCTestCase {
    let planner = RecoveryPlanner()

    private func legSession() -> WorkoutSession {
        var session = WorkoutSession(dayId: UUID(), dayName: "Lower body A", startedAt: .now)
        for i in 0..<4 {
            var set = SetRecord(sessionId: session.id, exerciseId: "squat", setIndex: i, plannedReps: 6, loggedWeightKg: 100, startedAt: .now, endedAt: .now)
            set.analysis = .sample
            session.sets.append(set)
        }
        return session
    }

    func testStretchesTargetTrainedMuscles() {
        let plan = planner.makePlan(session: legSession(), profile: UserProfile(), readiness: .init())
        let targets = Set(plan.stretches.flatMap(\.targets))
        XCTAssertTrue(targets.contains(.quads))
        XCTAssertTrue(targets.contains(.glutes))
        XCTAssertFalse(targets.contains(.biceps))
    }

    func testProteinScalesWithBodyMass() {
        let light = planner.nutrition(bodyMassKg: 60, sessionVolumeKg: 10_000, goal: .hypertrophy)
        let heavy = planner.nutrition(bodyMassKg: 100, sessionVolumeKg: 10_000, goal: .hypertrophy)
        XCTAssertGreaterThan(heavy.proteinGrams, light.proteinGrams)
        XCTAssertEqual(heavy.servings.map(\.grams).reduce(0, +), heavy.proteinGrams)
        XCTAssertTrue((1.6 * 100...2.2 * 100).contains(Double(heavy.proteinGrams)))
    }

    func testLowReadinessSuggestsYogaNidraNotSauna() {
        let tired = RecoveryPlanner.Readiness(restingHeartRate: 80, hrvMs: 25, sleepHours: 3, baselineRestingHeartRate: 55, baselineHrvMs: 70)
        XCTAssertLessThan(tired.score, 50)
        let activities = planner.activities(readiness: tired, sessionIntensity: 0.85, topMuscles: [.quads], peakHeartRateFraction: 0.95).map(\.modality)
        XCTAssertTrue(activities.contains(.yogaNidra))
        XCTAssertFalse(activities.contains(.sauna))
        XCTAssertTrue(activities.contains(.massage))
    }

    func testNoColdPlungeAfterHardSession() {
        let activities = planner.activities(readiness: .init(), sessionIntensity: 0.85, topMuscles: [.quads], peakHeartRateFraction: nil).map(\.modality)
        XCTAssertFalse(activities.contains(.coldPlunge))
    }
}
