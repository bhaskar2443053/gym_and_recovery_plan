import Foundation
import Observation

/// App-wide state: profile, plan, sessions and recovery. Persists to a JSON file in Documents.
@MainActor
@Observable
final class AppStore {
    struct Snapshot: Codable {
        var profile: UserProfile?
        var plan: WorkoutPlan?
        var sessions: [WorkoutSession] = []
        var recovery: RecoveryPlan?
        var completedStretchIds: Set<String> = []
    }

    var profile: UserProfile?
    var plan: WorkoutPlan?
    var sessions: [WorkoutSession] = []
    var activeSession: WorkoutSession?
    var recovery: RecoveryPlan?
    var completedStretchIds: Set<String> = []
    var readiness = RecoveryPlanner.Readiness()
    var uploadProgress: [String: Double] = [:]

    let health = HealthKitManager()
    let watch = PhoneWatchConnector()
    let backend: AnalysisBackend
    private let planner = PlanGenerator()
    private let recoveryPlanner = RecoveryPlanner()
    private let fileURL: URL

    init(backend: AnalysisBackend? = nil, fileURL: URL? = nil) {
        #if canImport(FirebaseCore) && canImport(FirebaseStorage) && canImport(FirebaseFirestore) && canImport(FirebaseAuth)
        self.backend = backend ?? FirebaseAnalysisBackend.makeIfConfigured() ?? MockAnalysisBackend()
        #else
        self.backend = backend ?? MockAnalysisBackend()
        #endif
        self.fileURL = fileURL ?? URL.documentsDirectory.appending(path: "forge-state.json")
        load()
        watch.onSetDoneTapped = { [weak self] _ in self?.watchRequestedSetEnd = true }
    }

    /// Set when the Watch's "Set done" is tapped; the record screen observes it and stops recording.
    var watchRequestedSetEnd = false

    var isOnboarded: Bool { profile != nil && plan != nil }

    // MARK: Lifecycle

    func start() async {
        watch.activate()
        try? await health.requestAuthorization()
        readiness = await health.readiness()
        if var profile, let mass = await health.latestBodyMassKg() {
            profile.bodyMassKg = mass
            self.profile = profile
        }
    }

    // MARK: Plan

    func completeOnboarding(with profile: UserProfile) {
        self.profile = profile
        plan = planner.makePlan(for: profile)
        save()
    }

    func regeneratePlan() {
        guard let profile else { return }
        let week = plan?.week(of: .now) ?? 1
        plan = planner.makePlan(for: profile, startDate: plan?.startDate ?? .now, week: week)
        save()
    }

    var todaysWorkout: WorkoutDay? { plan?.day(for: .now) }

    /// Next scheduled workout day, today included.
    var nextWorkout: (day: WorkoutDay, date: Date)? {
        guard let plan else { return nil }
        let cal = Calendar.current
        for offset in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: offset, to: .now), let day = plan.day(for: date) else { continue }
            return (day, date)
        }
        return nil
    }

    // MARK: Sessions

    func startSession(for day: WorkoutDay) {
        if activeSession?.dayId == day.id { return }
        activeSession = WorkoutSession(dayId: day.id, dayName: day.name, startedAt: .now)
    }

    /// Index of the next set to perform for an exercise in the active session.
    func completedSetCount(for exercise: PlannedExercise) -> Int {
        activeSession?.sets.filter { $0.exerciseId == exercise.exercise.id }.count ?? 0
    }

    func nextSet(in day: WorkoutDay) -> (PlannedExercise, Int)? {
        for ex in day.exercises {
            let done = completedSetCount(for: ex)
            if done < ex.sets.count { return (ex, done) }
        }
        return nil
    }

    func notifyWatchSetStarted(_ set: SetRecord, exercise: PlannedExercise) {
        watch.send(.setStarted(.init(setId: set.id, exerciseName: exercise.exercise.name, setIndex: set.setIndex, totalSets: exercise.sets.count, targetReps: set.plannedReps, weightKg: set.loggedWeightKg)))
    }

    /// Saves a recorded set, fetches its heart rate, uploads the video and listens for analysis.
    func addRecordedSet(_ set: SetRecord, restSeconds: Int) {
        guard activeSession != nil else { return }
        watchRequestedSetEnd = false
        activeSession?.sets.append(set)
        watch.send(.setEnded(setId: set.id, restSeconds: restSeconds))
        Task { await self.process(setId: set.id) }
    }

    private func updateSet(_ id: String, _ change: (inout SetRecord) -> Void) {
        guard let idx = activeSession?.sets.firstIndex(where: { $0.id == id }) else {
            // The session may already be finished; update it in history instead.
            for s in sessions.indices {
                if let i = sessions[s].sets.firstIndex(where: { $0.id == id }) { change(&sessions[s].sets[i]); save() }
            }
            return
        }
        change(&activeSession!.sets[idx])
    }

    private func set(_ id: String) -> SetRecord? {
        activeSession?.sets.first { $0.id == id } ?? sessions.lazy.flatMap(\.sets).first { $0.id == id }
    }

    private func process(setId: String) async {
        guard var record = set(setId) else { return }
        if let hr = await health.heartRate(from: record.startedAt, to: record.endedAt) {
            record.heartRateAvg = hr.avg
            record.heartRateMax = hr.max
            updateSet(setId) { $0.heartRateAvg = hr.avg; $0.heartRateMax = hr.max }
        }
        updateSet(setId) { $0.uploadState = .uploading }
        do {
            try await backend.upload(set: record, bodyMassKg: profile?.bodyMassKg) { [weak self] p in
                Task { @MainActor in self?.uploadProgress[setId] = p }
            }
            updateSet(setId) { $0.uploadState = .uploaded; $0.analysisStatus = .processing }
        } catch {
            updateSet(setId) { $0.uploadState = .failed }
            return
        }
        for await (status, analysis) in backend.analysisUpdates(for: record) {
            updateSet(setId) {
                $0.analysisStatus = status
                if let analysis { $0.analysis = analysis }
            }
        }
    }

    func retryUpload(setId: String) {
        Task { await process(setId: setId) }
    }

    func finishSession() {
        guard var session = activeSession else { return }
        session.endedAt = .now
        sessions.insert(session, at: 0)
        activeSession = nil
        watch.send(.workoutEnded)
        if let profile {
            recovery = recoveryPlanner.makePlan(session: session, profile: profile, readiness: readiness, nextHardSessionInHours: hoursUntilNextWorkout())
            completedStretchIds = []
        }
        save()
    }

    func refreshRecovery() {
        guard let profile, let last = sessions.first else { return }
        recovery = recoveryPlanner.makePlan(session: last, profile: profile, readiness: readiness, nextHardSessionInHours: hoursUntilNextWorkout())
        save()
    }

    private func hoursUntilNextWorkout() -> Int {
        guard let plan else { return 48 }
        let cal = Calendar.current
        for offset in 1...7 {
            if let date = cal.date(byAdding: .day, value: offset, to: .now), plan.day(for: date) != nil {
                return offset * 24
            }
        }
        return 72
    }

    func toggleStretch(_ id: String) {
        if completedStretchIds.contains(id) { completedStretchIds.remove(id) } else { completedStretchIds.insert(id) }
        save()
    }

    var recentSets: [SetRecord] {
        (Array((activeSession?.sets ?? []).reversed()) + sessions.flatMap(\.sets)).filter { $0.analysis != nil || $0.analysisStatus == .processing }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder.forge.decode(Snapshot.self, from: data) else { return }
        profile = snap.profile
        plan = snap.plan
        sessions = snap.sessions
        recovery = snap.recovery
        completedStretchIds = snap.completedStretchIds
    }

    func save() {
        let snap = Snapshot(profile: profile, plan: plan, sessions: sessions, recovery: recovery, completedStretchIds: completedStretchIds)
        if let data = try? JSONEncoder.forge.encode(snap) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
