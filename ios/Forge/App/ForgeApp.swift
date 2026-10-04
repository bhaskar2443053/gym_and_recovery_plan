import SwiftUI

@main
struct ForgeApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.ember)
                .task { await store.start() }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.isOnboarded {
            TabView {
                TodayView().tabItem { Label("Train", systemImage: "dumbbell") }
                InsightsView().tabItem { Label("Insights", systemImage: "chart.bar") }
                RecoveryView().tabItem { Label("Recover", systemImage: "drop") }
                PlanView().tabItem { Label("Plan", systemImage: "calendar") }
            }
            .toolbarBackground(Theme.ground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        } else {
            OnboardingView()
        }
    }
}
