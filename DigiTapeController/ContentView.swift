import SwiftUI
import UIKit

enum RXScreen: String, CaseIterable {
    case home
    case voltage
    case menu
    case offset
    case mode
    case tag
    case diagnostics
    case about
}

struct ContentView: View {
    @StateObject private var ble = DigiTapeBLEManager()
    @StateObject private var watchBridge = DigiTapeWatchBridge.shared

    var body: some View {
        RXConsoleView(ble: ble)
            .onAppear {
                watchBridge.activate()
                watchBridge.onSwitchRoute = {
                    ble.switchConnectionRoute()
                    publishWatchDistance()
                }
                ble.checkCloudFirmwareIfNeeded()
                publishWatchDistance()
            }
            .onChange(of: ble.packetCounter) { _, _ in publishWatchDistance() }
            .onChange(of: ble.connectionRoute) { _, _ in publishWatchDistance() }
            .onChange(of: ble.sensorType) { _, _ in publishWatchDistance() }
            .onChange(of: ble.isConnected) { _, _ in publishWatchDistance() }
            .onChange(of: ble.errorFlag) { _, _ in publishWatchDistance() }
            .onChange(of: ble.offsetInches) { _, _ in publishWatchDistance() }
            .onChange(of: ble.emulatorMode) { _, _ in publishWatchDistance() }
    }

    private func publishWatchDistance() {
        watchBridge.publish(
            distance: ble.displayDistance,
            route: ble.connectionRoute,
            sensor: ble.sensorType.label,
            linkOK: ble.linkOK,
            status: ble.status
        )
    }
}

struct RXConsoleView: View {
    @ObservedObject var ble: DigiTapeBLEManager
    @State private var screen: RXScreen = .home
    @State private var menuIndex = 0
    @State private var sourceIsTag = false
    @State private var forceTXSensorLabel = false
    @State private var requestedAutoConnect = false
    @State private var activePanel: HomePanel?

    private let menuItems: [(String, RXScreen)] = [
        ("Offset", .offset),
        ("Mode", .mode),
        ("Tag", .tag),
        ("Diagnostics", .diagnostics),
        ("About", .about)
    ]

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            Group {
                if landscape {
                    HStack(spacing: 14) {
                        lcd
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        landscapeControls
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                } else {
                    VStack(spacing: 10) {
                        lcd
                            .padding(.horizontal, -8)
                        controlRow
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 10)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color(.systemBackground))
        .onAppear { autoConnectIfNeeded() }
        .onChange(of: ble.isBluetoothReady) { _, _ in autoConnectIfNeeded() }
        .fullScreenCover(item: $activePanel) { panel in
            switch panel {
            case .diagnostics:
                DiagnosticsView(ble: ble)
                    .interactiveDismissDisabled()
            }
        }
    }

    private var lcd: some View {
        OLEDDisplay(
            ble: ble,
            screen: screen,
            menuIndex: menuIndex,
            menuItems: menuItems.map(\.0),
            sourceIsTag: sourceIsTag,
            forceTXSensorLabel: forceTXSensorLabel,
            onSoftKeyTap: handle,
            onMenuItemTap: openMenuItem
        )
    }

    private var controlRow: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            panelButton(.diagnostics)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var landscapeControls: some View {
        VStack(alignment: .center, spacing: 12) {
            compactPanelButton(.diagnostics)
            Spacer(minLength: 0)
        }
        .frame(width: 48)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private enum HomePanel: Identifiable {
        case diagnostics

        var id: Self { self }

        var title: String {
            switch self {
            case .diagnostics: return "Diag"
            }
        }

        var icon: String {
            switch self {
            case .diagnostics: return "gearshape"
            }
        }
    }

    private func panelButton(_ panel: HomePanel) -> some View {
        Button {
            activePanel = panel
        } label: {
            HStack(spacing: 6) {
                Image(systemName: panel.icon)
                Text(panel.title)
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(minWidth: 92, minHeight: 36)
        }
        .buttonStyle(MonoButtonStyle())
    }

    private func compactPanelButton(_ panel: HomePanel) -> some View {
        Button {
            activePanel = panel
        } label: {
            Image(systemName: panel.icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(MonoButtonStyle())
    }

private var routeIndicator: some View {
    Button {
        ble.switchConnectionRoute()
    } label: {
        HStack(spacing: 5) {
            Image(systemName: routeIcon)
            Text(ble.connectionRoute)
        }
        .font(.system(size: 14, weight: .semibold))
        .frame(minWidth: 58, minHeight: 36)
    }
    .buttonStyle(RouteButtonStyle(isActive: routeIsActive))
}

private var compactRouteIndicator: some View {
    Button {
        ble.switchConnectionRoute()
    } label: {
        Text(ble.connectionRoute)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .frame(width: 40, height: 40)
    }
    .buttonStyle(RouteButtonStyle(isActive: routeIsActive))
}

private var routeIcon: String {
    ble.connectionRoute == "TX" ? "antenna.radiowaves.left.and.right" : "display"
}

private var routeIsActive: Bool {
    ble.isConnected && !ble.emulatorMode
}

    private var connectButton: some View {
        Button(action: toggleConnection) {
            HStack(spacing: 6) {
                Image(systemName: connectionIcon)
                Text(connectionTitle)
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(minWidth: 112, minHeight: 36)
        }
        .buttonStyle(MonoButtonStyle(isActive: ble.isConnected && !ble.emulatorMode))
        .disabled(ble.isScanning)
    }

    private var compactConnectButton: some View {
        Button(action: toggleConnection) {
            Image(systemName: connectionIcon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(MonoButtonStyle(isActive: ble.isConnected && !ble.emulatorMode))
        .disabled(ble.isScanning)
    }

    private var connectionTitle: String {
        if ble.isScanning { return "Scanning" }
        if ble.isConnected && !ble.emulatorMode { return "Disconnect" }
        return "Connect"
    }

    private var connectionIcon: String {
        if ble.isScanning { return "dot.radiowaves.left.and.right" }
        if ble.isConnected && !ble.emulatorMode { return "xmark" }
        return "antenna.radiowaves.left.and.right"
    }

    private func autoConnectIfNeeded() {
        guard !requestedAutoConnect else { return }
        guard ble.isBluetoothReady else { return }
        guard !ble.isConnected, !ble.isScanning else { return }
        requestedAutoConnect = true
        sourceIsTag = false
        ble.startLiveMode()
    }

    private func toggleTagSensorSource() {
        requestedAutoConnect = true
        if sourceIsTag || (!ble.emulatorMode && ble.connectionRoute == "TX" && ble.sensorType == .tag) {
            sourceIsTag = false
            forceTXSensorLabel = true
            ble.selectTXSensorSource()
        } else {
            sourceIsTag = true
            forceTXSensorLabel = false
            ble.selectTXTagSource()
        }
    }

    enum Key { case k1, k2, k3, k4, k5 }

    private func handle(_ key: Key) {
        switch (screen, key) {
        case (.home, .k1):
            screen = .voltage
        case (.voltage, .k1):
            screen = .home
        case (.home, .k2):
            screen = .offset
        case (.home, .k3):
            cycleResponse(1)
        case (.home, .k4):
            screen = .menu
            menuIndex = 0
        case (.home, .k5):
            screen = .diagnostics
        case (.menu, .k1):
            menuIndex = (menuIndex + menuItems.count - 1) % menuItems.count
        case (.menu, .k2):
            menuIndex = (menuIndex + 1) % menuItems.count
        case (.menu, .k3):
            openMenuItem(menuIndex)
        case (.menu, .k4):
            screen = .home
        case (.offset, .k1):
            ble.nudgeOffset(1)
        case (.offset, .k2):
            ble.nudgeOffset(-1)
        case (.offset, .k3):
            ble.offsetInches = 0
            ble.sendSettings()
        case (.offset, .k4):
            ble.sendSettings()
            screen = .home
        case (.mode, .k1):
            cycleResponse(1)
        case (.mode, .k2):
            cycleResponse(-1)
        case (.mode, .k3):
            ble.sendSettings()
            screen = .home
        case (.mode, .k4):
            screen = .home
        case (.tag, .k1):
            sourceIsTag = false
            screen = .home
        case (.tag, .k2):
            sourceIsTag = true
            screen = .home
        case (.voltage, .k4):
            screen = .home
        case (_, .k4):
            screen = screen == .menu ? .home : .menu
        default:
            break
        }
    }

    private func cycleResponse(_ delta: Int) {
        let modes = ResponseMode.allCases
        guard let current = modes.firstIndex(of: ble.responseMode) else { return }
        let next = (current + delta + modes.count) % modes.count
        ble.setResponse(modes[next])
    }

    private func openMenuItem(_ index: Int) {
        guard menuItems.indices.contains(index) else { return }
        menuIndex = index
        screen = menuItems[index].1
    }

    private func openMenu() {
        screen = .menu
        menuIndex = 0
    }

    private func toggleMenu() {
        if screen == .menu {
            screen = .home
        } else {
            openMenu()
        }
    }

    private func toggleConnection() {
        sourceIsTag = false
        if ble.isConnected && !ble.emulatorMode {
            ble.disconnect()
        } else {
            requestedAutoConnect = true
            ble.startLiveMode()
        }
    }
}

struct RXMenuHostView: View {
    @ObservedObject var ble: DigiTapeBLEManager

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    Toggle("Emulator Mode", isOn: Binding(
                        get: { ble.emulatorMode },
                        set: { $0 ? ble.startEmulatorMode() : ble.startLiveMode() }
                    ))
                    Button(ble.isScanning ? "Scanning..." : "Connect to DigiTape-RX") {
                        ble.startLiveMode()
                    }
                    .disabled(!ble.emulatorMode && ble.isScanning)
                    Button("Disconnect") { ble.disconnect() }
                }

                Section("Offset") {
                    Stepper("\(ble.offsetInches >= 0 ? "+" : "")\(ble.offsetInches) inches", value: $ble.offsetInches, in: -120...120)
                    Button("Send Offset") { ble.sendSettings() }
                }

                Section("Response Mode") {
                    Picker("Mode", selection: Binding(
                        get: { ble.responseMode },
                        set: { ble.setResponse($0) }
                    )) {
                        ForEach(ResponseMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("DigiTape Menu")
        }
    }
}

struct OLEDDisplay: View {
    @ObservedObject var ble: DigiTapeBLEManager
    let screen: RXScreen
    let menuIndex: Int
    let menuItems: [String]
    let sourceIsTag: Bool
    let forceTXSensorLabel: Bool
    let onSoftKeyTap: (RXConsoleView.Key) -> Void
    let onMenuItemTap: (Int) -> Void

    var body: some View {
        ZStack {
            Color.black
            GeometryReader { geo in
                let scale = geo.size.width / 128
                ZStack(alignment: .topLeading) {
                    oledScreen(scale)
                        .frame(width: 128, height: 64, alignment: .topLeading)
                        .scaleEffect(scale, anchor: .topLeading)
                        .allowsHitTesting(false)
                    touchTargets(scale: scale)
                }
            }
        }
        .aspectRatio(128.0 / 64.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func touchTargets(scale: CGFloat) -> some View {
        if screen == .home {
            tapZone(x: 104, y: 0, width: 24, height: 13, scale: scale) {
                onSoftKeyTap(.k1)
            }
            tapZone(x: 64, y: 0, width: 30, height: 14, scale: scale) {
                onSoftKeyTap(.k5)
            }
            tapZone(x: 0, y: 50, width: 52, height: 14, scale: scale) {
                onSoftKeyTap(.k2)
            }
            tapZone(x: 50, y: 50, width: 32, height: 14, scale: scale) {
                onSoftKeyTap(.k3)
            }
            tapZone(x: 104, y: 50, width: 24, height: 14, scale: scale) {
                onSoftKeyTap(.k4)
            }
        } else {
            if screen == .voltage {
                tapZone(x: 104, y: 0, width: 24, height: 13, scale: scale) {
                    onSoftKeyTap(.k1)
                }
            }
            if screen == .menu {
                ForEach(menuItems.indices, id: \.self) { index in
                    tapZone(x: 0, y: CGFloat(14 + index * 8), width: 82, height: 8, scale: scale) {
                        onMenuItemTap(index)
                    }
                }
            }
            tapZone(x: 84, y: 10, width: 44, height: 14, scale: scale) {
                onSoftKeyTap(.k1)
            }
            tapZone(x: 84, y: 24, width: 44, height: 14, scale: scale) {
                onSoftKeyTap(.k2)
            }
            tapZone(x: 84, y: 38, width: 44, height: 13, scale: scale) {
                onSoftKeyTap(.k3)
            }
            tapZone(x: 84, y: 51, width: 44, height: 13, scale: scale) {
                onSoftKeyTap(.k4)
            }
        }
    }

    private func tapZone(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, scale: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Color.white.opacity(0.001)
                .frame(width: width * scale, height: height * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: x * scale, y: y * scale)
    }

    private func handleTap(at location: CGPoint, scale: CGFloat) {
        guard scale > 0 else { return }
        let oledX = location.x > 128 ? location.x / scale : location.x
        let oledY = location.y > 64 ? location.y / scale : location.y

        if screen == .home {
            if oledX >= 92 && oledY >= 48 {
                onSoftKeyTap(.k4)
            }
            return
        }

        if let key = softKey(atX: oledX, y: oledY) {
            onSoftKeyTap(key)
            return
        }

        guard screen == .menu else { return }
        let row = Int((oledY - 14) / 8)
        guard menuItems.indices.contains(row), oledY >= 14, oledY < 14 + CGFloat(menuItems.count * 8) else { return }
        onMenuItemTap(row)
    }

    private func softKey(atX x: CGFloat, y: CGFloat) -> RXConsoleView.Key? {
        guard x >= 84 else { return nil }
        switch y {
        case 12..<24:
            return .k1
        case 25..<37:
            return .k2
        case 38..<50:
            return .k3
        case 51..<64:
            return .k4
        default:
            return nil
        }
    }

    @ViewBuilder
    private func oledScreen(_ scale: CGFloat) -> some View {
        switch screen {
        case .home:
            homeScreen
        case .voltage:
            voltageScreen
        case .menu:
            menuScreen
        case .offset:
            offsetScreen
        case .mode:
            modeScreen
        case .tag:
            tagScreen
        case .diagnostics:
            diagnosticsScreen
        case .about:
            aboutScreen
        }
    }

    private var homeScreen: some View {
        ZStack(alignment: .topLeading) {
            oledText(sourceLabel, x: 0, y: 0, size: 8, color: sourceLabelColor)
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(OLEDTheme.pixel)
                .frame(width: 12, height: 12)
                .offset(x: 116, y: 0)
            SignalBars(percent: homeSignalPercent)
                .foregroundStyle(OLEDTheme.pixel)
                .frame(width: 24, height: 12)
                .position(x: 78, y: 6)
            if showsSourceCheck {
                OLEDCheckMark()
                    .stroke(OLEDTheme.pixel, lineWidth: 1)
                    .frame(width: 7, height: 6)
                    .offset(x: CGFloat(sourceLabel.count * 5 + 4), y: 1)
            }

            if tagSourceActive {
                if tagPacketActive {
                    distanceOLED
                } else {
                    missingDistanceOLED
                }
            } else if ble.linkOK {
                distanceOLED
            } else {
                missingDistanceOLED
            }

            oledText("OFF \(signedOffset)", x: 0, y: 55, size: 8)
            oledText(ble.responseMode.label, x: centeredX(ble.responseMode.label) + 5, y: 55, size: 8)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(OLEDTheme.pixel)
                .offset(x: 116, y: 53)
        }
    }

    private var voltageScreen: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(OLEDTheme.pixel)
                .offset(x: 117, y: 2)
            oledText("POWER", x: 2, y: 0, size: 8)
            Rectangle()
                .fill(OLEDTheme.pixel)
                .frame(width: 124, height: 1)
                .offset(x: 2, y: 13)
            oledText("BOARD", x: 2, y: 17, size: 8)
            oledText("SRC", x: 46, y: 17, size: 8)
            oledText("VOLTS", x: 84, y: 17, size: 8)
            oledText("TX", x: 2, y: 31, size: 8)
            oledText(txPowerSourceText, x: 46, y: 31, size: 8)
            oledText(txVoltageDetailText, x: 84, y: 31, size: 8)
            oledText("RX", x: 2, y: 43, size: 8)
            oledText(rxPowerSourceText, x: 46, y: 43, size: 8)
            oledText(rxVoltageDetailText, x: 84, y: 43, size: 8)
            oledText("BACK", x: rightX("BACK"), y: 55, size: 8)
        }
    }

    private var menuScreen: some View {
        ZStack(alignment: .topLeading) {
            header("SETTINGS")
            ForEach(menuItems.indices, id: \.self) { index in
                oledText(menuItems[index], x: 0, y: 14 + index * 8, size: 8)
            }
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(OLEDTheme.pixel)
                .offset(x: 116, y: 53)
        }
    }

    private var offsetScreen: some View {
        ZStack(alignment: .topLeading) {
            header("OFFSET")
            oledText(ble.linkOK ? ble.displayDistance.compactDistance : "--'--\"", x: 0, y: 16, size: 16)
            oledText("Offset: \(signedOffset)", x: 0, y: 43, size: 8)
            softLabels("+1", "-1", "0", "BACK")
        }
    }

    private var modeScreen: some View {
        ZStack(alignment: .topLeading) {
            header("MODE")
            oledText(ble.responseMode.label, x: 0, y: 22, size: 16)
            oledText("SMP \(responseAverage) RATE \(responseRate)ms", x: 0, y: 46, size: 8)
            softLabels("NEXT", "PREV", "SAVE", "BACK")
        }
    }

    private var tagScreen: some View {
        ZStack(alignment: .topLeading) {
            header("TAG")
            oledText("Status: \(tagStatusText)", x: 0, y: 14, size: 8)
            oledText("Dist: \(tagDistanceText)", x: 0, y: 26, size: 8)
            oledText("Route: \(ble.connectionRoute)", x: 0, y: 38, size: 8)
            oledText("ID: TAG00001", x: 0, y: 50, size: 8)
            oledText("BACK", x: rightX("BACK"), y: 55, size: 8)
        }
    }

    private var diagnosticsScreen: some View {
        ZStack(alignment: .topLeading) {
            header("DIAG")
            oledText("LINK", x: 0, y: 17, size: 8)
            oledText(ble.linkOK ? "OK" : "--", x: 52, y: 17, size: 8)
            oledText("SIGNAL", x: 0, y: 28, size: 8)
            oledText("\(ble.signalPercent)%", x: 52, y: 28, size: 8)
            oledText("AGE", x: 0, y: 39, size: 8)
            oledText(ble.packetAgeText, x: 52, y: 39, size: 8)
            oledText("SENSOR", x: 0, y: 50, size: 8)
            oledText(ble.sensorType.label, x: 52, y: 50, size: 8)
            oledText("BACK", x: rightX("BACK"), y: 55, size: 8)
        }
    }

    private var aboutScreen: some View {
        ZStack(alignment: .topLeading) {
            header("ABOUT")
            oledText("DigiTape RX", x: 0, y: 16, size: 8)
            oledText("APP 2.1", x: 0, y: 28, size: 8)
            oledText("Display 128x64", x: 0, y: 40, size: 8)
            oledText("BATTERY: --", x: 0, y: 54, size: 8)
            oledText("BACK", x: rightX("BACK"), y: 55, size: 8)
        }
    }

    private var distanceOLED: some View {
        let parts = distanceParts
        return ZStack(alignment: .topLeading) {
            oledText(String(format: "%2d", parts.feet), x: 6, y: 20, size: 24)
            oledText("'", x: 50, y: 24, size: 16)
            oledText(String(format: "%2d", parts.inches), x: 66, y: 20, size: 24)
            oledText("\"", x: 110, y: 24, size: 16)
        }
    }

    private var missingDistanceOLED: some View {
        ZStack(alignment: .topLeading) {
            oledText("--", x: 8, y: 20, size: 24)
            oledText("'", x: 50, y: 24, size: 16)
            oledText("--", x: 66, y: 20, size: 24)
            oledText("\"", x: 110, y: 24, size: 16)
        }
    }

    private func header(_ title: String) -> some View {
        ZStack(alignment: .topLeading) {
            oledText(title, x: 0, y: 0, size: 8)
            Rectangle()
                .fill(OLEDTheme.pixel)
                .frame(width: 124, height: 1)
                .offset(x: 2, y: 13)
        }
    }

    private func softLabels(_ k1: String, _ k2: String, _ k3: String, _ k4: String) -> some View {
        ZStack(alignment: .topLeading) {
            oledText(k1, x: rightX(k1), y: 14, size: 8)
            oledText(k2, x: rightX(k2), y: 27, size: 8)
            oledText(k3, x: rightX(k3), y: 40, size: 8)
            oledText(k4, x: rightX(k4), y: 53, size: 8)
        }
    }

    private func oledText(_ text: String, x: Int, y: Int, size: CGFloat, color: Color = OLEDTheme.pixel) -> some View {
        let paddedX = x == 0 ? 2 : x
        let paddedY = y == 0 ? 2 : (y >= 53 ? y - 2 : y)

        return Text(text)
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .offset(x: CGFloat(paddedX), y: CGFloat(paddedY))
    }

    private var sourceLabel: String {
        if forceTXSensorLabel && ble.sensorType == .tag { return "TX" }
        if tagSourceActive { return "TAG" }
        if ble.emulatorMode { return "EMU" }
        if !ble.linkOK { return "TX" }
        return ble.sensorType.label
    }

    private var sourceLabelColor: Color {
        if sourceLabel == "TAG" && !tagPacketActive { return OLEDTheme.danger }
        if sourceLabel == "TX" && !ble.linkOK { return OLEDTheme.danger }
        return OLEDTheme.pixel
    }

    private var homeSignalPercent: Int {
        if tagSourceActive { return tagPacketActive ? 100 : 0 }
        return ble.linkOK ? ble.signalPercent : 0
    }

    private var txVoltageDetailText: String {
        if ble.emulatorMode { return ble.txInputVoltageText }
        guard ble.isConnected else { return "--" }
        guard ble.txInputMillivolts != nil else { return "5.0V" }
        return ble.txInputVoltageText
    }

    private var txPowerSourceText: String {
        if ble.emulatorMode { return "BAT" }
        guard ble.isConnected else { return "--" }
        return ble.txInputMillivolts == nil ? "USB" : "BAT"
    }

    private var rxVoltageDetailText: String {
        if ble.emulatorMode {
            let estimatedVoltage = 3.3 + (Double(ble.batteryPercent) / 100.0) * 0.9
            return String(format: "%.1fV", estimatedVoltage)
        }
        guard ble.isConnected else { return "--" }
        return "5.0V"
    }

    private var rxPowerSourceText: String {
        if ble.emulatorMode { return "BAT" }
        return ble.isConnected ? "USB" : "--"
    }

    private var tagSourceActive: Bool {
        sourceIsTag || (!ble.emulatorMode && ble.sensorType == .tag)
    }

    private var tagPacketActive: Bool {
        ble.linkOK && ble.sensorType == .tag
    }

    private var tagStatusText: String {
        if tagPacketActive { return "Live" }
        if ble.errorFlag != 0 && ble.sensorType == .tag { return "Error" }
        return "Searching"
    }

    private var tagDistanceText: String {
        guard tagPacketActive else { return "--'--\"" }
        return ble.displayDistance.compactDistance
    }

    private var showsSourceCheck: Bool {
        false
    }

    private var signedOffset: String {
        "\(ble.offsetInches >= 0 ? "+" : "")\(ble.offsetInches)\""
    }

    private var distanceParts: (feet: Int, inches: Int) {
        let total = max(0, Int((ble.currentDistanceInches + Double(ble.offsetInches)).rounded()))
        return (total / 12, total % 12)
    }

    private var responseAverage: Int {
        switch ble.responseMode {
        case .fast: return 1
        case .normal: return 4
        case .avg: return 8
        case .slow: return 12
        }
    }

    private var responseRate: Int {
        switch ble.responseMode {
        case .fast: return 50
        case .normal: return 100
        case .avg: return 150
        case .slow: return 250
        }
    }


    private var shortPacketCounter: String {
        if ble.packetCounter < 10000 { return "\(ble.packetCounter)" }
        return "\(ble.packetCounter % 10000)"
    }

    private func rightX(_ text: String) -> Int {
        max(0, 125 - text.count * 5)
    }

    private func centeredX(_ text: String) -> Int {
        max(0, (128 - text.count * 5) / 2)
    }
}

private enum OLEDTheme {
    static let pixel = Color(red: 0.33, green: 1.0, blue: 0.18)
    static let warning = Color(red: 1.0, green: 0.78, blue: 0.22)
    static let danger = Color(red: 1.0, green: 0.16, blue: 0.12)
}

struct ArrowKeyColumn: View {
    let onUp: () -> Void
    let onDown: () -> Void
    let onForward: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            key("arrow.up", action: onUp)
            key("arrow.down", action: onDown)
            key("arrow.right", action: onForward)
            key("arrow.left", action: onBack)
        }
    }

    private func key(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 21, weight: .bold))
                .frame(width: 58, height: 42)
        }
        .buttonStyle(MonoButtonStyle())
    }
}

struct RouteButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? .black : OLEDTheme.pixel)
            .background(isActive ? OLEDTheme.pixel : Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(OLEDTheme.pixel, lineWidth: isActive ? 0 : 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct MonoButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? .black : OLEDTheme.pixel)
            .background(isActive ? OLEDTheme.pixel : Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(OLEDTheme.pixel, lineWidth: isActive ? 0 : 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct EmulatorView: View {
    @ObservedObject var ble: DigiTapeBLEManager

    var body: some View {
        NavigationStack {
            Form {
                Section("Distance") {
                    Text(ble.displayDistance).font(.largeTitle.monospaced().bold())
                    Slider(value: $ble.emulatorDistanceInches, in: 0...600, step: 1)
                }
                Section("Signal Strength") {
                    Text("\(ble.signalPercent)%")
                    Slider(value: $ble.emulatorSignal, in: 0...100, step: 1)
                }
                Section("Battery") {
                    Text("\(ble.batteryPercent)%")
                    Slider(value: $ble.emulatorBattery, in: 0...100, step: 1)
                }
            }
            .navigationTitle("Emulator")
            .onAppear { ble.startEmulatorMode() }
        }
    }
}

struct WiringDiagramView: View {
    @ObservedObject var ble: DigiTapeBLEManager

    @State private var diagrams = WiringDiagram.templates
    @State private var selectedDiagramID = "tx"
    @State private var canvasScale: CGFloat = 0.72
    @State private var canvasOffset = CGSize.zero
    @State private var pendingPin: WiringPinRef?
    @State private var selectedComponentID: String?
    @State private var selectedWireID: UUID?
    @State private var showingPrompt = false
    @State private var showingComponentPicker = false
    @State private var showingConnectionExport = false
    @State private var showingConnectionShare = false
    @State private var connectionExportItems: [Any] = []
    @State private var showingFirmwareCheck = false
    @State private var promptText = ""
    @State private var promptResult: WiringPromptResult?
    @State private var promptUndoStack: [String: [WiringDiagram]] = [:]

    private var selectedDiagramIndex: Int {
        diagrams.firstIndex { $0.id == selectedDiagramID } ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            wiringToolbar
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 8)

            Divider()

            WiringDiagramEditorCanvas(
                diagram: $diagrams[selectedDiagramIndex],
                scale: $canvasScale,
                offset: $canvasOffset,
                selectedColor: .green,
                label: "",
                pendingPin: $pendingPin,
                selectedComponentID: $selectedComponentID,
                selectedWireID: $selectedWireID
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Wiring")
        .navigationBarTitleDisplayMode(.inline)
        .disableNavigationBackSwipe()
        .sheet(isPresented: $showingPrompt) {
            wiringPromptSheet
        }
        .sheet(isPresented: $showingComponentPicker) {
            componentPickerSheet
        }
        .sheet(isPresented: $showingConnectionExport) {
            connectionExportSheet
        }
        .sheet(isPresented: $showingConnectionShare) {
            ActivityShareSheet(items: connectionExportItems)
        }
        .sheet(isPresented: $showingFirmwareCheck) {
            firmwareCheckSheet
        }
    }

    private var wiringToolbar: some View {
        VStack(spacing: 8) {
            Picker("Diagram", selection: $selectedDiagramID) {
                ForEach(diagrams) { diagram in
                    Text(diagram.title).tag(diagram.id)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        showingPrompt = true
                    } label: {
                        Label("Prompt", systemImage: "text.bubble")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showingComponentPicker = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showingConnectionExport = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showingFirmwareCheck = true
                    } label: {
                        Label("Check", systemImage: "checklist.checked")
                    }
                    .buttonStyle(.bordered)

                    if canDeleteSelectedComponent {
                        Button(role: .destructive) {
                            deleteSelectedComponent()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                    }

                }
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var firmwareCheckSheet: some View {
        let report = WiringFirmwarePinAudit.report(for: diagrams)

        return NavigationStack {
            List {
                Section("Firmware Checked") {
                    firmwareVersionRow(target: "TX", installed: ble.installedFirmwareVersion(for: "TX"), expected: WiringFirmwarePinAudit.expectedTXVersion)
                    firmwareVersionRow(target: "RX", installed: ble.installedFirmwareVersion(for: "RX"), expected: WiringFirmwarePinAudit.expectedRXVersion)
                }

                Section("Wiring Cross-Check") {
                    Label(report.isClean ? "All checked wiring matches the loaded firmware pin map." : "\(report.issues.count) wiring issue(s) found", systemImage: report.isClean ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(report.isClean ? .green : .orange)

                    if !report.isClean {
                        ForEach(report.issues) { issue in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.title)
                                    .font(.headline)
                                Text(issue.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("Firmware Wiring") {
                    firmwareWiringGroup("TX \(WiringFirmwarePinAudit.expectedTXVersion)", rows: [
                        ("Distance Sensor", ["TX -> GPIO21", "RX -> GPIO20"]),
                        ("HC-SR04", ["TRIG -> GPIO20", "ECHO -> GPIO21"]),
                        ("RYUW122", ["TXD -> GPIO37", "RXD -> GPIO36", "NRST -> GPIO1", "VDD -> 3V3"]),
                        ("MAX3232 / MDR.X", ["TTL IN -> GPIO16", "TTL OUT -> GPIO15", "GND -> GND"]),
                        ("OLED", ["SDA -> GPIO40", "SCL -> GPIO41", "3V3 -> 3V3"])
                    ])

                    firmwareWiringGroup("RX \(WiringFirmwarePinAudit.expectedRXVersion)", rows: [
                        ("OLED", ["SDA -> GPIO47", "SCL -> GPIO48", "3V3 -> 3V3"]),
                        ("Buttons", ["K1 -> GPIO11", "K2 -> GPIO12", "K3 -> GPIO13", "K4 -> GPIO14"]),
                        ("2.8 Touch", ["LCD CS -> GPIO10", "LCD DC -> GPIO9", "LCD RST -> GPIO14", "SCK -> GPIO12", "MOSI -> GPIO7", "MISO -> GPIO11", "CTP SDA -> GPIO17", "CTP SCL -> GPIO18", "CTP INT -> GPIO13", "CTP RST -> GPIO15"]),
                        ("RYUW122", ["TXD -> GPIO38", "RXD -> GPIO39", "NRST -> GPIO1", "VDD -> 3V3"]),
                        ("Power", ["Boost 5V OUT -> 5VIN", "GND -> GND"]),
                        ("Battery Sense", ["ADC -> GPIO16"])
                    ])
                }
            }
            .navigationTitle("Firmware Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        showingFirmwareCheck = false
                    }
                }
            }
        }
    }

    private func firmwareWiringGroup(_ title: String, rows: [(String, [String])]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            ForEach(rows, id: \.0) { row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.0)
                        .font(.subheadline.weight(.semibold))
                    ForEach(row.1, id: \.self) { pinLine in
                        Text(pinLine)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func firmwareVersionRow(target: String, installed: String, expected: String) -> some View {
        let normalizedInstalled = installed.trimmingCharacters(in: .whitespacesAndNewlines)
        let boardVersionRead = !(normalizedInstalled.isEmpty || normalizedInstalled == "--" || normalizedInstalled == "Unknown")
        let versionOK = boardVersionRead && (normalizedInstalled == expected || normalizedInstalled.contains(expected))

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(target)
                    .font(.headline)
                Text(boardVersionRead ? "Board \(installed)" : "Board version not read")
                    .font(.caption)
                    .foregroundStyle(boardVersionRead ? (versionOK ? .green : .orange) : .secondary)
            }

            Spacer()

            Text("Map \(expected)")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
        }
    }

    private var componentPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(WiringComponentLibrary.categories) { category in
                    Section(category.title) {
                        ForEach(WiringComponentLibrary.items(for: category)) { item in
                            Button {
                                addComponent(item)
                                showingComponentPicker = false
                            } label: {
                                Label(item.title, systemImage: item.symbolName)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Component")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        showingComponentPicker = false
                    }
                }
            }
        }
    }

    private var connectionExportSheet: some View {
        NavigationStack {
            ScrollView {
                Text(connectionExportText)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        showingConnectionExport = false
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        connectionExportItems = makeConnectionExportItems()
                        showingConnectionShare = !connectionExportItems.isEmpty
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private var wiringPromptSheet: some View {
        NavigationStack {
            Form {
                Section("Diagram Prompt") {
                    TextEditor(text: $promptText)
                        .frame(minHeight: 120)
                        .textInputAutocapitalization(.sentences)

                    Button {
                        promptResult = WiringPromptEngine.preview(prompt: promptText, diagram: diagrams[selectedDiagramIndex])
                    } label: {
                        Label("Preview Changes", systemImage: "wand.and.sparkles")
                    }
                    .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let promptResult {
                    Section("Preview") {
                        ForEach(promptResult.messages, id: \.self) { message in
                            Text(message)
                        }
                    }

                    Section {
                        Button {
                            promptUndoStack[selectedDiagramID, default: []].append(diagrams[selectedDiagramIndex])
                            diagrams[selectedDiagramIndex] = promptResult.diagram
                            selectedComponentID = nil
                            selectedWireID = nil
                            pendingPin = nil
                            showingPrompt = false
                        } label: {
                            Label("Apply", systemImage: "checkmark.circle")
                        }
                        .disabled(!promptResult.hasChanges)
                    }
                }
            }
            .navigationTitle("Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        showingPrompt = false
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        undoPromptChange()
                        showingPrompt = false
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!canUndoPromptChange)
                }
            }
        }
    }

    private var selectedComponentBinding: Binding<WiringComponent>? {
        guard let selectedComponentID,
              let componentIndex = diagrams[selectedDiagramIndex].components.firstIndex(where: { $0.id == selectedComponentID })
        else { return nil }
        return $diagrams[selectedDiagramIndex].components[componentIndex]
    }

    private var selectedWireBinding: Binding<WiringWire>? {
        guard let selectedWireID,
              let wireIndex = diagrams[selectedDiagramIndex].wires.firstIndex(where: { $0.id == selectedWireID })
        else { return nil }
        return $diagrams[selectedDiagramIndex].wires[wireIndex]
    }

    private var canDeleteSelectedComponent: Bool {
        guard let selectedComponentID,
              let component = diagrams[selectedDiagramIndex].component(with: selectedComponentID)
        else { return false }
        return !component.isESP32S3
    }

    private var canUndoPromptChange: Bool {
        promptUndoStack[selectedDiagramID]?.isEmpty == false
    }

    private func undoPromptChange() {
        guard var stack = promptUndoStack[selectedDiagramID],
              let previousDiagram = stack.popLast()
        else { return }
        promptUndoStack[selectedDiagramID] = stack
        diagrams[selectedDiagramIndex] = previousDiagram
        selectedComponentID = nil
        selectedWireID = nil
        pendingPin = nil
    }

    private func addComponent(_ item: WiringComponentLibraryItem) {
        var diagram = diagrams[selectedDiagramIndex]
        let component = item.component(for: diagram)
        diagram.components.append(component)
        item.addDefaultWires(componentID: component.id, to: &diagram)
        item.addCompanionWires(componentID: component.id, to: &diagram)
        diagrams[selectedDiagramIndex] = diagram
        selectedComponentID = component.id
        selectedWireID = nil
        pendingPin = nil
    }

    private func deleteSelectedComponent() {
        guard let selectedComponentID,
              let component = diagrams[selectedDiagramIndex].component(with: selectedComponentID),
              !component.isESP32S3
        else { return }
        diagrams[selectedDiagramIndex].components.removeAll { $0.id == selectedComponentID }
        diagrams[selectedDiagramIndex].wires.removeAll {
            $0.from.componentID == selectedComponentID || $0.to.componentID == selectedComponentID
        }
        self.selectedComponentID = nil
        selectedWireID = nil
        pendingPin = nil
    }

    private func connectionSummary(for wire: WiringWire, in diagram: WiringDiagram) -> String {
        "\(diagram.pinTitle(for: wire.from)) -> \(diagram.pinTitle(for: wire.to))"
    }

    private var connectionExportText: String {
        var lines: [String] = [
            "DigiTape Wiring Export",
            ""
        ]

        for diagram in diagrams {
            lines.append("\(diagram.title) Pinout")
            lines.append(String(repeating: "-", count: max(10, diagram.title.count + 7)))

            for component in diagram.components.sorted(by: { lhs, rhs in
                if lhs.isESP32S3 != rhs.isESP32S3 { return lhs.isESP32S3 }
                return lhs.title < rhs.title
            }) {
                lines.append(component.title)
                for pin in component.pins {
                    let ref = WiringPinRef(componentID: component.id, pin: pin)
                    lines.append("  \(pin) -> \(pinConnectionSummary(for: ref, in: diagram))")
                }
                lines.append("")
            }

            lines.append("\(diagram.title) Diagram")
            lines.append(String(repeating: "-", count: max(10, diagram.title.count + 8)))

            if diagram.wires.isEmpty {
                lines.append("No diagram connections.")
            } else {
                for wire in diagram.wires {
                    lines.append(diagramConnectionLine(for: wire, in: diagram))
                }
            }

            lines.append("")
            lines.append("\(diagram.title) Assembly List")
            lines.append(String(repeating: "-", count: max(14, diagram.title.count + 14)))

            if diagram.wires.isEmpty {
                lines.append("No connections.")
            } else {
                for (index, wire) in diagram.wires.enumerated() {
                    lines.append("\(index + 1). \(assemblyConnectionLine(for: wire, in: diagram))")
                }
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    @MainActor
    private func makeConnectionExportItems() -> [Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DigiTape-Wiring-Export", isDirectory: true)
        var urls: [URL] = []

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let textURL = directory.appendingPathComponent("DigiTape_Wiring_Pinout.txt")
            try connectionExportText.data(using: .utf8)?.write(to: textURL, options: .atomic)
            urls.append(textURL)

            for diagram in diagrams {
                if let imageURL = renderDiagramExport(diagram, in: directory) {
                    urls.append(imageURL)
                }
            }
        } catch {
            return [connectionExportText]
        }

        return urls
    }

    @MainActor
    private func renderDiagramExport(_ diagram: WiringDiagram, in directory: URL) -> URL? {
        let renderer = ImageRenderer(content: WiringDiagramExportImage(diagram: diagram))
        renderer.scale = 2
        guard let image = renderer.uiImage,
              let data = image.pngData()
        else { return nil }

        let url = directory.appendingPathComponent("DigiTape_\(diagram.title)_Wiring_Diagram.png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func pinConnectionSummary(for ref: WiringPinRef, in diagram: WiringDiagram) -> String {
        let matches = diagram.wires.filter { $0.from == ref || $0.to == ref }
        guard !matches.isEmpty else { return "Not connected" }
        return matches.map { wire in
            let other = wire.from == ref ? wire.to : wire.from
            return diagram.pinTitle(for: other)
        }
        .joined(separator: " | ")
    }

    private func diagramConnectionLine(for wire: WiringWire, in diagram: WiringDiagram) -> String {
        guard let fromComponent = diagram.component(with: wire.from.componentID),
              let toComponent = diagram.component(with: wire.to.componentID)
        else {
            return "[\(wire.from.componentID):\(wire.from.pin)] -> [\(wire.to.componentID):\(wire.to.pin)]"
        }

        return "[\(fromComponent.title): \(wire.from.pin)] -- \(wire.label) --> [\(toComponent.title): \(wire.to.pin)]"
    }

    private func assemblyConnectionLine(for wire: WiringWire, in diagram: WiringDiagram) -> String {
        guard let fromComponent = diagram.component(with: wire.from.componentID),
              let toComponent = diagram.component(with: wire.to.componentID)
        else {
            return "\(wire.from.componentID) \(wire.from.pin) -> \(wire.to.componentID) \(wire.to.pin)"
        }

        if fromComponent.isESP32S3 {
            return "\(toComponent.title) \(wire.to.pin) -> \(fromComponent.title) \(wire.from.pin)"
        }

        if toComponent.isESP32S3 {
            return "\(fromComponent.title) \(wire.from.pin) -> \(toComponent.title) \(wire.to.pin)"
        }

        return "\(fromComponent.title) \(wire.from.pin) -> \(toComponent.title) \(wire.to.pin)"
    }

    private func pinConnectionText(for ref: WiringPinRef, in diagram: WiringDiagram) -> String {
        let matches = diagram.wires.filter { $0.from == ref || $0.to == ref }
        guard !matches.isEmpty else { return "Not connected" }
        return matches.map { wire in
            let other = wire.from == ref ? wire.to : wire.from
            return "\(wire.label): \(diagram.pinTitle(for: other))"
        }
        .joined(separator: "\n")
    }
}

private extension View {
    func disableNavigationBackSwipe() -> some View {
        background(NavigationBackSwipeDisabler())
    }
}

private struct WiringFirmwarePinIssue: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

private struct WiringFirmwarePinReport {
    let issues: [WiringFirmwarePinIssue]

    var isClean: Bool {
        issues.isEmpty
    }
}

private enum WiringFirmwarePinAudit {
    static let expectedTXVersion = "2.0.9"
    static let expectedRXVersion = "2.0.8"

    private struct ExpectedPin {
        let componentTitleContains: String
        let componentPin: String
        let boardPin: String
        let firmwareSymbol: String
    }

    static func report(for diagrams: [WiringDiagram]) -> WiringFirmwarePinReport {
        var issues: [WiringFirmwarePinIssue] = []

        for diagram in diagrams {
            let expectations = expectedPins(for: diagram.id)
            for expected in expectations {
                let matchingComponents = diagram.components.filter {
                    $0.title.localizedCaseInsensitiveContains(expected.componentTitleContains)
                }

                for component in matchingComponents {
                    guard component.pins.contains(expected.componentPin) else { continue }
                    let actualBoardPin = boardPinConnected(to: WiringPinRef(componentID: component.id, pin: expected.componentPin), in: diagram)

                    guard let actualBoardPin else {
                        issues.append(WiringFirmwarePinIssue(
                            title: "\(diagram.title): \(component.title) \(expected.componentPin) not connected",
                            detail: "Firmware \(expected.firmwareSymbol) expects ESP32 \(expected.boardPin)."
                        ))
                        continue
                    }

                    guard pinsMatch(actualBoardPin, expectedBoardPin: expected.boardPin) else {
                        issues.append(WiringFirmwarePinIssue(
                            title: "\(diagram.title): \(component.title) \(expected.componentPin) is on \(actualBoardPin)",
                            detail: "Firmware \(expected.firmwareSymbol) expects ESP32 \(expected.boardPin)."
                        ))
                        continue
                    }
                }
            }
        }

        return WiringFirmwarePinReport(issues: issues)
    }

    private static func boardPinConnected(to ref: WiringPinRef, in diagram: WiringDiagram) -> String? {
        for wire in diagram.wires where wire.from == ref || wire.to == ref {
            let otherRef = wire.from == ref ? wire.to : wire.from
            if diagram.component(with: otherRef.componentID)?.isESP32S3 == true {
                return otherRef.pin
            }
        }
        return nil
    }

    private static func pinsMatch(_ actual: String, expectedBoardPin expected: String) -> Bool {
        if expected == "GND" { return actual.uppercased().hasPrefix("GND") }
        if expected == "3V3" { return actual.uppercased().hasPrefix("3V3") }
        return actual == expected
    }

    private static func expectedPins(for diagramID: String) -> [ExpectedPin] {
        switch diagramID {
        case "tx":
            return [
                ExpectedPin(componentTitleContains: "Luna", componentPin: "TX", boardPin: "GPIO21", firmwareSymbol: "ECHO_PIN / UART RX"),
                ExpectedPin(componentTitleContains: "Luna", componentPin: "RX", boardPin: "GPIO20", firmwareSymbol: "TRIG_PIN / UART TX"),
                ExpectedPin(componentTitleContains: "Garmin", componentPin: "TX", boardPin: "GPIO21", firmwareSymbol: "ECHO_PIN / UART RX"),
                ExpectedPin(componentTitleContains: "Garmin", componentPin: "RX", boardPin: "GPIO20", firmwareSymbol: "TRIG_PIN / UART TX"),
                ExpectedPin(componentTitleContains: "HC-SR04", componentPin: "TRIG", boardPin: "GPIO20", firmwareSymbol: "TRIG_PIN"),
                ExpectedPin(componentTitleContains: "HC-SR04", componentPin: "ECHO", boardPin: "GPIO21", firmwareSymbol: "ECHO_PIN"),
                ExpectedPin(componentTitleContains: "RYUW122", componentPin: "TXD", boardPin: "GPIO38", firmwareSymbol: "RYUW_RX_PIN"),
                ExpectedPin(componentTitleContains: "RYUW122", componentPin: "RXD", boardPin: "GPIO39", firmwareSymbol: "RYUW_TX_PIN"),
                ExpectedPin(componentTitleContains: "RYUW122", componentPin: "NRST", boardPin: "GPIO1", firmwareSymbol: "RYUW_NRST_PIN"),
                ExpectedPin(componentTitleContains: "RYUW122", componentPin: "VDD", boardPin: "3V3", firmwareSymbol: "RYUW VDD"),
                ExpectedPin(componentTitleContains: "RYUW122", componentPin: "GND", boardPin: "GND", firmwareSymbol: "RYUW GND"),
                ExpectedPin(componentTitleContains: "MAX3232", componentPin: "TTL IN", boardPin: "GPIO16", firmwareSymbol: "MDR_TX_PIN"),
                ExpectedPin(componentTitleContains: "MAX3232", componentPin: "TTL OUT", boardPin: "GPIO15", firmwareSymbol: "MDR_RX_PIN"),
                ExpectedPin(componentTitleContains: "MAX3232", componentPin: "GND", boardPin: "GND", firmwareSymbol: "MDR GND"),
                ExpectedPin(componentTitleContains: "OLED", componentPin: "SDA", boardPin: "GPIO40", firmwareSymbol: "OLED_SDA_PIN"),
                ExpectedPin(componentTitleContains: "OLED", componentPin: "SCL", boardPin: "GPIO41", firmwareSymbol: "OLED_SCL_PIN"),
                ExpectedPin(componentTitleContains: "OLED", componentPin: "3V3", boardPin: "3V3", firmwareSymbol: "OLED VDD"),
                ExpectedPin(componentTitleContains: "OLED", componentPin: "GND", boardPin: "GND", firmwareSymbol: "OLED GND")
            ]
        case "rx":
            return [
                ExpectedPin(componentTitleContains: "OLED", componentPin: "SDA", boardPin: "GPIO47", firmwareSymbol: "I2C_SDA"),
                ExpectedPin(componentTitleContains: "OLED", componentPin: "SCL", boardPin: "GPIO48", firmwareSymbol: "I2C_SCL"),
                ExpectedPin(componentTitleContains: "OLED", componentPin: "3V3", boardPin: "3V3", firmwareSymbol: "OLED VDD"),
                ExpectedPin(componentTitleContains: "OLED", componentPin: "GND", boardPin: "GND", firmwareSymbol: "OLED GND"),
                ExpectedPin(componentTitleContains: "Button", componentPin: "SW", boardPin: "GPIO11", firmwareSymbol: "BTN_K1"),
                ExpectedPin(componentTitleContains: "Button", componentPin: "GND", boardPin: "GND", firmwareSymbol: "Button GND"),
                ExpectedPin(componentTitleContains: "RYUW122", componentPin: "TXD", boardPin: "GPIO37", firmwareSymbol: "RYUW_RX_PIN"),
                ExpectedPin(componentTitleContains: "RYUW122", componentPin: "RXD", boardPin: "GPIO36", firmwareSymbol: "RYUW_TX_PIN"),
                ExpectedPin(componentTitleContains: "RYUW122", componentPin: "NRST", boardPin: "GPIO1", firmwareSymbol: "RYUW_NRST_PIN"),
                ExpectedPin(componentTitleContains: "RYUW122", componentPin: "VDD", boardPin: "3V3", firmwareSymbol: "RYUW VDD"),
                ExpectedPin(componentTitleContains: "RYUW122", componentPin: "GND", boardPin: "GND", firmwareSymbol: "RYUW GND"),
                ExpectedPin(componentTitleContains: "USB Boost Charger", componentPin: "5V OUT", boardPin: "5VIN", firmwareSymbol: "RX board power input"),
                ExpectedPin(componentTitleContains: "USB Boost Charger", componentPin: "GND", boardPin: "GND", firmwareSymbol: "RX board ground"),
                ExpectedPin(componentTitleContains: "Battery Sense", componentPin: "ADC", boardPin: "GPIO16", firmwareSymbol: "BATTERY_ADC_PIN")
            ]
        default:
            return []
        }
    }
}

private struct NavigationBackSwipeDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        Controller()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Controller: UIViewController {
        private weak var previousDelegate: UIGestureRecognizerDelegate?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }
            previousDelegate = gesture.delegate
            gesture.isEnabled = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }
            gesture.delegate = previousDelegate
            gesture.isEnabled = true
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct WiringDiagram: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    var components: [WiringComponent]
    var wires: [WiringWire]

    private static let txESP32S3Pins = [
        "3V3 A", "3V3 B", "RST", "GPIO4", "GPIO5", "GPIO6", "GPIO7", "GPIO15", "GPIO16", "GPIO17", "GPIO18", "GPIO8", "GPIO3", "GPIO46", "GPIO9", "GPIO10", "GPIO11", "GPIO12", "GPIO13", "GPIO14", "5VIN", "GND L",
        "GND TOP", "GPIO43", "GPIO44", "GPIO1", "GPIO2", "GPIO42", "GPIO41", "GPIO40", "GPIO39", "GPIO38", "GPIO37", "GPIO36", "GPIO35", "GPIO0", "GPIO45", "GPIO48", "GPIO47", "GPIO21", "GPIO20", "GPIO19", "GND R1", "GND R2"
    ]

    private static let rxESP32S3Pins = [
        "3V3 A", "3V3 B", "RST", "GPIO4", "GPIO5", "GPIO6", "GPIO7", "GPIO15", "GPIO16", "GPIO17", "GPIO18", "GPIO8", "GPIO3", "GPIO46", "GPIO9", "GPIO10", "GPIO11", "GPIO12", "GPIO13", "GPIO14", "5VIN", "GND L",
        "GND TOP", "GPIO43", "GPIO44", "GPIO1", "GPIO2", "GPIO42", "GPIO41", "GPIO40", "GPIO39", "GPIO38", "GPIO37", "GPIO36", "GPIO35", "GPIO0", "GPIO45", "GPIO48", "GPIO47", "GPIO21", "GPIO20", "GPIO19", "GND R1", "GND R2"
    ]

    static let templates: [WiringDiagram] = [
        WiringDiagram(
            id: "tx",
            title: "TX",
            subtitle: "Sensor, RYUW anchor, MDR.X serial, OLED, and power.",
            components: [
                WiringComponent(id: "tx-board", title: "TX ESP32-S3", pins: txESP32S3Pins, rect: CGRect(x: 260, y: 20, width: 186, height: 500), color: .green),
                WiringComponent(id: "sensor", title: "Luna Sensor", pins: ["TX", "RX", "VDD", "GND"], rect: CGRect(x: 14, y: 42, width: 116, height: 102), color: .green),
                WiringComponent(id: "sensor-connector", title: "Sensor 4-pin", pins: ["TX", "RX", "VDD", "GND"], rect: CGRect(x: 148, y: 42, width: 92, height: 102), color: .gray),
                WiringComponent(id: "oled", title: "0.97 OLED", pins: ["SDA", "SCL", "3V3", "GND"], rect: CGRect(x: 14, y: 310, width: 104, height: 94), color: .purple),
                WiringComponent(id: "ryuw", title: "RYUW122 Lite", pins: ["TXD", "RXD", "NRST", "VDD", "GND"], rect: CGRect(x: 572, y: 42, width: 108, height: 112), color: .orange),
                WiringComponent(id: "mdr", title: "MAX3232 / MDR.X", pins: ["TTL IN", "TTL OUT", "RS-232 out", "9600 8N1", "GND"], rect: CGRect(x: 560, y: 310, width: 126, height: 116), color: .brown)
            ],
            wires: [
                WiringWire(from: WiringPinRef(componentID: "sensor", pin: "TX"), to: WiringPinRef(componentID: "sensor-connector", pin: "TX"), label: "TX", colorName: .green),
                WiringWire(from: WiringPinRef(componentID: "sensor", pin: "RX"), to: WiringPinRef(componentID: "sensor-connector", pin: "RX"), label: "RX", colorName: .blue),
                WiringWire(from: WiringPinRef(componentID: "sensor", pin: "VDD"), to: WiringPinRef(componentID: "sensor-connector", pin: "VDD"), label: "VDD", colorName: .red),
                WiringWire(from: WiringPinRef(componentID: "sensor", pin: "GND"), to: WiringPinRef(componentID: "sensor-connector", pin: "GND"), label: "GND", colorName: .black),
                WiringWire(from: WiringPinRef(componentID: "sensor-connector", pin: "TX"), to: WiringPinRef(componentID: "tx-board", pin: "GPIO21"), label: "GPIO21", colorName: .green),
                WiringWire(from: WiringPinRef(componentID: "sensor-connector", pin: "RX"), to: WiringPinRef(componentID: "tx-board", pin: "GPIO20"), label: "GPIO20", colorName: .blue),
                WiringWire(from: WiringPinRef(componentID: "sensor-connector", pin: "VDD"), to: WiringPinRef(componentID: "tx-board", pin: "5VIN"), label: "VDD", colorName: .red),
                WiringWire(from: WiringPinRef(componentID: "sensor-connector", pin: "GND"), to: WiringPinRef(componentID: "tx-board", pin: "GND L"), label: "GND", colorName: .black),
                WiringWire(from: WiringPinRef(componentID: "ryuw", pin: "TXD"), to: WiringPinRef(componentID: "tx-board", pin: "GPIO37"), label: "RYUW TXD", colorName: .orange),
                WiringWire(from: WiringPinRef(componentID: "ryuw", pin: "RXD"), to: WiringPinRef(componentID: "tx-board", pin: "GPIO36"), label: "RYUW RXD", colorName: .yellow),
                WiringWire(from: WiringPinRef(componentID: "ryuw", pin: "NRST"), to: WiringPinRef(componentID: "tx-board", pin: "GPIO1"), label: "NRST", colorName: .blue),
                WiringWire(from: WiringPinRef(componentID: "ryuw", pin: "VDD"), to: WiringPinRef(componentID: "tx-board", pin: "3V3 B"), label: "VDD", colorName: .red),
                WiringWire(from: WiringPinRef(componentID: "mdr", pin: "TTL IN"), to: WiringPinRef(componentID: "tx-board", pin: "GPIO16"), label: "MDR IN", colorName: .blue),
                WiringWire(from: WiringPinRef(componentID: "mdr", pin: "TTL OUT"), to: WiringPinRef(componentID: "tx-board", pin: "GPIO15"), label: "MDR OUT", colorName: .orange),
                WiringWire(from: WiringPinRef(componentID: "oled", pin: "SDA"), to: WiringPinRef(componentID: "tx-board", pin: "GPIO40"), label: "SDA", colorName: .purple),
                WiringWire(from: WiringPinRef(componentID: "oled", pin: "SCL"), to: WiringPinRef(componentID: "tx-board", pin: "GPIO41"), label: "SCL", colorName: .brown),
                WiringWire(from: WiringPinRef(componentID: "oled", pin: "3V3"), to: WiringPinRef(componentID: "tx-board", pin: "3V3 A"), label: "3V3", colorName: .red),
                WiringWire(from: WiringPinRef(componentID: "ryuw", pin: "GND"), to: WiringPinRef(componentID: "tx-board", pin: "GND TOP"), label: "GND", colorName: .black),
                WiringWire(from: WiringPinRef(componentID: "mdr", pin: "GND"), to: WiringPinRef(componentID: "tx-board", pin: "GND R1"), label: "GND", colorName: .black),
                WiringWire(from: WiringPinRef(componentID: "oled", pin: "GND"), to: WiringPinRef(componentID: "tx-board", pin: "GND L"), label: "GND", colorName: .black)
            ]
        ),
        WiringDiagram(
            id: "rx",
            title: "RX",
            subtitle: "OLED, buttons, battery power, charger boost, and RYUW.",
            components: [
                WiringComponent(id: "rx-board", title: "RX ESP32-S3", pins: rxESP32S3Pins, rect: CGRect(x: 260, y: 20, width: 186, height: 500), color: .green),
                WiringComponent(id: "rx-oled", title: "0.97 OLED", pins: ["SDA", "SCL", "3V3", "GND"], rect: CGRect(x: 14, y: 42, width: 104, height: 94), color: .purple),
                WiringComponent(id: "button", title: "Button", pins: ["SW", "GND"], rect: CGRect(x: 14, y: 310, width: 98, height: 74), color: .blue),
                WiringComponent(id: "rx-ryuw", title: "RYUW122 Lite", pins: ["TXD", "RXD", "NRST", "VDD", "GND"], rect: CGRect(x: 572, y: 42, width: 108, height: 112), color: .orange),
                WiringComponent(id: "rx-battery", title: "2000mAh 3.7V Battery", pins: ["BAT+", "BAT-"], rect: CGRect(x: 560, y: 292, width: 140, height: 84), color: .red),
                WiringComponent(id: "rx-charger", title: "USB Boost Charger", pins: ["B+", "B-", "5V OUT", "GND", "USB"], rect: CGRect(x: 560, y: 404, width: 142, height: 116), color: .gray)
            ],
            wires: [
                WiringWire(from: WiringPinRef(componentID: "rx-oled", pin: "SDA"), to: WiringPinRef(componentID: "rx-board", pin: "GPIO47"), label: "SDA", colorName: .purple),
                WiringWire(from: WiringPinRef(componentID: "rx-oled", pin: "SCL"), to: WiringPinRef(componentID: "rx-board", pin: "GPIO48"), label: "SCL", colorName: .brown),
                WiringWire(from: WiringPinRef(componentID: "rx-oled", pin: "3V3"), to: WiringPinRef(componentID: "rx-board", pin: "3V3 A"), label: "3V3", colorName: .red),
                WiringWire(from: WiringPinRef(componentID: "button", pin: "SW"), to: WiringPinRef(componentID: "rx-board", pin: "GPIO11"), label: "Button", colorName: .blue),
                WiringWire(from: WiringPinRef(componentID: "rx-battery", pin: "BAT+"), to: WiringPinRef(componentID: "rx-charger", pin: "B+"), label: "BAT+", colorName: .red),
                WiringWire(from: WiringPinRef(componentID: "rx-battery", pin: "BAT-"), to: WiringPinRef(componentID: "rx-charger", pin: "B-"), label: "BAT-", colorName: .black),
                WiringWire(from: WiringPinRef(componentID: "rx-charger", pin: "5V OUT"), to: WiringPinRef(componentID: "rx-board", pin: "5VIN"), label: "5V OUT", colorName: .red),
                WiringWire(from: WiringPinRef(componentID: "rx-ryuw", pin: "TXD"), to: WiringPinRef(componentID: "rx-board", pin: "GPIO38"), label: "RYUW TXD", colorName: .orange),
                WiringWire(from: WiringPinRef(componentID: "rx-ryuw", pin: "RXD"), to: WiringPinRef(componentID: "rx-board", pin: "GPIO39"), label: "RYUW RXD", colorName: .yellow),
                WiringWire(from: WiringPinRef(componentID: "rx-ryuw", pin: "NRST"), to: WiringPinRef(componentID: "rx-board", pin: "GPIO1"), label: "NRST", colorName: .blue),
                WiringWire(from: WiringPinRef(componentID: "rx-ryuw", pin: "VDD"), to: WiringPinRef(componentID: "rx-board", pin: "3V3 B"), label: "VDD", colorName: .red),
                WiringWire(from: WiringPinRef(componentID: "rx-oled", pin: "GND"), to: WiringPinRef(componentID: "rx-board", pin: "GND L"), label: "GND", colorName: .black),
                WiringWire(from: WiringPinRef(componentID: "button", pin: "GND"), to: WiringPinRef(componentID: "rx-board", pin: "GND L"), label: "GND", colorName: .black),
                WiringWire(from: WiringPinRef(componentID: "rx-charger", pin: "GND"), to: WiringPinRef(componentID: "rx-board", pin: "GND R1"), label: "GND", colorName: .black),
                WiringWire(from: WiringPinRef(componentID: "rx-ryuw", pin: "GND"), to: WiringPinRef(componentID: "rx-board", pin: "GND TOP"), label: "GND", colorName: .black)
            ]
        )
    ]

    func component(with id: String) -> WiringComponent? {
        components.first { $0.id == id }
    }

    func pinPoint(for ref: WiringPinRef) -> CGPoint? {
        guard let component = component(with: ref.componentID),
              let index = component.pins.firstIndex(of: ref.pin)
        else { return nil }
        return component.pinPoint(for: ref.pin, index: index, side: pinSide(for: ref))
    }

    func pinSide(for ref: WiringPinRef) -> WiringPinSide {
        guard let component = component(with: ref.componentID) else { return .right }
        if component.isESP32S3 {
            return component.physicalPinSide(for: ref.pin)
        }
        if let board = components.first(where: { $0.isESP32S3 }) {
            return board.rect.midX < component.rect.midX ? .left : .right
        }
        return .right
    }

    func pinTitle(for ref: WiringPinRef) -> String {
        guard let component = component(with: ref.componentID) else { return ref.pin }
        return "\(component.title) \(ref.pin)"
    }

    func laneOffset(for wire: WiringWire) -> CGFloat {
        let matchingWires = wires.filter { candidate in
            candidate.componentPairKey == wire.componentPairKey || candidate.boardPinKey(in: self) == wire.boardPinKey(in: self)
        }
        guard matchingWires.count > 1,
              let index = matchingWires.firstIndex(where: { $0.id == wire.id })
        else { return 0 }
        let centered = CGFloat(index) - CGFloat(matchingWires.count - 1) / 2
        return centered * 36
    }

    mutating func addWireIfPinsExist(from componentID: String, pin: String, to boardPin: String, label: String, color: WiringColor) {
        guard let board = components.first(where: { $0.isESP32S3 }),
              component(with: componentID)?.pins.contains(pin) == true,
              board.pins.contains(boardPin)
        else { return }
        let from = WiringPinRef(componentID: componentID, pin: pin)
        let to = WiringPinRef(componentID: board.id, pin: boardPin)
        guard !wires.contains(where: { ($0.from == from && $0.to == to) || ($0.from == to && $0.to == from) }) else { return }
        wires.append(WiringWire(from: from, to: to, label: label, colorName: color))
    }

    mutating func addWireIfPinsExist(from fromRef: WiringPinRef, to toRef: WiringPinRef, label: String, color: WiringColor) {
        guard component(with: fromRef.componentID)?.pins.contains(fromRef.pin) == true,
              component(with: toRef.componentID)?.pins.contains(toRef.pin) == true
        else { return }
        guard !wires.contains(where: { ($0.from == fromRef && $0.to == toRef) || ($0.from == toRef && $0.to == fromRef) }) else { return }
        wires.append(WiringWire(from: fromRef, to: toRef, label: label, colorName: color))
    }

    func suggestedRect(for item: WiringComponentLibraryItem) -> CGRect {
        guard let board = components.first(where: { $0.isESP32S3 }) else {
            return CGRect(x: 40, y: 40, width: item.size.width, height: item.size.height)
        }
        let existing = components.filter { !$0.isESP32S3 }
        let rightSide = item.preferredSide == .right
        let sideCount = existing.filter { rightSide ? $0.rect.midX > board.rect.midX : $0.rect.midX < board.rect.midX }.count
        let x = rightSide ? board.rect.maxX + 20 : board.rect.minX - item.size.width - 20
        let y = 24 + CGFloat(sideCount % 5) * (item.size.height + 18)
        return CGRect(x: x, y: y, width: item.size.width, height: item.size.height)
    }
}

private struct WiringComponent: Identifiable {
    let id: String
    var title: String
    var pins: [String]
    var rect: CGRect
    let color: Color

    var pinEditorText: String {
        get { pins.joined(separator: ", ") }
        set {
            pins = newValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    var isESP32S3: Bool {
        title.contains("ESP32-S3")
    }

    func pinPoint(for pin: String, index: Int, side: WiringPinSide) -> CGPoint {
        let sidePins = pins(for: side)
        let sideIndex = sidePins.firstIndex(of: pin) ?? index
        let count = max(1, sidePins.count)
        let topInset: CGFloat = isESP32S3 ? 33 : 34
        let bottomInset: CGFloat = isESP32S3 ? 15 : 14
        let top = rect.minY + topInset
        let bottom = rect.maxY - bottomInset
        let y: CGFloat
        if count == 1 {
            y = rect.midY
        } else {
            y = top + CGFloat(sideIndex) * ((bottom - top) / CGFloat(count - 1))
        }
        let pinDotOffset: CGFloat = isESP32S3 ? 0 : 11.5
        let x = side == .left ? rect.minX + pinDotOffset : rect.maxX - pinDotOffset
        return CGPoint(x: x, y: y)
    }

    func physicalPinSide(for pin: String) -> WiringPinSide {
        guard isESP32S3 else { return pin.contains("GPIO") ? .left : .right }
        return pins.firstIndex(of: pin).map { $0 < pins.count / 2 ? .left : .right } ?? .left
    }

    func pins(for side: WiringPinSide) -> [String] {
        guard isESP32S3 else { return pins }
        let midpoint = pins.count / 2
        if side == .left {
            return Array(pins.prefix(midpoint))
        }
        return Array(pins.suffix(from: midpoint))
    }
}

private enum WiringPinSide {
    case left
    case right
}

private enum WiringStyle {
    static let diagramBackground = Color(white: 0.78)
}

private struct WiringWire: Identifiable {
    let id: UUID
    var from: WiringPinRef
    var to: WiringPinRef
    var label: String
    var colorName: WiringColor

    init(id: UUID = UUID(), from: WiringPinRef, to: WiringPinRef, label: String, colorName: WiringColor) {
        self.id = id
        self.from = from
        self.to = to
        self.label = label
        self.colorName = colorName
    }

    var componentPairKey: String {
        [from.componentID, to.componentID].sorted().joined(separator: "::")
    }

    func boardPinKey(in diagram: WiringDiagram) -> String {
        if diagram.component(with: from.componentID)?.isESP32S3 == true {
            return "\(from.componentID)::\(from.pin)"
        }
        if diagram.component(with: to.componentID)?.isESP32S3 == true {
            return "\(to.componentID)::\(to.pin)"
        }
        return componentPairKey
    }
}

private struct WiringPinRef: Hashable {
    let componentID: String
    let pin: String
}

private enum WiringColor: String, CaseIterable, Identifiable {
    case white = "White"
    case gray = "Gray"
    case purple = "Purple"
    case blue = "Blue"
    case green = "Green"
    case yellow = "Yellow"
    case orange = "Orange"
    case brown = "Brown"
    case red = "Red"
    case black = "Black"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .white: return Color(white: 0.92)
        case .gray: return .gray
        case .purple: return .purple
        case .blue: return .blue
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .brown: return .brown
        case .red: return .red
        case .black: return .black
        }
    }
}

private struct WiringComponentLibraryItem: Identifiable {
    let id: String
    let title: String
    let symbolName: String
    let pins: [String]
    let size: CGSize
    let color: Color
    let preferredSide: WiringPinSide
    let wireRules: [String: [(pin: String, boardPin: String, label: String, color: WiringColor)]]

    func component(for diagram: WiringDiagram) -> WiringComponent {
        WiringComponent(
            id: "\(id)-\(UUID().uuidString)",
            title: title,
            pins: pins,
            rect: diagram.suggestedRect(for: self),
            color: color
        )
    }

    func addDefaultWires(componentID: String, to diagram: inout WiringDiagram) {
        let rules = wireRules[diagram.id] ?? []
        for rule in rules {
            diagram.addWireIfPinsExist(
                from: componentID,
                pin: rule.pin,
                to: rule.boardPin,
                label: rule.label,
                color: rule.color
            )
        }
    }

    func addCompanionWires(componentID: String, to diagram: inout WiringDiagram) {
        guard diagram.id == "rx" else { return }
        switch id {
        case "battery-2000mah":
            guard let charger = diagram.components.first(where: { $0.title == "USB Boost Charger" }) else { return }
            diagram.addWireIfPinsExist(from: WiringPinRef(componentID: componentID, pin: "BAT+"), to: WiringPinRef(componentID: charger.id, pin: "B+"), label: "BAT+", color: .red)
            diagram.addWireIfPinsExist(from: WiringPinRef(componentID: componentID, pin: "BAT-"), to: WiringPinRef(componentID: charger.id, pin: "B-"), label: "BAT-", color: .black)
        case "usb-boost-charger":
            guard let battery = diagram.components.first(where: { $0.title == "2000mAh 3.7V Battery" }) else { return }
            diagram.addWireIfPinsExist(from: WiringPinRef(componentID: battery.id, pin: "BAT+"), to: WiringPinRef(componentID: componentID, pin: "B+"), label: "BAT+", color: .red)
            diagram.addWireIfPinsExist(from: WiringPinRef(componentID: battery.id, pin: "BAT-"), to: WiringPinRef(componentID: componentID, pin: "B-"), label: "BAT-", color: .black)
        default:
            return
        }
    }
}

private struct WiringComponentCategory: Identifiable {
    let id: String
    let title: String
    let itemIDs: [String]
}

private enum WiringComponentLibrary {
    static let categories: [WiringComponentCategory] = [
        WiringComponentCategory(
            id: "displays",
            title: "Displays",
            itemIDs: ["oled-091", "oled-097", "oled-242", "touch-screen"]
        ),
        WiringComponentCategory(
            id: "inputs",
            title: "Inputs",
            itemIDs: ["button", "joystick", "four-button-module"]
        ),
        WiringComponentCategory(
            id: "distance-sensors",
            title: "Distance Sensors",
            itemIDs: ["luna-sensor", "garmin-sensor", "hc-sr04"]
        ),
        WiringComponentCategory(
            id: "wireless",
            title: "Wireless",
            itemIDs: ["ryuw122"]
        ),
        WiringComponentCategory(
            id: "interfaces",
            title: "Interfaces",
            itemIDs: ["max3232"]
        ),
        WiringComponentCategory(
            id: "system-power",
            title: "System / Power",
            itemIDs: ["battery-2000mah", "usb-boost-charger", "battery-sense"]
        )
    ]

    static let items: [WiringComponentLibraryItem] = [
        WiringComponentLibraryItem(
            id: "luna-sensor",
            title: "Luna Sensor",
            symbolName: "sensor",
            pins: ["TX", "RX", "VDD", "GND"],
            size: CGSize(width: 116, height: 102),
            color: .green,
            preferredSide: .left,
            wireRules: [
                "tx": [
                    ("TX", "GPIO21", "GPIO21", .green),
                    ("RX", "GPIO20", "GPIO20", .blue),
                    ("VDD", "5VIN", "VDD", .red),
                    ("GND", "GND L", "GND", .black)
                ]
            ]
        ),
        WiringComponentLibraryItem(
            id: "garmin-sensor",
            title: "Garmin LIDAR",
            symbolName: "sensor",
            pins: ["TX", "RX", "VDD", "GND"],
            size: CGSize(width: 116, height: 102),
            color: .green,
            preferredSide: .left,
            wireRules: [
                "tx": [
                    ("TX", "GPIO21", "GPIO21", .green),
                    ("RX", "GPIO20", "GPIO20", .blue),
                    ("VDD", "5VIN", "VDD", .red),
                    ("GND", "GND L", "GND", .black)
                ]
            ]
        ),
        WiringComponentLibraryItem(
            id: "hc-sr04",
            title: "HC-SR04",
            symbolName: "sensor",
            pins: ["ECHO", "TRIG", "VCC", "GND"],
            size: CGSize(width: 116, height: 102),
            color: .green,
            preferredSide: .left,
            wireRules: [
                "tx": [
                    ("TRIG", "GPIO20", "TRIG", .green),
                    ("ECHO", "GPIO21", "ECHO", .blue),
                    ("VCC", "5VIN", "VCC", .red),
                    ("GND", "GND L", "GND", .black)
                ]
            ]
        ),
        WiringComponentLibraryItem(
            id: "ryuw122",
            title: "RYUW122 Lite",
            symbolName: "antenna.radiowaves.left.and.right",
            pins: ["TXD", "RXD", "NRST", "VDD", "GND"],
            size: CGSize(width: 108, height: 112),
            color: .orange,
            preferredSide: .right,
            wireRules: [
                "tx": [
                    ("TXD", "GPIO37", "RYUW TXD", .orange),
                    ("RXD", "GPIO36", "RYUW RXD", .yellow),
                    ("NRST", "GPIO1", "NRST", .blue),
                    ("VDD", "3V3 B", "VDD", .red),
                    ("GND", "GND TOP", "GND", .black)
                ],
                "rx": [
                    ("TXD", "GPIO38", "RYUW TXD", .orange),
                    ("RXD", "GPIO39", "RYUW RXD", .yellow),
                    ("NRST", "GPIO1", "NRST", .blue),
                    ("VDD", "3V3 B", "VDD", .red),
                    ("GND", "GND TOP", "GND", .black)
                ]
            ]
        ),
        WiringComponentLibraryItem(
            id: "max3232",
            title: "MAX3232 / MDR.X",
            symbolName: "cable.connector",
            pins: ["TTL IN", "TTL OUT", "RS-232 out", "9600 8N1", "GND"],
            size: CGSize(width: 126, height: 116),
            color: .brown,
            preferredSide: .right,
            wireRules: [
                "tx": [
                    ("TTL IN", "GPIO16", "MDR IN", .blue),
                    ("TTL OUT", "GPIO15", "MDR OUT", .orange),
                    ("GND", "GND R1", "GND", .black)
                ]
            ]
        ),
        WiringComponentLibraryItem(
            id: "oled-091",
            title: "0.91 OLED",
            symbolName: "display",
            pins: ["SDA", "SCL", "3V3", "GND"],
            size: CGSize(width: 98, height: 90),
            color: .purple,
            preferredSide: .left,
            wireRules: [
                "tx": [
                    ("SDA", "GPIO40", "SDA", .purple),
                    ("SCL", "GPIO41", "SCL", .brown),
                    ("3V3", "3V3 A", "3V3", .red),
                    ("GND", "GND L", "GND", .black)
                ],
                "rx": [
                    ("SDA", "GPIO47", "SDA", .purple),
                    ("SCL", "GPIO48", "SCL", .brown),
                    ("3V3", "3V3 A", "3V3", .red),
                    ("GND", "GND L", "GND", .black)
                ]
            ]
        ),
        WiringComponentLibraryItem(
            id: "oled-097",
            title: "0.97 OLED",
            symbolName: "display",
            pins: ["SDA", "SCL", "3V3", "GND"],
            size: CGSize(width: 104, height: 94),
            color: .purple,
            preferredSide: .left,
            wireRules: [
                "tx": [
                    ("SDA", "GPIO40", "SDA", .purple),
                    ("SCL", "GPIO41", "SCL", .brown),
                    ("3V3", "3V3 A", "3V3", .red),
                    ("GND", "GND L", "GND", .black)
                ],
                "rx": [
                    ("SDA", "GPIO47", "SDA", .purple),
                    ("SCL", "GPIO48", "SCL", .brown),
                    ("3V3", "3V3 A", "3V3", .red),
                    ("GND", "GND L", "GND", .black)
                ]
            ]
        ),
        WiringComponentLibraryItem(
            id: "oled-242",
            title: "2.42 OLED",
            symbolName: "display",
            pins: ["SDA", "SCL", "3V3", "GND"],
            size: CGSize(width: 126, height: 94),
            color: .purple,
            preferredSide: .left,
            wireRules: [
                "tx": [
                    ("SDA", "GPIO40", "SDA", .purple),
                    ("SCL", "GPIO41", "SCL", .brown),
                    ("3V3", "3V3 A", "3V3", .red),
                    ("GND", "GND L", "GND", .black)
                ],
                "rx": [
                    ("SDA", "GPIO47", "SDA", .purple),
                    ("SCL", "GPIO48", "SCL", .brown),
                    ("3V3", "3V3 A", "3V3", .red),
                    ("GND", "GND L", "GND", .black)
                ]
            ]
        ),
        WiringComponentLibraryItem(
            id: "touch-screen",
            title: "2.8 Touch Screen",
            symbolName: "rectangle.and.hand.point.up.left",
            pins: ["VCC", "GND", "LCD CS", "LCD DC", "LCD RST", "SCK", "MOSI", "MISO", "CTP SDA", "CTP SCL", "CTP INT", "CTP RST"],
            size: CGSize(width: 156, height: 176),
            color: .gray,
            preferredSide: .left,
            wireRules: [
                "rx": [
                    ("VCC", "5VIN", "VCC", .red),
                    ("GND", "GND L", "GND", .black),
                    ("LCD CS", "GPIO10", "LCD CS", .green),
                    ("LCD DC", "GPIO9", "LCD DC", .blue),
                    ("LCD RST", "GPIO14", "LCD RST", .white),
                    ("SCK", "GPIO12", "SCK", .brown),
                    ("MOSI", "GPIO7", "MOSI", .purple),
                    ("MISO", "GPIO11", "MISO", .yellow),
                    ("CTP SDA", "GPIO17", "CTP SDA", .purple),
                    ("CTP SCL", "GPIO18", "CTP SCL", .brown),
                    ("CTP INT", "GPIO13", "CTP INT", .blue),
                    ("CTP RST", "GPIO15", "CTP RST", .gray)
                ]
            ]
        ),
        WiringComponentLibraryItem(
            id: "button",
            title: "Button",
            symbolName: "button.programmable",
            pins: ["SW", "GND"],
            size: CGSize(width: 98, height: 74),
            color: .blue,
            preferredSide: .left,
            wireRules: [
                "rx": [
                    ("SW", "GPIO11", "Button", .blue),
                    ("GND", "GND L", "GND", .black)
                ]
            ]
        ),
        WiringComponentLibraryItem(
            id: "joystick",
            title: "Joystick",
            symbolName: "circle.grid.cross",
            pins: ["VRX", "VRY", "SW", "VCC", "GND"],
            size: CGSize(width: 116, height: 108),
            color: .blue,
            preferredSide: .left,
            wireRules: [
                "rx": [
                    ("VRX", "GPIO4", "VRX", .green),
                    ("VRY", "GPIO5", "VRY", .blue),
                    ("SW", "GPIO11", "SW", .brown),
                    ("VCC", "3V3 A", "3V3", .red),
                    ("GND", "GND L", "GND", .black)
                ]
            ]
        ),
        WiringComponentLibraryItem(
            id: "four-button-module",
            title: "4 Button Module",
            symbolName: "square.grid.2x2",
            pins: ["K1", "K2", "K3", "K4", "GND"],
            size: CGSize(width: 126, height: 108),
            color: .blue,
            preferredSide: .left,
            wireRules: [
                "rx": [
                    ("K1", "GPIO4", "K1", .green),
                    ("K2", "GPIO5", "K2", .blue),
                    ("K3", "GPIO10", "K3", .purple),
                    ("K4", "GPIO11", "K4", .brown),
                    ("GND", "GND L", "GND", .black)
                ]
            ]
        ),
        WiringComponentLibraryItem(
            id: "battery-2000mah",
            title: "2000mAh 3.7V Battery",
            symbolName: "battery.100",
            pins: ["BAT+", "BAT-"],
            size: CGSize(width: 140, height: 84),
            color: .red,
            preferredSide: .right,
            wireRules: [
                "rx": [
                    ("BAT+", "B+", "BAT+", .red),
                    ("BAT-", "B-", "BAT-", .black)
                ]
            ]
        ),
        WiringComponentLibraryItem(
            id: "usb-boost-charger",
            title: "USB Boost Charger",
            symbolName: "bolt.batteryblock",
            pins: ["B+", "B-", "5V OUT", "GND", "USB"],
            size: CGSize(width: 142, height: 116),
            color: .gray,
            preferredSide: .right,
            wireRules: [
                "rx": [
                    ("5V OUT", "5VIN", "5V OUT", .red),
                    ("GND", "GND R1", "GND", .black)
                ]
            ]
        ),
        WiringComponentLibraryItem(
            id: "battery-sense",
            title: "Battery Sense",
            symbolName: "battery.100",
            pins: ["Divider", "ADC", "GND"],
            size: CGSize(width: 110, height: 88),
            color: .gray,
            preferredSide: .right,
            wireRules: [
                "rx": [
                    ("ADC", "GPIO16", "ADC", .gray),
                    ("GND", "GND R1", "GND", .black)
                ]
            ]
        )
    ]

    static func items(for category: WiringComponentCategory) -> [WiringComponentLibraryItem] {
        category.itemIDs.compactMap { itemID in
            items.first { $0.id == itemID }
        }
    }
}

private struct WiringPromptResult {
    var diagram: WiringDiagram
    var messages: [String]
    var hasChanges: Bool
}

private enum WiringPromptEngine {
    static func preview(prompt: String, diagram: WiringDiagram) -> WiringPromptResult {
        var updatedDiagram = diagram
        var messages: [String] = []
        var didChange = false
        let commands = splitCommands(prompt)

        for command in commands {
            if applyAddCommand(command, to: &updatedDiagram, messages: &messages) {
                didChange = true
            }
            if applyWireCommand(command, to: &updatedDiagram, messages: &messages) {
                didChange = true
            }
            if applyMoveCommand(command, to: &updatedDiagram, messages: &messages) {
                didChange = true
            }
            if applyColorCommand(command, to: &updatedDiagram, messages: &messages) {
                didChange = true
            }
        }

        if messages.isEmpty {
            messages.append("No changes found. Try commands like: add RYUW, wire RYUW TXD to GPIO37, move OLED below ESP32, make SDA wire yellow.")
        }

        return WiringPromptResult(diagram: updatedDiagram, messages: messages, hasChanges: didChange)
    }

    private static func splitCommands(_ prompt: String) -> [String] {
        prompt
            .replacingOccurrences(of: "\n", with: ".")
            .split(whereSeparator: { ".;".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func applyAddCommand(_ command: String, to diagram: inout WiringDiagram, messages: inout [String]) -> Bool {
        let lower = command.lowercased()
        guard lower.contains("add") || lower.contains("create") else { return false }
        guard let template = componentTemplate(for: lower, count: diagram.components.count + 1) else { return false }
        if diagram.components.contains(where: { componentMatches($0, phrase: template.title) }) {
            messages.append("\(template.title) is already on the \(diagram.title) diagram.")
            return false
        }
        diagram.components.append(template)
        messages.append("Added \(template.title).")
        return true
    }

    private static func applyWireCommand(_ command: String, to diagram: inout WiringDiagram, messages: inout [String]) -> Bool {
        let lower = command.lowercased()
        guard lower.contains("wire") || lower.contains("connect") else { return false }
        let contextComponent = preferredComponent(in: diagram, from: lower)
        var didChange = false

        for pair in pinPairs(in: command) {
            guard let from = pinRef(for: pair.from, preferredComponent: contextComponent, in: diagram),
                  let to = pinRef(for: pair.to, preferredComponent: nil, in: diagram)
            else {
                messages.append("Could not find pins for \(pair.from) -> \(pair.to).")
                continue
            }
            if diagram.wires.contains(where: { ($0.from == from && $0.to == to) || ($0.from == to && $0.to == from) }) {
                messages.append("\(diagram.pinTitle(for: from)) is already wired to \(diagram.pinTitle(for: to)).")
                continue
            }
            let color = colorForPins(from.pin, to.pin)
            let label = "\(shortPinName(from.pin)) -> \(shortPinName(to.pin))"
            diagram.wires.append(WiringWire(from: from, to: to, label: label, colorName: color))
            messages.append("Wired \(diagram.pinTitle(for: from)) to \(diagram.pinTitle(for: to)).")
            didChange = true
        }

        return didChange
    }

    private static func applyMoveCommand(_ command: String, to diagram: inout WiringDiagram, messages: inout [String]) -> Bool {
        let lower = command.lowercased()
        guard lower.contains("move") else { return false }
        guard let movingIndex = diagram.components.firstIndex(where: { componentMatches($0, phrase: lower) }) else { return false }
        let targetIndex = diagram.components.firstIndex { component in
            component.id != diagram.components[movingIndex].id && (component.isESP32S3 || componentMatches(component, phrase: lower))
        } ?? 0
        let target = diagram.components[targetIndex].rect
        var rect = diagram.components[movingIndex].rect
        let gap: CGFloat = 24

        if lower.contains("below") || lower.contains("under") {
            rect.origin = CGPoint(x: target.midX - rect.width / 2, y: target.maxY + gap)
        } else if lower.contains("above") || lower.contains("top") {
            rect.origin = CGPoint(x: target.midX - rect.width / 2, y: target.minY - rect.height - gap)
        } else if lower.contains("left") {
            rect.origin = CGPoint(x: target.minX - rect.width - gap, y: target.midY - rect.height / 2)
        } else if lower.contains("right") {
            rect.origin = CGPoint(x: target.maxX + gap, y: target.midY - rect.height / 2)
        } else {
            return false
        }

        diagram.components[movingIndex].rect = rect
        messages.append("Moved \(diagram.components[movingIndex].title).")
        return true
    }

    private static func applyColorCommand(_ command: String, to diagram: inout WiringDiagram, messages: inout [String]) -> Bool {
        let lower = command.lowercased()
        guard lower.contains("wire"),
              let color = WiringColor.allCases.first(where: { lower.contains($0.rawValue.lowercased()) })
        else { return false }
        let keywords = lower
            .replacingOccurrences(of: "wire", with: "")
            .replacingOccurrences(of: "make", with: "")
            .replacingOccurrences(of: "change", with: "")
            .replacingOccurrences(of: "color", with: "")
            .replacingOccurrences(of: color.rawValue.lowercased(), with: "")
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 }
        guard let index = diagram.wires.firstIndex(where: { wire in
            let haystack = "\(wire.label) \(wire.from.pin) \(wire.to.pin)".lowercased()
            return keywords.contains(where: { haystack.contains($0) })
        }) else { return false }
        diagram.wires[index].colorName = color
        messages.append("Changed \(diagram.wires[index].label) to \(color.rawValue).")
        return true
    }

    private static func componentTemplate(for lower: String, count: Int) -> WiringComponent? {
        let id = "custom-\(UUID().uuidString)"
        let x = 36 + CGFloat((count % 3) * 126)
        let y = 548 + CGFloat((count / 3) * 100)

        if lower.contains("ryuw") || lower.contains("uwb") {
            return WiringComponent(id: id, title: "RYUW122 Lite", pins: ["TXD", "RXD", "NRST", "VDD", "GND"], rect: CGRect(x: x, y: y, width: 108, height: 112), color: .orange)
        }
        if lower.contains("touch") || lower.contains("screen") || lower.contains("2.8") {
            return WiringComponent(id: id, title: "2.8 Touch Screen", pins: ["VCC", "GND", "LCD CS", "LCD DC", "LCD RST", "SCK", "MOSI", "MISO", "CTP SDA", "CTP SCL", "CTP INT", "CTP RST"], rect: CGRect(x: x, y: y, width: 156, height: 188), color: .gray)
        }
        if lower.contains("2.42") || lower.contains("242") {
            return WiringComponent(id: id, title: "2.42 OLED", pins: ["SDA", "SCL", "3V3", "GND"], rect: CGRect(x: x, y: y, width: 126, height: 94), color: .purple)
        }
        if lower.contains(".91") || lower.contains("0.91") || lower.contains("091") {
            return WiringComponent(id: id, title: "0.91 OLED", pins: ["SDA", "SCL", "3V3", "GND"], rect: CGRect(x: x, y: y, width: 98, height: 90), color: .purple)
        }
        if lower.contains("oled") || lower.contains("display") || lower.contains(".97") || lower.contains("0.97") {
            return WiringComponent(id: id, title: "0.97 OLED", pins: ["SDA", "SCL", "3V3", "GND"], rect: CGRect(x: x, y: y, width: 104, height: 94), color: .purple)
        }
        if lower.contains("max3232") || lower.contains("mdr") || lower.contains("rs-232") {
            return WiringComponent(id: id, title: "MAX3232 / MDR.X", pins: ["TTL IN", "TTL OUT", "RS-232 out", "9600 8N1", "GND"], rect: CGRect(x: x, y: y, width: 126, height: 116), color: .brown)
        }
        if lower.contains("sr04") || lower.contains("hc-sr04") || lower.contains("ultrasonic") {
            return WiringComponent(id: id, title: "HC-SR04", pins: ["ECHO", "TRIG", "VCC", "GND"], rect: CGRect(x: x, y: y, width: 116, height: 102), color: .green)
        }
        if lower.contains("garmin") {
            return WiringComponent(id: id, title: "Garmin LIDAR", pins: ["TX", "RX", "VDD", "GND"], rect: CGRect(x: x, y: y, width: 116, height: 102), color: .green)
        }
        if lower.contains("sensor") || lower.contains("luna") {
            return WiringComponent(id: id, title: "Luna Sensor", pins: ["TX", "RX", "VDD", "GND"], rect: CGRect(x: x, y: y, width: 116, height: 102), color: .green)
        }
        if lower.contains("boost") || lower.contains("charger") || lower.contains("usb power") {
            return WiringComponent(id: id, title: "USB Boost Charger", pins: ["B+", "B-", "5V OUT", "GND", "USB"], rect: CGRect(x: x, y: y, width: 142, height: 116), color: .gray)
        }
        if lower.contains("2000") || lower.contains("mah") || lower.contains("3.7") || lower.contains("battery pack") {
            return WiringComponent(id: id, title: "2000mAh 3.7V Battery", pins: ["BAT+", "BAT-"], rect: CGRect(x: x, y: y, width: 140, height: 84), color: .red)
        }
        if lower.contains("battery") || lower.contains("voltage") {
            return WiringComponent(id: id, title: "Battery Sense", pins: ["Divider", "ADC", "GND"], rect: CGRect(x: x, y: y, width: 110, height: 88), color: .gray)
        }
        if lower.contains("joystick") || lower.contains("thumbstick") {
            return WiringComponent(id: id, title: "Joystick", pins: ["VRX", "VRY", "SW", "VCC", "GND"], rect: CGRect(x: x, y: y, width: 116, height: 108), color: .blue)
        }
        if lower.contains("4 button") || lower.contains("four button") || lower.contains("button module") {
            return WiringComponent(id: id, title: "4 Button Module", pins: ["K1", "K2", "K3", "K4", "GND"], rect: CGRect(x: x, y: y, width: 126, height: 108), color: .blue)
        }
        if lower.contains("button") || lower.contains("key") {
            return WiringComponent(id: id, title: "Button", pins: ["SW", "GND"], rect: CGRect(x: x, y: y, width: 98, height: 74), color: .blue)
        }
        return nil
    }

    private static func pinPairs(in command: String) -> [(from: String, to: String)] {
        let cleaned = command
            .replacingOccurrences(of: "wire", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "connect", with: "", options: [.caseInsensitive])
        return cleaned
            .components(separatedBy: ",")
            .compactMap { chunk in
                let parts = chunk.components(separatedBy: " to ")
                guard parts.count == 2 else { return nil }
                let from = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let to = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !from.isEmpty, !to.isEmpty else { return nil }
                return (from, to)
            }
    }

    private static func preferredComponent(in diagram: WiringDiagram, from lower: String) -> WiringComponent? {
        diagram.components.first { component in
            !component.isESP32S3 && componentMatches(component, phrase: lower)
        }
    }

    private static func pinRef(for phrase: String, preferredComponent: WiringComponent?, in diagram: WiringDiagram) -> WiringPinRef? {
        if let preferredComponent, let pin = matchingPin(in: preferredComponent, phrase: phrase) {
            return WiringPinRef(componentID: preferredComponent.id, pin: pin)
        }
        let boardFirst = phrase.lowercased().contains("gpio") || phrase.lowercased().contains("3v") || phrase.lowercased().contains("5v") || phrase.lowercased().contains("gnd")
        let components = boardFirst ? diagram.components.sorted { $0.isESP32S3 && !$1.isESP32S3 } : diagram.components
        for component in components {
            if let pin = matchingPin(in: component, phrase: phrase) {
                return WiringPinRef(componentID: component.id, pin: pin)
            }
        }
        return nil
    }

    private static func matchingPin(in component: WiringComponent, phrase: String) -> String? {
        let normalizedPhrase = normalized(phrase)
        return component.pins.first { normalized($0) == normalizedPhrase }
            ?? component.pins.first { normalized($0).contains(normalizedPhrase) || normalizedPhrase.contains(normalized($0)) }
            ?? component.pins.first { pin in
                let firstToken = normalized(pin).split(separator: " ").first.map(String.init) ?? ""
                return !firstToken.isEmpty && normalizedPhrase.contains(firstToken)
            }
    }

    private static func componentMatches(_ component: WiringComponent, phrase: String) -> Bool {
        let text = normalized("\(component.id) \(component.title)")
        let phrase = normalized(phrase)
        if component.isESP32S3 && (phrase.contains("esp32") || phrase.contains("board")) { return true }
        if text.contains("ryuw") && (phrase.contains("ryuw") || phrase.contains("uwb")) { return true }
        if text.contains("oled") && (phrase.contains("oled") || phrase.contains("display")) { return true }
        if text.contains("sensor") && (phrase.contains("sensor") || phrase.contains("luna") || phrase.contains("garmin")) { return true }
        if text.contains("mdr") && (phrase.contains("mdr") || phrase.contains("max3232")) { return true }
        if text.contains("battery") && (phrase.contains("battery") || phrase.contains("voltage")) { return true }
        if text.contains("button") && (phrase.contains("button") || phrase.contains("key")) { return true }
        return text.split(separator: " ").contains { phrase.contains($0) }
    }

    private static func colorForPins(_ first: String, _ second: String) -> WiringColor {
        let lower = "\(first) \(second)".lowercased()
        if lower.contains("gnd") { return .black }
        if lower.contains("vdd") || lower.contains("3v") || lower.contains("5v") { return .red }
        if lower.contains("sda") { return .purple }
        if lower.contains("scl") { return .brown }
        if lower.contains("tx") { return .orange }
        if lower.contains("rx") { return .yellow }
        return .green
    }

    private static func shortPinName(_ pin: String) -> String {
        pin.split(separator: " ").first.map(String.init) ?? pin
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "->", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct WiringDiagramEditorCanvas: View {
    @Binding var diagram: WiringDiagram
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    let selectedColor: WiringColor
    let label: String
    @Binding var pendingPin: WiringPinRef?
    @Binding var selectedComponentID: String?
    @Binding var selectedWireID: UUID?
    @State private var panStart = CGSize.zero
    @State private var pinchStartScale: CGFloat?

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                WiringStyle.diagramBackground
                    .overlay(WiringGrid().stroke(Color.black.opacity(0.12), lineWidth: 1))

                ZStack(alignment: .topLeading) {
                    ForEach(diagram.wires) { wire in
                        WiringWirePath(
                            wire: wire,
                            diagram: diagram,
                            isSelected: selectedWireID == wire.id
                        ) {
                            selectedWireID = wire.id
                            selectedComponentID = nil
                        }
                    }

                    ForEach($diagram.components) { $component in
                        WiringEditableComponentBox(
                            component: $component,
                            diagram: diagram,
                            scale: scale,
                            pendingPin: $pendingPin,
                            selectedComponentID: $selectedComponentID,
                            onPinTap: handlePinTap
                        )
                    }
                }
                .frame(width: 760, height: 540, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .offset(offset)
            }
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
            .clipShape(Rectangle())
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                offset = CGSize(width: panStart.width + value.translation.width, height: panStart.height + value.translation.height)
            }
            .onEnded { _ in
                panStart = offset
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if pinchStartScale == nil {
                    pinchStartScale = scale
                }
                let base = pinchStartScale ?? scale
                scale = min(2.5, max(0.35, base * value))
            }
            .onEnded { _ in
                pinchStartScale = nil
            }
    }

    private func handlePinTap(_ ref: WiringPinRef) {
        if let pendingPin {
            guard pendingPin != ref else {
                self.pendingPin = nil
                return
            }
            let defaultLabel = label.isEmpty ? "\(pendingPin.pin) -> \(ref.pin)" : label
            diagram.wires.append(WiringWire(from: pendingPin, to: ref, label: defaultLabel, colorName: selectedColor))
            selectedWireID = diagram.wires.last?.id
            self.pendingPin = nil
        } else {
            pendingPin = ref
        }
    }
}

private struct WiringWirePath: View {
    let wire: WiringWire
    let diagram: WiringDiagram
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        if let from = diagram.pinPoint(for: wire.from), let to = diagram.pinPoint(for: wire.to) {
            let laneOffset = diagram.laneOffset(for: wire)
            ZStack(alignment: .topLeading) {
                wirePath(from: from, to: to, laneOffset: laneOffset)
                    .stroke(wire.colorName.color, style: StrokeStyle(lineWidth: isSelected ? 5 : 3, lineCap: .round, lineJoin: .round))

                wirePath(from: from, to: to, laneOffset: laneOffset)
                    .stroke(Color.primary.opacity(0.001), style: StrokeStyle(lineWidth: 28, lineCap: .round, lineJoin: .round))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)

                if isSelected {
                    Circle()
                        .fill(wire.colorName.color)
                        .frame(width: 8, height: 8)
                        .offset(x: min(from.x, to.x) + abs(from.x - to.x) / 2 + laneOffset - 4,
                                y: min(from.y, to.y) + abs(from.y - to.y) / 2 - 4)
                }
            }
        }
    }

    private func wirePath(from: CGPoint, to: CGPoint, laneOffset: CGFloat) -> Path {
        Path { path in
            let points = routePoints(from: from, to: to, laneOffset: laneOffset)
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func routePoints(from: CGPoint, to: CGPoint, laneOffset: CGFloat) -> [CGPoint] {
        guard let fromComponent = diagram.component(with: wire.from.componentID),
              let toComponent = diagram.component(with: wire.to.componentID)
        else {
            return defaultRoute(from: from, to: to, laneOffset: laneOffset)
        }

        if toComponent.isESP32S3,
           shouldRouteAroundBoard(board: toComponent, boardRef: wire.to, otherComponent: fromComponent) {
            return routeAroundBoard(from: from, to: to, board: toComponent, boardRef: wire.to, laneOffset: laneOffset)
        }

        if fromComponent.isESP32S3,
           shouldRouteAroundBoard(board: fromComponent, boardRef: wire.from, otherComponent: toComponent) {
            return routeAroundBoardFromBoard(from: from, to: to, board: fromComponent, boardRef: wire.from, laneOffset: laneOffset)
        }

        return defaultRoute(from: from, to: to, laneOffset: laneOffset)
    }

    private func shouldRouteAroundBoard(board: WiringComponent, boardRef: WiringPinRef, otherComponent: WiringComponent) -> Bool {
        let side = diagram.pinSide(for: boardRef)
        return (otherComponent.rect.midX < board.rect.midX && side == .right)
            || (otherComponent.rect.midX > board.rect.midX && side == .left)
    }

    private func routeAroundBoard(from: CGPoint, to: CGPoint, board: WiringComponent, boardRef: WiringPinRef, laneOffset: CGFloat) -> [CGPoint] {
        let side = diagram.pinSide(for: boardRef)
        let clearance: CGFloat = 24 + abs(laneOffset)
        let outsideX = side == .right ? board.rect.maxX + clearance : board.rect.minX - clearance
        let trackY = board.rect.minY - 16 - abs(laneOffset) * 0.25 - boardBypassTrackOffset(board: board, boardRef: boardRef)
        let exitX = from.x + componentExitDirection(from: from, to: to) * (22 + abs(laneOffset) * 0.35)
        return [
            from,
            CGPoint(x: exitX, y: from.y),
            CGPoint(x: exitX, y: trackY),
            CGPoint(x: outsideX, y: trackY),
            CGPoint(x: outsideX, y: to.y),
            to
        ]
    }

    private func routeAroundBoardFromBoard(from: CGPoint, to: CGPoint, board: WiringComponent, boardRef: WiringPinRef, laneOffset: CGFloat) -> [CGPoint] {
        let side = diagram.pinSide(for: boardRef)
        let clearance: CGFloat = 24 + abs(laneOffset)
        let outsideX = side == .right ? board.rect.maxX + clearance : board.rect.minX - clearance
        let trackY = board.rect.minY - 16 - abs(laneOffset) * 0.25 - boardBypassTrackOffset(board: board, boardRef: boardRef)
        let entryX = to.x + componentExitDirection(from: to, to: from) * (22 + abs(laneOffset) * 0.35)
        return [
            from,
            CGPoint(x: outsideX, y: from.y),
            CGPoint(x: outsideX, y: trackY),
            CGPoint(x: entryX, y: trackY),
            CGPoint(x: entryX, y: to.y),
            to
        ]
    }

    private func defaultRoute(from: CGPoint, to: CGPoint, laneOffset: CGFloat) -> [CGPoint] {
        let fromExitX = from.x + componentExitDirection(from: from, to: to) * (20 + abs(laneOffset) * 0.35)
        let toExitX = to.x + componentExitDirection(from: to, to: from) * (20 + abs(laneOffset) * 0.35)
        if abs(from.x - to.x) < 56 {
            let verticalX = (fromExitX + to.x) / 2 + laneOffset
            return [
                from,
                CGPoint(x: fromExitX, y: from.y),
                CGPoint(x: verticalX, y: from.y),
                CGPoint(x: verticalX, y: to.y),
                to
            ]
        }
        let midX = (fromExitX + toExitX) / 2 + laneOffset
        return [
            from,
            CGPoint(x: fromExitX, y: from.y),
            CGPoint(x: midX, y: from.y),
            CGPoint(x: midX, y: to.y),
            CGPoint(x: toExitX, y: to.y),
            to
        ]
    }

    private func componentExitDirection(from: CGPoint, to: CGPoint) -> CGFloat {
        to.x >= from.x ? 1 : -1
    }

    private func boardBypassTrackOffset(board: WiringComponent, boardRef: WiringPinRef) -> CGFloat {
        let side = diagram.pinSide(for: boardRef)
        let sidePins = board.pins(for: side)
        let index = sidePins.firstIndex(of: boardRef.pin) ?? 0
        return CGFloat(index % 12) * 18
    }
}

private struct WiringEditableComponentBox: View {
    @Binding var component: WiringComponent
    let diagram: WiringDiagram
    let scale: CGFloat
    @Binding var pendingPin: WiringPinRef?
    @Binding var selectedComponentID: String?
    let onPinTap: (WiringPinRef) -> Void
    @State private var dragStart = CGPoint.zero
    @State private var isDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(component.title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if component.isESP32S3 {
                esp32PinGrid
            } else {
                componentPinGrid
            }
        }
        .padding(7)
        .frame(width: component.rect.width, height: component.rect.height, alignment: .topLeading)
        .background(component.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(selectedComponentID == component.id ? Color.primary : component.color, lineWidth: selectedComponentID == component.id ? 2.5 : 1.5)
        )
        .offset(x: component.rect.minX, y: component.rect.minY)
        .onTapGesture {
            selectedComponentID = component.id
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard !component.isESP32S3 else { return }
                    if !isDragging {
                        dragStart = component.rect.origin
                        isDragging = true
                    }
                    component.rect.origin = CGPoint(
                        x: dragStart.x + value.translation.width / scale,
                        y: dragStart.y + value.translation.height / scale
                    )
                    selectedComponentID = component.id
                }
                .onEnded { _ in
                    guard !component.isESP32S3 else { return }
                    dragStart = component.rect.origin
                    isDragging = false
                }
        )
    }

    private func pinColor(for pin: String) -> Color {
        let ref = WiringPinRef(componentID: component.id, pin: pin)
        return pendingPin == ref ? .primary : component.color
    }

    private func pinRow(_ pin: String) -> some View {
        let ref = WiringPinRef(componentID: component.id, pin: pin)
        let side = diagram.pinSide(for: ref)
        return HStack(spacing: 4) {
            if side == .right { Spacer(minLength: 0) }
            if side == .left { pinButton(for: pin) }
            Text(pin)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .multilineTextAlignment(side == .left ? .leading : .trailing)
            if side == .right { pinButton(for: pin) }
            if side == .left { Spacer(minLength: 0) }
        }
    }

    private func pinButton(for pin: String) -> some View {
        Button {
            onPinTap(WiringPinRef(componentID: component.id, pin: pin))
        } label: {
            Circle()
                .fill(pinColor(for: pin))
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var componentPinGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(component.pins.enumerated()), id: \.offset) { index, pin in
                pinRow(pin)

                if index < component.pins.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var esp32PinGrid: some View {
        HStack(alignment: .top, spacing: 6) {
            esp32PinColumn(component.pins(for: .left), side: .left)

            Spacer(minLength: 0)

            esp32PinColumn(component.pins(for: .right), side: .right)
        }
        .frame(maxHeight: .infinity)
    }

    private func esp32PinColumn(_ pins: [String], side: WiringPinSide) -> some View {
        VStack(alignment: side == .left ? .leading : .trailing, spacing: 0) {
            ForEach(Array(pins.enumerated()), id: \.element) { index, pin in
                esp32PinRow(pin, side: side)

                if index < pins.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func esp32PinRow(_ pin: String, side: WiringPinSide) -> some View {
        HStack(spacing: 2) {
            if side == .left { pinButton(for: pin) }
            Text(pin)
                .font(.system(size: 6, weight: .medium, design: .monospaced))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .frame(maxWidth: 68, alignment: side == .left ? .leading : .trailing)
            if side == .right { pinButton(for: pin) }
        }
        .frame(height: 9)
    }
}

private struct WiringDiagramExportImage: View {
    let diagram: WiringDiagram

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DigiTape \(diagram.title) Wiring")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            ZStack(alignment: .topLeading) {
                WiringStyle.diagramBackground
                    .overlay(WiringGrid().stroke(Color.black.opacity(0.12), lineWidth: 1))

                ForEach(diagram.wires) { wire in
                    WiringWirePath(wire: wire, diagram: diagram, isSelected: false) {}
                }

                ForEach(diagram.components) { component in
                    WiringStaticComponentBox(component: component, diagram: diagram)
                }
            }
            .frame(width: 760, height: 540, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
            )
        }
        .padding(24)
        .frame(width: 820, height: 620, alignment: .topLeading)
        .background(WiringStyle.diagramBackground)
    }
}

private struct WiringStaticComponentBox: View {
    let component: WiringComponent
    let diagram: WiringDiagram

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(component.title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if component.isESP32S3 {
                esp32PinGrid
            } else {
                componentPinGrid
            }
        }
        .padding(7)
        .frame(width: component.rect.width, height: component.rect.height, alignment: .topLeading)
        .background(component.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(component.color, lineWidth: 1.5)
        )
        .offset(x: component.rect.minX, y: component.rect.minY)
    }

    private func pinDot() -> some View {
        Circle()
            .fill(component.color)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
    }

    private func pinRow(_ pin: String) -> some View {
        let ref = WiringPinRef(componentID: component.id, pin: pin)
        let side = diagram.pinSide(for: ref)
        return HStack(spacing: 4) {
            if side == .right { Spacer(minLength: 0) }
            if side == .left { pinDot() }
            Text(pin)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .multilineTextAlignment(side == .left ? .leading : .trailing)
            if side == .right { pinDot() }
            if side == .left { Spacer(minLength: 0) }
        }
    }

    private var componentPinGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(component.pins.enumerated()), id: \.offset) { index, pin in
                pinRow(pin)

                if index < component.pins.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var esp32PinGrid: some View {
        HStack(alignment: .top, spacing: 6) {
            esp32PinColumn(component.pins(for: .left), side: .left)

            Spacer(minLength: 0)

            esp32PinColumn(component.pins(for: .right), side: .right)
        }
        .frame(maxHeight: .infinity)
    }

    private func esp32PinColumn(_ pins: [String], side: WiringPinSide) -> some View {
        VStack(alignment: side == .left ? .leading : .trailing, spacing: 0) {
            ForEach(Array(pins.enumerated()), id: \.element) { index, pin in
                HStack(spacing: 2) {
                    if side == .left { pinDot() }
                    Text(pin)
                        .font(.system(size: 6, weight: .medium, design: .monospaced))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .frame(maxWidth: 68, alignment: side == .left ? .leading : .trailing)
                    if side == .right { pinDot() }
                }
                .frame(height: 9)

                if index < pins.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct WiringGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 24
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += step
        }

        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += step
        }
        return path
    }
}

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var ble: DigiTapeBLEManager
    @State private var firmwareTarget = "RX"
    @State private var selectedFirmwareID: String?

    private var firmwareChoices: [FirmwareManifest.FirmwareFile] {
        ble.availableFirmware.filter { firmwareMatchesTarget($0, target: firmwareTarget) }
    }

    private var selectedFirmware: FirmwareManifest.FirmwareFile? {
        if let selectedFirmwareID,
           let selected = firmwareChoices.first(where: { $0.id == selectedFirmwareID }) {
            return selected
        }
        return firmwareChoices.first
    }

    private var isSelectedRouteConnected: Bool {
        ble.connectionRoute == firmwareTarget
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Firmware Update") {
                    Picker("Target", selection: $firmwareTarget) {
                        Label("RX", systemImage: "display").tag("RX")
                        Label("TX", systemImage: "antenna.radiowaves.left.and.right").tag("TX")
                    }
                    .pickerStyle(.segmented)
                    .disabled(ble.otaInProgress)
                    .onChange(of: firmwareTarget) { _, _ in
                        selectedFirmwareID = nil
                    }

                    diagRow("Installed", ble.installedFirmwareVersion(for: firmwareTarget))
                    diagRow("Cloud", firmwareStatusText)
                    if ble.otaInProgress {
                        ProgressView(value: ble.otaProgress)
                    }

                    Button {
                        if isSelectedRouteConnected {
                            if let selectedFirmware {
                                ble.downloadAndUpdateFirmware(selectedFirmware)
                            }
                        } else {
                            ble.switchConnectionRoute(to: firmwareTarget)
                        }
                    } label: {
                        Label(primaryFirmwareButtonTitle, systemImage: primaryFirmwareButtonIcon)
                    }
                    .disabled(primaryFirmwareButtonDisabled)

                    if ble.otaInProgress {
                        Button("Abort Update", role: .destructive) {
                            ble.abortFirmwareUpdate()
                        }
                    }
                }

                Section("Connection") {
                    diagRow("Route", ble.connectionRoute)
                    diagRow("State", ble.linkOK ? "Live" : "No data")
                    diagRow("Status", ble.status)
                    diagRow("Signal", "\(ble.signalPercent)%")
                    diagRow("RSSI", "\(ble.rssi) dBm")
                    diagRow("Sensor", ble.linkOK ? ble.sensorType.label : "--")
                    diagRow("Packet", "\(ble.packetCounter)")

                    Button {
                        toggleConnection()
                    } label: {
                        Label(connectionButtonTitle, systemImage: connectionButtonIcon)
                    }
                    .disabled(ble.isScanning)

                    Button {
                        ble.switchConnectionRoute()
                    } label: {
                        Label("Switch to \(alternateRoute)", systemImage: routeIcon(for: alternateRoute))
                    }
                    .disabled(ble.otaInProgress)
                }

                Section("TAG / RYUW") {
                    diagRow("UWB", ble.uwbStatus)
                    diagRow("Link", ble.tagLinkText)
                    diagRow("Route Lock", ble.txRouteLockText)
                    diagRow("Packet Age", ble.packetAgeText)
                }
            }
            .navigationTitle("Diagnostics")
            .onAppear {
                ble.checkCloudFirmwareIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var firmwareStatusText: String {
        if ble.otaInProgress { return ble.otaStatus }
        if ble.isCheckingCloudFirmware { return "Checking GitHub..." }
        if ble.isDownloadingFirmware { return ble.cloudFirmwareStatus }
        if let selectedFirmware {
            return "\(firmwareDisplayName(selectedFirmware)) available"
        }
        return ble.cloudFirmwareStatus
    }

    private var primaryFirmwareButtonTitle: String {
        if !isSelectedRouteConnected { return "Connect to \(firmwareTarget)" }
        if let selectedFirmware { return "Update \(firmwareDisplayName(selectedFirmware))" }
        if ble.isCheckingCloudFirmware { return "Checking Updates" }
        return "No Firmware Available"
    }

    private var primaryFirmwareButtonIcon: String {
        isSelectedRouteConnected ? "icloud.and.arrow.down" : routeIcon(for: firmwareTarget)
    }

    private var primaryFirmwareButtonDisabled: Bool {
        ble.otaInProgress ||
        ble.isDownloadingFirmware ||
        ble.isCheckingCloudFirmware ||
        (isSelectedRouteConnected && (!ble.otaReady || selectedFirmware == nil))
    }

    private var connectionButtonTitle: String {
        if ble.isScanning { return "Scanning..." }
        if ble.isConnected && !ble.emulatorMode { return "Disconnect" }
        return "Connect"
    }

    private var connectionButtonIcon: String {
        if ble.isScanning { return "dot.radiowaves.left.and.right" }
        if ble.isConnected && !ble.emulatorMode { return "xmark" }
        return "antenna.radiowaves.left.and.right"
    }

    private var alternateRoute: String {
        ble.connectionRoute == "TX" ? "RX" : "TX"
    }

    private func toggleConnection() {
        if ble.isConnected && !ble.emulatorMode {
            ble.disconnect()
        } else {
            ble.startLiveMode()
        }
    }

    private func routeIcon(for route: String) -> String {
        route == "TX" ? "antenna.radiowaves.left.and.right" : "display"
    }

    private func firmwareMatchesTarget(_ firmware: FirmwareManifest.FirmwareFile, target: String) -> Bool {
        let normalizedTarget = target.uppercased()
        let normalizedFirmware = firmware.target
            .uppercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return normalizedFirmware == normalizedTarget || normalizedFirmware.hasPrefix("\(normalizedTarget)_")
    }

    private func firmwareDisplayName(_ firmware: FirmwareManifest.FirmwareFile) -> String {
        let normalized = firmware.target
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let words = normalized
            .split(separator: " ")
            .map { word in String(word.prefix(1)).uppercased() + String(word.dropFirst()).lowercased() }
            .joined(separator: " ")
        return "\(words) \(firmware.version)"
    }

    private func diagRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}
struct SignalBars: View {
    let percent: Int
    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(0..<5) { index in
                let filledBars = filledBars
                let barHeight = CGFloat(3 + index * 2)
                Rectangle()
                    .strokeBorder(lineWidth: index < filledBars ? 0 : 1)
                    .background(Rectangle().fill(index < filledBars ? OLEDTheme.pixel : Color.clear))
                    .frame(width: 2.5, height: barHeight)
            }
        }
        .frame(width: 22, height: 11, alignment: .bottom)
    }

    private var filledBars: Int {
        if percent >= 80 { return 5 }
        if percent >= 60 { return 4 }
        if percent >= 40 { return 3 }
        if percent >= 20 { return 2 }
        if percent > 0 { return 1 }
        return 0
    }
}

struct OLEDCheckMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

struct BatteryIcon: View {
    let percent: Int
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().stroke(lineWidth: 1).frame(width: 20, height: 8)
            Rectangle().frame(width: fillWidth, height: 4).offset(x: 2)
            Rectangle().frame(width: 2, height: 4).offset(x: 20)
        }
        .frame(width: 23, height: 10)
    }

    private var fillWidth: CGFloat {
        max(0, min(16, CGFloat(percent) / 100 * 16))
    }
}

private extension String {
    var compactDistance: String {
        replacingOccurrences(of: " ", with: "")
    }
}

private extension ResponseMode {
    var shortLabel: String {
        switch self {
        case .fast: return "FAST"
        case .normal: return "NORM"
        case .avg: return "SMTH"
        case .slow: return "SLOW"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
