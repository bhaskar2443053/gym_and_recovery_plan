import SwiftUI

@main
struct ForgeWatchApp: App {
    @State private var workout = WatchWorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchWorkoutView()
                .environment(workout)
                .task { await workout.activate() }
        }
    }
}
