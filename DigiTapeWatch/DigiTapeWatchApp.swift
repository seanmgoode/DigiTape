import SwiftUI

@main
struct DigiTapeWatchApp: App {
    @StateObject private var session = WatchDistanceSession()

    var body: some Scene {
        WindowGroup {
            WatchDistanceView(session: session)
        }
    }
}
