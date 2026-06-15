import Foundation
import WatchConnectivity

@MainActor
final class WatchDistanceSession: NSObject, ObservableObject {
    @Published var distance = "--"
    @Published var route = "--"
    @Published var sensor = "--"
    @Published var linkOK = false
    @Published var status = "Open DigiTape on iPhone"
    @Published var lastUpdated: Date?

    private let session: WCSession?
    private var hasStarted = false

    override init() {
        if WCSession.isSupported() {
            session = WCSession.default
        } else {
            session = nil
        }
        super.init()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        session?.delegate = self
        session?.activate()
        apply(session?.applicationContext ?? [:])
    }

    func apply(_ payload: [String: Any]) {
        guard !payload.isEmpty else { return }
        distance = payload["distance"] as? String ?? distance
        route = payload["route"] as? String ?? route
        sensor = payload["sensor"] as? String ?? sensor
        linkOK = payload["linkOK"] as? Bool ?? linkOK
        status = payload["status"] as? String ?? status
        if let timestamp = payload["updatedAt"] as? TimeInterval {
            lastUpdated = Date(timeIntervalSince1970: timestamp)
        } else {
            lastUpdated = Date()
        }
    }

    func switchRoute() {
        let targetRoute = route.uppercased() == "TX" ? "RX" : "TX"
        status = "Switching to \(targetRoute)"

        guard let session, session.activationState == .activated else {
            status = "Open DigiTape on iPhone"
            return
        }

        let message: [String: Any] = [
            "command": "switchRoute",
            "target": targetRoute
        ]

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.status = "Open DigiTape on iPhone"
                }
            }
        } else {
            session.transferUserInfo(message)
        }
    }
}

extension WatchDistanceSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.apply(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.apply(message)
        }
    }
}
