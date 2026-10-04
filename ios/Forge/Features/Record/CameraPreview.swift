import SwiftUI
import AVFoundation
import Vision

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Draws the live Vision skeleton over the camera feed.
struct SkeletonOverlay: View {
    var pose: SetVideoRecorder.PoseFrame?
    var highlight: Color = Theme.ember

    private typealias J = VNHumanBodyPoseObservation.JointName
    private static let bones: [(J, J)] = [
        (.neck, .root), (.leftShoulder, .rightShoulder), (.leftHip, .rightHip),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist), (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.neck, .leftShoulder), (.neck, .rightShoulder), (.root, .leftHip), (.root, .rightHip),
    ]

    var body: some View {
        Canvas { ctx, size in
            guard let joints = pose?.joints else { return }
            // Vision uses a bottom-left origin; flip y.
            func p(_ j: J) -> CGPoint? { joints[j].map { CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height) } }
            var path = Path()
            for (a, b) in Self.bones {
                guard let pa = p(a), let pb = p(b) else { continue }
                path.move(to: pa); path.addLine(to: pb)
            }
            ctx.stroke(path, with: .color(Theme.glacier), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            for point in joints.values {
                let c = CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(Theme.text))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
