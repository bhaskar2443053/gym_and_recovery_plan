import Foundation
import HealthKit
import WatchConnectivity
import WatchKit

/// Runs an HKWorkoutSession for strength training so heart rate is sampled continuously,
/// streams live metrics to the phone and shows the current set and rest timer.
@MainActor
@Observable
final class WatchWorkoutManager: NSObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var lastSent = Date.distantPast

    private(set) var isRunning = false
    private(set) var heartRate: Double = 0
    private(set) var activeEnergy: Double = 0
    private(set) var startDate: Date?
    private(set) var currentSet: WatchMessage.SetContext?
    private(set) var restEndsAt: Date?
    var maxHeartRate: Double = 190

    var zone: HeartRateZone { HeartRateZone.zone(for: heartRate, maxHeartRate: maxHeartRate) }

    func activate() async {
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        try? await healthStore.requestAuthorization(toShare: share, read: read)
    }

    func startWorkout() {
        guard !isRunning else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }
            startDate = start
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    func endWorkout() {
        session?.end()
        isRunning = false
        currentSet = nil
        restEndsAt = nil
    }

    func setDoneTapped() {
        guard let set = currentSet else { return }
        WKInterfaceDevice.current().play(.success)
        send(.setDoneTapped(setId: set.setId))
    }

    private func send(_ message: WatchMessage) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message.encoded(), replyHandler: nil)
        } else if case .setDoneTapped = message {
            session.transferUserInfo(message.encoded())
        }
    }

    fileprivate func handle(_ message: WatchMessage) {
        switch message {
        case .setStarted(let context):
            if !isRunning { startWorkout() }
            currentSet = context
            restEndsAt = nil
            WKInterfaceDevice.current().play(.start)
        case .setEnded(_, let rest):
            restEndsAt = Date().addingTimeInterval(Double(rest))
            WKInterfaceDevice.current().play(.stop)
            scheduleRestHaptic(after: rest)
        case .workoutEnded:
            endWorkout()
        default:
            break
        }
    }

    private func scheduleRestHaptic(after seconds: Int) {
        let target = restEndsAt
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if self.restEndsAt == target { WKInterfaceDevice.current().play(.notification) }
        }
    }

    fileprivate func update(from stats: HKStatistics?) {
        guard let stats else { return }
        switch stats.quantityType {
        case HKQuantityType(.heartRate):
            heartRate = stats.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute())) ?? heartRate
        case HKQuantityType(.activeEnergyBurned):
            activeEnergy = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? activeEnergy
        default:
            break
        }
        if Date().timeIntervalSince(lastSent) >= 1, let startDate {
            lastSent = Date()
            send(.liveMetrics(.init(heartRate: heartRate, activeEnergyKcal: activeEnergy, elapsedSeconds: Date().timeIntervalSince(startDate), timestamp: .now)))
        }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        Task { @MainActor in
            guard let builder = self.builder else { return }
            try? await builder.endCollection(at: date)
            _ = try? await builder.finishWorkout()
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let stats = collectedTypes.compactMap { $0 as? HKQuantityType }.map { workoutBuilder.statistics(for: $0) }
        Task { @MainActor in stats.forEach { self.update(from: $0) } }
    }
}

extension WatchWorkoutManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let decoded = WatchMessage(dictionary: message) else { return }
        Task { @MainActor in self.handle(decoded) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let decoded = WatchMessage(dictionary: userInfo) else { return }
        Task { @MainActor in self.handle(decoded) }
    }
}
