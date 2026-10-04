import Foundation

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case quads, hamstrings, glutes, calves, chest, back, lats, shoulders, biceps, triceps, core, hipFlexors

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hipFlexors: return "Hip flexors"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

enum Equipment: String, Codable, CaseIterable {
    case barbell, dumbbell, bodyweight, machine, cable, kettlebell
}

/// An exercise the app can plan and the cloud analyser can recognise.
/// `id` values match the backend's `detectedExercise` ids exactly.
struct Exercise: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let primary: [MuscleGroup]
    let secondary: [MuscleGroup]
    let equipment: Equipment
    /// Camera angle that gives the analyser the clearest view.
    let recommendedCameraAngle: CameraAngle
    let isCompound: Bool

    enum CameraAngle: String, Codable { case side, front, diagonal }

    var allMuscles: [MuscleGroup] { primary + secondary }
}

extension Exercise {
    static let squat = Exercise(id: "squat", name: "Back squat", primary: [.quads, .glutes], secondary: [.hamstrings, .core], equipment: .barbell, recommendedCameraAngle: .side, isCompound: true)
    static let deadlift = Exercise(id: "deadlift", name: "Deadlift", primary: [.hamstrings, .glutes, .back], secondary: [.quads, .core, .lats], equipment: .barbell, recommendedCameraAngle: .side, isCompound: true)
    static let benchPress = Exercise(id: "bench_press", name: "Bench press", primary: [.chest, .triceps], secondary: [.shoulders], equipment: .barbell, recommendedCameraAngle: .side, isCompound: true)
    static let overheadPress = Exercise(id: "overhead_press", name: "Overhead press", primary: [.shoulders, .triceps], secondary: [.core], equipment: .barbell, recommendedCameraAngle: .side, isCompound: true)
    static let barbellRow = Exercise(id: "barbell_row", name: "Barbell row", primary: [.back, .lats], secondary: [.biceps, .hamstrings], equipment: .barbell, recommendedCameraAngle: .side, isCompound: true)
    static let pullUp = Exercise(id: "pull_up", name: "Pull-up", primary: [.lats, .back], secondary: [.biceps], equipment: .bodyweight, recommendedCameraAngle: .front, isCompound: true)
    static let pushUp = Exercise(id: "push_up", name: "Push-up", primary: [.chest, .triceps], secondary: [.shoulders, .core], equipment: .bodyweight, recommendedCameraAngle: .side, isCompound: true)
    static let lunge = Exercise(id: "lunge", name: "Walking lunge", primary: [.quads, .glutes], secondary: [.hamstrings, .hipFlexors], equipment: .dumbbell, recommendedCameraAngle: .side, isCompound: true)
    static let bicepCurl = Exercise(id: "bicep_curl", name: "Biceps curl", primary: [.biceps], secondary: [], equipment: .dumbbell, recommendedCameraAngle: .front, isCompound: false)
    static let romanianDeadlift = Exercise(id: "romanian_deadlift", name: "Romanian deadlift", primary: [.hamstrings, .glutes], secondary: [.back], equipment: .barbell, recommendedCameraAngle: .side, isCompound: true)
    static let hipThrust = Exercise(id: "hip_thrust", name: "Hip thrust", primary: [.glutes], secondary: [.hamstrings], equipment: .barbell, recommendedCameraAngle: .side, isCompound: false)
    static let lateralRaise = Exercise(id: "lateral_raise", name: "Lateral raise", primary: [.shoulders], secondary: [], equipment: .dumbbell, recommendedCameraAngle: .front, isCompound: false)

    static let catalog: [Exercise] = [
        .squat, .deadlift, .benchPress, .overheadPress, .barbellRow, .pullUp,
        .pushUp, .lunge, .bicepCurl, .romanianDeadlift, .hipThrust, .lateralRaise,
    ]

    static func byId(_ id: String) -> Exercise? { catalog.first { $0.id == id } }
}
