import SwiftUI

struct WatchDistanceView: View {
    @ObservedObject var session: WatchDistanceSession

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(session.linkOK ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(sourceLabel)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                Spacer(minLength: 0)
                Button {
                    session.switchRoute()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9, weight: .bold))
                        Text(nextRoute)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.18), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.green.opacity(0.55), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            Text(session.distance)
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .minimumScaleFactor(0.48)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Text(session.linkOK ? "LIVE" : session.status.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(session.linkOK ? .green : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .containerBackground(.black, for: .navigation)
        .task {
            session.start()
        }
    }

    private var sourceLabel: String {
        session.sensor.uppercased() == "TAG" ? "TAG" : session.route
    }

    private var nextRoute: String {
        session.route.uppercased() == "TX" ? "RX" : "TX"
    }
}

#Preview {
    let session = WatchDistanceSession()
    session.distance = "12' 8\""
    session.route = "TX"
    session.sensor = "TAG"
    session.linkOK = true
    session.status = "Live"
    return WatchDistanceView(session: session)
}
