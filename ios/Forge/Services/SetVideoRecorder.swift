import AVFoundation
import Vision
import UIKit

/// Records one video per set with AVAssetWriter, and runs on-device Vision body-pose detection
/// on a subset of frames for the live skeleton overlay and a live rep estimate.
/// The authoritative rep count, form score and so on come from the cloud analysis.
final class SetVideoRecorder: NSObject, @unchecked Sendable {
    enum RecorderError: Error { case cameraUnavailable, notAuthorized, writerFailed }

    struct PoseFrame {
        /// Normalised joint positions (Vision coordinates: origin bottom-left).
        var joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    }

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "forge.recorder")

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var frameCounter = 0
    private var outputURL: URL?

    let liveCounter = LiveRepCounter()
    /// Delivered on the main queue.
    var onPose: ((PoseFrame) -> Void)?
    var onLiveRep: ((Int) -> Void)?

    private(set) var isRecording = false

    static func requestPermissions() async -> Bool {
        let video = await AVCaptureDevice.requestAccess(for: .video)
        let audio = await AVCaptureDevice.requestAccess(for: .audio)
        return video && audio
    }

    func configure(position: AVCaptureDevice.Position = .back) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1920x1080
        session.inputs.forEach { session.removeInput($0) }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let videoIn = try? AVCaptureDeviceInput(device: camera), session.canAddInput(videoIn) else {
            throw RecorderError.cameraUnavailable
        }
        session.addInput(videoIn)
        if let mic = AVCaptureDevice.default(for: .audio), let audioIn = try? AVCaptureDeviceInput(device: mic), session.canAddInput(audioIn) {
            session.addInput(audioIn)
        }

        if session.outputs.isEmpty {
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            videoOutput.alwaysDiscardsLateVideoFrames = false
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            audioOutput.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
            if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
        }
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            connection.isVideoMirrored = position == .front
        }
    }

    func startPreview() { queue.async { [session] in if !session.isRunning { session.startRunning() } } }
    func stopPreview() { queue.async { [session] in if session.isRunning { session.stopRunning() } } }

    func startRecording(exerciseId: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("set-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: 1080,
            AVVideoHeightKey: 1920,
        ])
        video.expectsMediaDataInRealTime = true
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 1, AVSampleRateKey: 44_100,
        ])
        audio.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { throw RecorderError.writerFailed }
        writer.add(video)
        if writer.canAdd(audio) { writer.add(audio) }

        queue.sync {
            self.writer = writer
            self.videoInput = video
            self.audioInput = audio
            self.outputURL = url
            self.sessionStarted = false
            self.frameCounter = 0
            self.liveCounter.reset(exerciseId: exerciseId)
            writer.startWriting()
            self.isRecording = true
        }
    }

    /// Finishes the file and returns its URL.
    func stopRecording() async throws -> URL {
        let (writer, url): (AVAssetWriter?, URL?) = queue.sync {
            isRecording = false
            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            return (self.writer, self.outputURL)
        }
        guard let writer, let url else { throw RecorderError.writerFailed }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? RecorderError.writerFailed }
        return url
    }
}

extension SetVideoRecorder: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let isVideo = output === videoOutput
        if isVideo { detectPose(in: sampleBuffer) }

        guard isRecording, let writer, writer.status == .writing else { return }
        if !sessionStarted {
            guard isVideo else { return }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            sessionStarted = true
        }
        if isVideo, let input = videoInput, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        } else if !isVideo, let input = audioInput, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    private func detectPose(in sampleBuffer: CMSampleBuffer) {
        frameCounter += 1
        // ~10 fps of pose detection is plenty for an overlay and keeps the phone cool.
        guard frameCounter % 3 == 0, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let points = try? observation.recognizedPoints(.all) else { return }
        let joints = points.filter { $0.value.confidence > 0.3 }.mapValues { $0.location }
        let frame = PoseFrame(joints: joints)
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let newRep = isRecording ? liveCounter.ingest(frame, at: timestamp) : nil
        DispatchQueue.main.async { [weak self] in
            self?.onPose?(frame)
            if let newRep { self?.onLiveRep?(newRep) }
        }
    }
}

/// A light on-device rep counter using the primary joint angle with hysteresis.
/// Mirrors the backend's approach so the live number usually matches the final analysis.
final class LiveRepCounter {
    private(set) var reps = 0
    private var exerciseId = "squat"
    private var phaseDown = false
    private var smoothed: Double?

    func reset(exerciseId: String) {
        self.exerciseId = exerciseId
        reps = 0
        phaseDown = false
        smoothed = nil
    }

    /// Thresholds (degrees) for "bottom" and "top" of a rep on the tracked joint angle.
    private var thresholds: (bottom: Double, top: Double) {
        switch exerciseId {
        case "bench_press", "push_up", "overhead_press", "pull_up", "bicep_curl", "barbell_row": return (95, 150)
        case "deadlift", "romanian_deadlift", "hip_thrust": return (120, 160)
        case "lateral_raise": return (30, 70)
        default: return (110, 160)
        }
    }

    /// Returns the new rep count when a rep completes.
    func ingest(_ frame: SetVideoRecorder.PoseFrame, at time: Double) -> Int? {
        guard let angle = primaryAngle(frame) else { return nil }
        let s = smoothed.map { $0 * 0.6 + angle * 0.4 } ?? angle
        smoothed = s
        let (bottom, top) = thresholds
        let inverted = exerciseId == "lateral_raise" // raise: rep peaks at a large angle
        let atBottom = inverted ? s > top : s < bottom
        let atTop = inverted ? s < bottom : s > top
        if atBottom { phaseDown = true }
        if phaseDown && atTop {
            phaseDown = false
            reps += 1
            return reps
        }
        return nil
    }

    private func primaryAngle(_ f: SetVideoRecorder.PoseFrame) -> Double? {
        typealias J = VNHumanBodyPoseObservation.JointName
        func angle(_ a: J, _ b: J, _ c: J) -> Double? {
            guard let pa = f.joints[a], let pb = f.joints[b], let pc = f.joints[c] else { return nil }
            let v1 = CGVector(dx: pa.x - pb.x, dy: pa.y - pb.y), v2 = CGVector(dx: pc.x - pb.x, dy: pc.y - pb.y)
            let dot = v1.dx * v2.dx + v1.dy * v2.dy
            let mag = hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy)
            guard mag > 0 else { return nil }
            let cosine = Swift.max(-1.0, Swift.min(1.0, Double(dot / mag)))
            return Foundation.acos(cosine) * 180 / Double.pi
        }
        func either(_ l: (J, J, J), _ r: (J, J, J)) -> Double? {
            angle(l.0, l.1, l.2) ?? angle(r.0, r.1, r.2)
        }
        switch exerciseId {
        case "bench_press", "push_up", "overhead_press", "pull_up", "bicep_curl", "barbell_row":
            return either((.leftShoulder, .leftElbow, .leftWrist), (.rightShoulder, .rightElbow, .rightWrist))
        case "deadlift", "romanian_deadlift", "hip_thrust":
            return either((.leftShoulder, .leftHip, .leftKnee), (.rightShoulder, .rightHip, .rightKnee))
        case "lateral_raise":
            return either((.leftHip, .leftShoulder, .leftElbow), (.rightHip, .rightShoulder, .rightElbow))
        default:
            return either((.leftHip, .leftKnee, .leftAnkle), (.rightHip, .rightKnee, .rightAnkle))
        }
    }
}
