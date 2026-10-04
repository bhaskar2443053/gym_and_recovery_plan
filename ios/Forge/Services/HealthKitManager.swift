import Foundation
import HealthKit

/// Reads the Health data Forge uses for readiness and per-set heart rate.
/// Heart rate during a workout is recorded by the Watch app's HKWorkoutSession and
/// synced to the phone's HealthKit store, so the phone can query it by set time range.
@MainActor
final class HealthKitManager {
    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.bodyMass),
            HKQuantityType(.vo2Max),
            HKQuantityType(.oxygenSaturation),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType(),
        ]
    }

    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
    }

    func requestAuthorization() async throws {
        guard Self.isAvailable else { return }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    // MARK: Readiness

    func readiness() async -> RecoveryPlanner.Readiness {
        let now = Date()
        let dayAgo = now.addingTimeInterval(-86_400)
        let monthAgo = now.addingTimeInterval(-30 * 86_400)
        async let rhr = average(.restingHeartRate, unit: .count().unitDivided(by: .minute()), from: dayAgo, to: now)
        async let hrv = average(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: dayAgo, to: now)
        async let rhrBase = average(.restingHeartRate, unit: .count().unitDivided(by: .minute()), from: monthAgo, to: now)
        async let hrvBase = average(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: monthAgo, to: now)
        async let sleep = sleepHours(endingAt: now)
        return await .init(restingHeartRate: rhr, hrvMs: hrv, sleepHours: sleep, baselineRestingHeartRate: rhrBase, baselineHrvMs: hrvBase)
    }

    func latestBodyMassKg() async -> Double? {
        await latest(.bodyMass, unit: .gramUnit(with: .kilo))
    }

    /// Average and max heart rate between two dates, e.g. the span of one set.
    func heartRate(from start: Date, to end: Date) async -> (avg: Double, max: Double)? {
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: [.discreteAverage, .discreteMax]) { _, stats, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                guard let avg = stats?.averageQuantity()?.doubleValue(for: unit),
                      let max = stats?.maximumQuantity()?.doubleValue(for: unit) else {
                    cont.resume(returning: nil); return
                }
                cont.resume(returning: (avg, max))
            }
            store.execute(query)
        }
    }

    // MARK: Helpers

    private func average(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, _ in
                cont.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: HKQuantityType(id), predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Hours asleep in the 24 h before `end`, summing all asleep stages.
    private func sleepHours(endingAt end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: end.addingTimeInterval(-86_400), end: end)
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let seconds = (samples as? [HKCategorySample] ?? [])
                    .filter { asleep.contains($0.value) }
                    .reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: seconds > 0 ? seconds / 3600 : nil)
            }
            store.execute(query)
        }
    }
}
