import Foundation
import WatchConnectivity

/// iPhone side of the Watch link: tells the Watch about sets and receives live heart rate and taps.
@MainActor
@Observable
final class PhoneWatchConnector: NSObject {
    private(set) var isReachable = false
    private(set) var isPaired = false
    private(set) var latestMetrics: WatchMessage.LiveMetrics?

    /// Called when the user taps "Set done" on the Watch.
    var onSetDoneTapped: ((String) -> Void)?

    private var session: WCSession? { WCSession.isSupported() ? .default : nil }

    func activate() {
        session?.delegate = self
        session?.activate()
    }

    func send(_ message: WatchMessage) {
        guard let session, session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message.encoded(), replyHandler: nil)
        } else {
            // Queued and delivered when the Watch app next wakes.
            session.transferUserInfo(message.encoded())
        }
    }

    private func handle(_ message: WatchMessage) {
        switch message {
        case .liveMetrics(let metrics): latestMetrics = metrics
        case .setDoneTapped(let setId): onSetDoneTapped?(setId)
        default: break
        }
    }
}

extension PhoneWatchConnector: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let paired = session.isPaired, reachable = session.isReachable
        Task { @MainActor in
            self.isPaired = paired
            self.isReachable = reachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let decoded = WatchMessage(dictionary: message) else { return }
        Task { @MainActor in self.handle(decoded) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let decoded = WatchMessage(dictionary: userInfo) else { return }
        Task { @MainActor in self.handle(decoded) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
