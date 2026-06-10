import SwiftUI
import UniformTypeIdentifiers

enum RXScreen: String, CaseIterable {
    case home
    case menu
    case offset
    case mode
    case tag
    case diagnostics
    case about
}

struct ContentView: View {
    @StateObject private var ble = DigiTapeBLEManager()

    var body: some View {
        RXConsoleView(ble: ble)
    }
}

struct RXConsoleView: View {
    @ObservedObject var ble: DigiTapeBLEManager
    @State private var screen: RXScreen = .home
    @State private var menuIndex = 0
    @State private var sourceIsTag = false
    @State private var requestedAutoConnect = false
    @State private var activePanel: HomePanel?

    private let menuItems: [(String, RXScreen)] = [
        ("Offset", .offset),
        ("Mode", .mode),
        ("Tag", .tag),
        ("Settings", .diagnostics),
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
        .sheet(item: $activePanel) { panel in
            switch panel {
            case .diagnostics:
                DiagnosticsView(ble: ble)
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
            onSoftKeyTap: handle,
            onMenuItemTap: openMenuItem
        )
    }

    private var controlRow: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            routeIndicator
            connectButton
            panelButton(.diagnostics)
            menuButton
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var landscapeControls: some View {
        VStack(alignment: .center, spacing: 12) {
            compactRouteIndicator
            compactConnectButton
            compactPanelButton(.diagnostics)
            compactMenuButton
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
            case .diagnostics: return "Set"
            }
        }

        var icon: String {
            switch self {
            case .diagnostics: return "waveform.path.ecg"
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

    private var menuButton: some View {
        Button {
            toggleMenu()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                Text("Menu")
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(minWidth: 82, minHeight: 36)
        }
        .buttonStyle(MonoButtonStyle())
    }

    private var compactMenuButton: some View {
        Button {
            toggleMenu()
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(MonoButtonStyle())
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

    enum Key { case k1, k2, k3, k4 }

    private func handle(_ key: Key) {
        switch (screen, key) {
        case (.home, .k1):
            sourceIsTag.toggle()
        case (.home, .k2):
            screen = .offset
        case (.home, .k3):
            cycleResponse(1)
        case (.home, .k4):
            screen = .menu
            menuIndex = 0
        case (.menu, .k1):
            menuIndex = (menuIndex + menuItems.count - 1) % menuItems.count
        case (.menu, .k2):
            menuIndex = (menuIndex + 1) % menuItems.count
        case (.menu, .k3):
            screen = menuItems[menuIndex].1
        case (.menu, .k4):
            screen = .home
        case (.offset, .k1):
            ble.nudgeOffset(1)
        case (.offset, .k2):
            ble.nudgeOffset(-1)
        case (.offset, .k3):
            ble.sendSettings()
            screen = .home
        case (.mode, .k1):
            cycleResponse(1)
        case (.mode, .k2):
            cycleResponse(-1)
        case (.mode, .k3):
            ble.sendSettings()
            screen = .home
        case (.tag, .k1):
            sourceIsTag = false
            screen = .home
        case (.tag, .k2):
            sourceIsTag = true
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
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(OLEDTheme.pixel.opacity(0.7), lineWidth: 1.5)
        )
        .shadow(color: OLEDTheme.pixel.opacity(0.24), radius: 8, y: 2)
    }

    @ViewBuilder
    private func touchTargets(scale: CGFloat) -> some View {
        if screen == .home {
            tapZone(x: 0, y: 0, width: 48, height: 13, scale: scale) {
                onSoftKeyTap(.k1)
            }
            tapZone(x: 0, y: 50, width: 52, height: 14, scale: scale) {
                onSoftKeyTap(.k2)
            }
            tapZone(x: 76, y: 50, width: 52, height: 14, scale: scale) {
                onSoftKeyTap(.k3)
            }
        } else {
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
            oledText(sourceLabel, x: 0, y: 0, size: 8)
            if showsSourceCheck {
                OLEDCheckMark()
                    .stroke(OLEDTheme.pixel, lineWidth: 1)
                    .frame(width: 7, height: 6)
                    .offset(x: CGFloat(sourceLabel.count * 5 + 4), y: 1)
            }
            SignalBars(percent: sourceIsTag ? 10 : ble.signalPercent)
                .foregroundStyle(OLEDTheme.pixel)
                .frame(width: 22, height: 8)
                .position(x: 79, y: 5)
            BatteryIcon(percent: 0)
                .foregroundStyle(OLEDTheme.pixel)
                .frame(width: 23, height: 10)
                .position(x: 115, y: 5)

            if sourceIsTag {
                oledText("SEARCHING", x: 12, y: 24, size: 16)
            } else if ble.linkOK {
                distanceOLED
            } else {
                missingDistanceOLED
            }

            oledText("OFF \(signedOffset)", x: 0, y: 55, size: 8)
            oledText(ble.responseMode.label, x: rightX(ble.responseMode.label), y: 55, size: 8)
        }
    }

    private var menuScreen: some View {
        ZStack(alignment: .topLeading) {
            header("SETTINGS")
            ForEach(menuItems.indices, id: \.self) { index in
                oledText("\(index == menuIndex ? ">" : " ")\(menuItems[index])", x: 0, y: 14 + index * 8, size: 8)
            }
            softLabels("UP", "DN", "SEL", "BACK")
        }
    }

    private var offsetScreen: some View {
        ZStack(alignment: .topLeading) {
            header("OFFSET")
            oledText(ble.linkOK ? ble.displayDistance.compactDistance : "--'--\"", x: 0, y: 16, size: 16)
            oledText("Offset: \(signedOffset)", x: 0, y: 43, size: 8)
            softLabels("+1", "-1", "SAVE", "BACK")
        }
    }

    private var modeScreen: some View {
        ZStack(alignment: .topLeading) {
            header("MODE")
            oledText(ble.responseMode.label, x: 0, y: 22, size: 16)
            oledText("AVG \(responseAverage) RATE \(responseRate)ms", x: 0, y: 46, size: 8)
            softLabels("NEXT", "PREV", "SAVE", "BACK")
        }
    }

    private var tagScreen: some View {
        ZStack(alignment: .topLeading) {
            header("TAG")
            oledText("Status: Searching", x: 0, y: 16, size: 8)
            oledText("Battery: --", x: 0, y: 28, size: 8)
            oledText("FW: --", x: 0, y: 40, size: 8)
            oledText("ID: TAG-001", x: 0, y: 52, size: 8)
            oledText("BACK", x: rightX("BACK"), y: 55, size: 8)
        }
    }

    private var diagnosticsScreen: some View {
        ZStack(alignment: .topLeading) {
            header("DIAG")
            oledText("RX 2.0.2", x: 0, y: 13, size: 8)
            oledText(ble.sensorType.label, x: rightX(ble.sensorType.label), y: 13, size: 8)
            oledText("LINK \(ble.linkOK ? "OK" : "--")", x: 0, y: 25, size: 8)
            oledText("SIG \(ble.signalPercent)%", x: 64, y: 25, size: 8)
            oledText("RSSI \(ble.rssi)", x: 0, y: 37, size: 8)
            oledText("PKT \(shortPacketCounter)", x: 64, y: 37, size: 8)
            oledText("RESP \(ble.responseMode.shortLabel)", x: 0, y: 49, size: 8)
            oledText("BACK", x: rightX("BACK"), y: 55, size: 8)
        }
    }

    private var aboutScreen: some View {
        ZStack(alignment: .topLeading) {
            header("ABOUT")
            oledText("DigiTape RX", x: 0, y: 16, size: 8)
            oledText("APP 2.0.2", x: 0, y: 28, size: 8)
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
                .frame(width: 128, height: 1)
                .offset(x: 0, y: 10)
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

    private func oledText(_ text: String, x: Int, y: Int, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .foregroundStyle(OLEDTheme.pixel)
            .lineLimit(1)
            .fixedSize()
            .offset(x: CGFloat(x), y: CGFloat(y))
    }

    private var sourceLabel: String {
        if sourceIsTag { return "TAG-01" }
        if ble.emulatorMode { return "EMU" }
        if !ble.linkOK { return "TX" }
        return ble.sensorType.label
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
        }
    }

    private var responseRate: Int {
        switch ble.responseMode {
        case .fast: return 50
        case .normal: return 100
        case .avg: return 150
        }
    }


    private var shortPacketCounter: String {
        if ble.packetCounter < 10000 { return "\(ble.packetCounter)" }
        return "\(ble.packetCounter % 10000)"
    }

    private func rightX(_ text: String) -> Int {
        max(0, 127 - text.count * 5)
    }
}

private enum OLEDTheme {
    static let pixel = Color(red: 0.33, green: 1.0, blue: 0.18)
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

struct DiagnosticsView: View {
    @ObservedObject var ble: DigiTapeBLEManager
    @State private var showingFirmwareImporter = false
    @State private var firmwareTarget = "RX"

    private var selectedFirmware: FirmwareManifest.FirmwareFile? {
        ble.availableFirmware.first { $0.target.caseInsensitiveCompare(firmwareTarget) == .orderedSame }
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

                    diagRow("Status", firmwareStatusText)
                    diagRow("Installed", ble.installedFirmwareVersion(for: firmwareTarget))
                    ProgressView(value: ble.otaProgress)
                        .opacity(ble.otaInProgress ? 1 : 0.35)

                    Button {
                        ble.checkCloudFirmware()
                    } label: {
                        Label(ble.availableFirmware.isEmpty ? "Check for Updates" : "Refresh Updates", systemImage: "arrow.clockwise")
                    }
                    .disabled(ble.isCheckingCloudFirmware || ble.otaInProgress)

                    Button {
                        if isSelectedRouteConnected {
                            ble.downloadAndUpdateFirmware(for: firmwareTarget)
                        } else {
                            ble.switchConnectionRoute(to: firmwareTarget)
                        }
                    } label: {
                        Label(primaryFirmwareButtonTitle, systemImage: primaryFirmwareButtonIcon)
                    }
                    .disabled(primaryFirmwareButtonDisabled)

                    Button {
                        if isSelectedRouteConnected {
                            showingFirmwareImporter = true
                        } else {
                            ble.switchConnectionRoute(to: firmwareTarget)
                        }
                    } label: {
                        Label(isSelectedRouteConnected ? "Choose File Instead" : "Connect to \(firmwareTarget)", systemImage: "folder")
                    }
                    .disabled(ble.otaInProgress || (isSelectedRouteConnected && !ble.otaReady))

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
                    diagRow("Sensor", ble.sensorType.label)
                    diagRow("Packet", "\(ble.packetCounter)")
                }

                Section("Emulator") {
                    Toggle("Emulator Mode", isOn: Binding(
                        get: { ble.emulatorMode },
                        set: { $0 ? ble.startEmulatorMode() : ble.startLiveMode() }
                    ))
                    diagRow("Distance", ble.displayDistance)
                    Slider(value: $ble.emulatorDistanceInches, in: 0...600, step: 1)
                    diagRow("Signal", "\(ble.signalPercent)%")
                    Slider(value: $ble.emulatorSignal, in: 0...100, step: 1)
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $showingFirmwareImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }

                do {
                    let data = try Data(contentsOf: url)
                    ble.startFirmwareUpdate(data: data, filename: url.lastPathComponent)
                } catch {
                    ble.otaStatus = "File error: \(error.localizedDescription)"
                }
            }
        }
    }

    private var firmwareStatusText: String {
        if ble.otaInProgress { return ble.otaStatus }
        if ble.isCheckingCloudFirmware { return "Checking GitHub..." }
        if ble.isDownloadingFirmware { return ble.cloudFirmwareStatus }
        if let selectedFirmware {
            return "\(firmwareTarget) \(selectedFirmware.version) available"
        }
        return ble.cloudFirmwareStatus
    }

    private var primaryFirmwareButtonTitle: String {
        if !isSelectedRouteConnected { return "Connect to \(firmwareTarget)" }
        if let selectedFirmware { return "Update \(firmwareTarget) to \(selectedFirmware.version)" }
        return "Check for Updates First"
    }

    private var primaryFirmwareButtonIcon: String {
        isSelectedRouteConnected ? "icloud.and.arrow.down" : routeIcon(for: firmwareTarget)
    }

    private var primaryFirmwareButtonDisabled: Bool {
        ble.otaInProgress ||
        ble.isDownloadingFirmware ||
        (isSelectedRouteConnected && (!ble.otaReady || selectedFirmware == nil))
    }

    private func routeIcon(for route: String) -> String {
        route == "TX" ? "antenna.radiowaves.left.and.right" : "display"
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
                Rectangle()
                    .strokeBorder(lineWidth: index < filledBars ? 0 : 1)
                    .background(Rectangle().fill(index < filledBars ? OLEDTheme.pixel : Color.clear))
                    .frame(width: 3, height: 8)
            }
        }
        .frame(width: 22, height: 8)
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
        case .normal: return "DEF"
        case .avg: return "AVG"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
