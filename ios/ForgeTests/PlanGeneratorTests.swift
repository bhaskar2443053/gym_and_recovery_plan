import XCTest
@testable import Forge

final class PlanGeneratorTests: XCTestCase {
    let generator = PlanGenerator()

    func testFourDayPlanUsesUpperLowerSplit() {
        var profile = UserProfile()
        profile.daysPerWeek = 4
        let plan = generator.makePlan(for: profile)
        XCTAssertEqual(plan.days.map(\.name), ["Lower body A", "Upper body A", "Lower body B", "Upper body B"])
        XCTAssertEqual(Set(plan.days.map(\.weekday)).count, 4)
    }

    func testStrengthPrescribesLowRepsLongRest() {
        let rx = generator.prescription(for: .strength, compound: true, experience: .intermediate)
        XCTAssertEqual(rx.reps, 5)
        XCTAssertGreaterThanOrEqual(rx.restSeconds, 180)
    }

    func testWorkingWeightUsesKnownOneRepMaxAndRoundsToPlates() throws {
        var profile = UserProfile()
        profile.oneRepMaxKg["squat"] = 140
        let weight = try XCTUnwrap(generator.workingWeight(for: .squat, profile: profile, intensity: 0.72, week: 1))
        XCTAssertEqual(weight, 100) // 140 * 0.72 = 100.8 → 100
        XCTAssertEqual(weight.truncatingRemainder(dividingBy: 2.5), 0)
    }

    func testDeloadWeekIsLighter() throws {
        var profile = UserProfile()
        profile.oneRepMaxKg["squat"] = 140
        let week3 = try XCTUnwrap(generator.workingWeight(for: .squat, profile: profile, intensity: 0.72, week: 3))
        let week4 = try XCTUnwrap(generator.workingWeight(for: .squat, profile: profile, intensity: 0.72, week: 4))
        XCTAssertLessThan(week4, week3)
    }

    func testBodyweightExercisesHaveNoWeight() {
        XCTAssertNil(generator.workingWeight(for: .pullUp, profile: UserProfile(), intensity: 0.7, week: 1))
    }

    func testSessionsAreTrimmedToTimeBudget() {
        var profile = UserProfile()
        profile.sessionMinutes = 30
        let plan = generator.makePlan(for: profile)
        for day in plan.days {
            XCTAssertTrue(day.estimatedMinutes <= 30 || day.exercises.allSatisfy { $0.sets.count <= 2 })
        }
    }
}
