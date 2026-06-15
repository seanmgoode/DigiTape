import Foundation
import WatchConnectivity

@MainActor
final class DigiTapeWatchBridge: NSObject, ObservableObject {
    static let shared = DigiTapeWatchBridge()

    private let session: WCSession?
    private var lastPayload: [String: Any] = [:]
    var onSwitchRoute: (() -> Void)?

    private override init() {
        if WCSession.isSupported() {
            session = WCSession.default
        } else {
            session = nil
        }
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func activate() {
        session?.activate()
    }

    func publish(distance: String, route: String, sensor: String, linkOK: Bool, status: String) {
        let payload: [String: Any] = [
            "distance": distance,
            "route": route,
            "sensor": sensor,
            "linkOK": linkOK,
            "status": status,
            "updatedAt": Date().timeIntervalSince1970
        ]

        guard NSDictionary(dictionary: payload) != NSDictionary(dictionary: lastPayload) else { return }
        lastPayload = payload

        guard let session, session.activationState == .activated else { return }
        guard session.isPaired, session.isWatchAppInstalled else { return }

        do {
            try session.updateApplicationContext(payload)
        } catch {
            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil)
            }
        }
    }
}

extension DigiTapeWatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleWatchCommand(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleWatchCommand(userInfo)
    }

    private nonisolated func handleWatchCommand(_ message: [String: Any]) {
        guard message["command"] as? String == "switchRoute" else { return }
        Task { @MainActor in
            self.onSwitchRoute?()
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
