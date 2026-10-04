import SwiftUI

/// Full-screen camera flow for a workout: record a set, rest, record the next.
struct RecordSetView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: WorkoutDay

    enum Phase: Equatable { case setup, ready, recording(started: Date), resting(until: Date), finished }

    @State private var recorder = SetVideoRecorder()
    @State private var phase: Phase = .setup
    @State private var pose: SetVideoRecorder.PoseFrame?
    @State private var liveReps = 0
    @State private var weightKg: Double?
    @State private var lastSetEndedAt: Date?
    @State private var errorText: String?
    @State private var useFrontCamera = false

    private var current: (PlannedExercise, Int)? { store.nextSet(in: day) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: recorder.session).ignoresSafeArea()
            SkeletonOverlay(pose: pose).ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                if case let (ex, index)? = current {
                    Text("\(ex.exercise.name) · set \(index + 1) of \(ex.sets.count) · \(formatWeight(weightKg ?? ex.sets[index].weightKg))")
                        .eyebrow().foregroundStyle(Color.white.opacity(0.75)).padding(.top, 14)
                    if phase == .ready {
                        Text("Film from the \(ex.exercise.recommendedCameraAngle.rawValue), whole body in frame")
                            .font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.7)).padding(.top, 4)
                    }
                }
                Spacer()
                centerContent
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                controls
            }
        }
        .task { await setUp() }
        .onDisappear { recorder.stopPreview() }
        .onChange(of: store.watchRequestedSetEnd) { _, requested in
            if requested, case .recording = phase { Task { await stop() } }
        }
        .statusBarHidden()
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.black.opacity(0.5), in: Circle())
            }
            .accessibilityLabel("Close")
            Spacer()
            if case .recording(let started) = phase {
                TimelineView(.periodic(from: started, by: 1)) { context in
                    HStack(spacing: 8) {
                        Circle().fill(Theme.record).frame(width: 8, height: 8)
                        Text("REC \(formatDuration(context.date.timeIntervalSince(started)))").font(.mono(13))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 40).background(.black.opacity(0.5), in: Capsule())
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "heart.fill").foregroundStyle(Theme.heart)
                Text(store.watch.latestMetrics.map { "\(Int($0.heartRate))" } ?? "--").font(.mono(13))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: 40).background(.black.opacity(0.5), in: Capsule())
            .accessibilityLabel("Heart rate from Apple Watch")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var centerContent: some View {
        switch phase {
        case .recording:
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(liveReps)").font(.display(120)).foregroundStyle(.white).contentTransition(.numericText())
                    Text("OF \(current.map { $0.0.sets[$0.1].targetReps } ?? 0) REPS · LIVE").font(.mono(12)).foregroundStyle(Color.white.opacity(0.7))
                }
                Spacer()
            }
        case .resting(let until):
            RestCard(until: until, lastSet: store.activeSession?.sets.last, uploadProgress: store.activeSession?.sets.last.flatMap { store.uploadProgress[$0.id] }) {
                phase = .ready
            }
        case .finished:
            VStack(spacing: 12) {
                Text("WORKOUT COMPLETE").font(.display(40)).foregroundStyle(.white)
                Text("Your sets are being analysed. Recovery is ready in the Recover tab.").multilineTextAlignment(.center).foregroundStyle(Color.white.opacity(0.75))
                Button("Finish and plan recovery") {
                    store.finishSession()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.glacier))
            }
        case .setup:
            ProgressView().tint(.white)
        case .ready:
            if let errorText { Text(errorText).foregroundStyle(Theme.emberSoft).multilineTextAlignment(.center) }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if phase != .finished {
            HStack {
                Button {
                    useFrontCamera.toggle()
                    try? recorder.configure(position: useFrontCamera ? .front : .back)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera").font(.system(size: 20)).foregroundStyle(.white)
                        .frame(width: 52, height: 52).background(Theme.surface, in: Circle())
                }
                .accessibilityLabel("Switch camera")
                .disabled(isRecording)

                Spacer()
                Button {
                    if isRecording { Task { await stop() } } else { start() }
                } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 84, height: 84)
                        RoundedRectangle(cornerRadius: isRecording ? 8 : 34)
                            .fill(Theme.record)
                            .frame(width: isRecording ? 34 : 68, height: isRecording ? 34 : 68)
                    }
                    .animation(.spring(duration: 0.25), value: isRecording)
                }
                .accessibilityLabel(isRecording ? "Finish set" : "Start set")
                .disabled(current == nil || phase == .setup)

                Spacer()
                weightControl
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(Theme.ground.opacity(0.92), in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        }
    }

    private var weightControl: some View {
        Menu {
            ForEach([-5.0, -2.5, 2.5, 5.0], id: \.self) { delta in
                Button(delta > 0 ? "+\(formatWeight(delta))" : "−\(formatWeight(-delta))") {
                    let base = weightKg ?? current.flatMap { $0.0.sets[$0.1].weightKg } ?? 0
                    weightKg = max(0, base + delta)
                }
            }
        } label: {
            VStack(spacing: 2) {
                Text(formatWeight(weightKg ?? current.flatMap { $0.0.sets[$0.1].weightKg })).font(.mono(14)).foregroundStyle(.white)
                Text("weight").font(.system(size: 10)).foregroundStyle(Theme.textMuted)
            }
            .frame(width: 52, height: 52)
        }
        .accessibilityLabel("Adjust weight")
        .disabled(isRecording)
    }

    private var isRecording: Bool { if case .recording = phase { true } else { false } }

    // MARK: Actions

    private func setUp() async {
        guard await SetVideoRecorder.requestPermissions() else {
            errorText = "Camera and microphone access are needed to record sets. Turn them on in Settings."
            phase = .ready
            return
        }
        do {
            try recorder.configure()
            recorder.onPose = { pose = $0 }
            recorder.onLiveRep = { reps in withAnimation { liveReps = reps } }
            recorder.startPreview()
        } catch {
            errorText = "No camera available on this device."
        }
        lastSetEndedAt = store.activeSession?.sets.last?.endedAt
        phase = current == nil ? .finished : .ready
    }

    private func start() {
        guard case let (ex, index)? = current else { return }
        do {
            try recorder.startRecording(exerciseId: ex.exercise.id)
            liveReps = 0
            let started = Date()
            phase = .recording(started: started)
            let preview = SetRecord(sessionId: store.activeSession?.id ?? "", exerciseId: ex.exercise.id, setIndex: index, plannedReps: ex.sets[index].targetReps, loggedWeightKg: weightKg ?? ex.sets[index].weightKg, startedAt: started, endedAt: started)
            store.notifyWatchSetStarted(preview, exercise: ex)
        } catch {
            errorText = "Couldn't start recording. Try again."
        }
    }

    private func stop() async {
        guard case .recording(let started) = phase, case let (ex, index)? = current, let session = store.activeSession else { return }
        let planned = ex.sets[index]
        do {
            let url = try await recorder.stopRecording()
            let ended = Date()
            let record = SetRecord(
                sessionId: session.id, exerciseId: ex.exercise.id, setIndex: index,
                plannedReps: planned.targetReps, loggedWeightKg: weightKg ?? planned.weightKg,
                startedAt: started, endedAt: ended, previousSetEndedAt: lastSetEndedAt, localVideoURL: url
            )
            store.addRecordedSet(record, restSeconds: planned.restSeconds)
            lastSetEndedAt = ended
            weightKg = nil
            phase = store.nextSet(in: day) == nil ? .finished : .resting(until: ended.addingTimeInterval(Double(planned.restSeconds)))
        } catch {
            errorText = "Recording failed to save. Record the set again."
            phase = .ready
        }
    }
}

private struct RestCard: View {
    var until: Date
    var lastSet: SetRecord?
    var uploadProgress: Double?
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, until.timeIntervalSince(context.date))
                VStack(spacing: 2) {
                    Text("REST").eyebrow()
                    Text(formatDuration(remaining)).font(.display(88)).foregroundStyle(remaining == 0 ? Theme.good : .white)
                        .contentTransition(.numericText(countsDown: true))
                }
            }
            if let lastSet { LastSetStatus(set: lastSet, progress: uploadProgress) }
            Button("Ready for next set", action: onSkip).buttonStyle(PrimaryButtonStyle())
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct LastSetStatus: View {
    var set: SetRecord
    var progress: Double?

    var body: some View {
        HStack(spacing: 12) {
            switch (set.uploadState, set.analysisStatus) {
            case (.uploading, _), (.pending, _):
                ProgressView(value: progress ?? 0).tint(Theme.glacier)
                Text("Uploading").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
            case (.failed, _):
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.emberSoft)
                Text("Upload failed. It will retry from Insights.").font(.system(size: 13))
            case (_, .done):
                if let a = set.analysis {
                    Pill(text: "\(a.reps) reps", fg: Theme.text, bg: Theme.surfaceRaised)
                    Pill(text: "Form \(a.formScore)", fg: a.formScore >= 85 ? Theme.good : Theme.emberSoft, bg: Theme.surfaceRaised)
                    Text(a.coachingTip).font(.system(size: 12)).foregroundStyle(Theme.textMuted).lineLimit(2)
                }
            default:
                ProgressView().tint(Theme.glacier)
                Text("Analysing last set").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
