import SwiftUI

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
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            RXConsoleView(ble: ble)
                .tabItem { Label("RX", systemImage: "rectangle.inset.filled") }
                .tag(0)
            RXMenuHostView(ble: ble)
                .tabItem { Label("Menu", systemImage: "list.bullet.rectangle") }
                .tag(1)
            EmulatorView(ble: ble)
                .tabItem { Label("Emulator", systemImage: "iphone") }
                .tag(2)
            DiagnosticsView(ble: ble)
                .tabItem { Label("Diag", systemImage: "waveform.path.ecg") }
                .tag(3)
        }
    }
}

struct RXConsoleView: View {
    @ObservedObject var ble: DigiTapeBLEManager
    @State private var screen: RXScreen = .home
    @State private var menuIndex = 0
    @State private var sourceIsTag = false
    @State private var requestedAutoConnect = false

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
                    HStack(spacing: 18) {
                        lcd
                            .frame(maxWidth: .infinity)
                        ArrowKeyColumn(
                            onUp: { handle(.k1) },
                            onDown: { handle(.k2) },
                            onForward: { handle(.k3) },
                            onBack: { handle(.k4) }
                        )
                        .frame(width: 74)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                } else {
                    VStack(spacing: 14) {
                        lcd
                        ArrowKeyColumn(
                            onUp: { handle(.k1) },
                            onDown: { handle(.k2) },
                            onForward: { handle(.k3) },
                            onBack: { handle(.k4) }
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color(.systemBackground))
        .onAppear { autoConnectIfNeeded() }
        .onChange(of: ble.isBluetoothReady) { _, _ in autoConnectIfNeeded() }
    }

    private var lcd: some View {
        OLEDDisplay(
            ble: ble,
            screen: screen,
            menuIndex: menuIndex,
            menuItems: menuItems.map(\.0),
            sourceIsTag: sourceIsTag
        )
    }

    private func autoConnectIfNeeded() {
        guard !requestedAutoConnect else { return }
        guard !ble.isConnected, !ble.isScanning else { return }
        guard ble.isBluetoothReady else { return }
        requestedAutoConnect = true
        sourceIsTag = false
        ble.startLiveMode()
    }

    private enum Key { case k1, k2, k3, k4 }

    private func handle(_ key: Key) {
        switch (screen, key) {
        case (.home, .k1):
            sourceIsTag.toggle()
        case (.home, .k2):
            sourceIsTag = false
            if ble.isConnected && !ble.emulatorMode {
                ble.disconnect()
            } else {
                ble.startLiveMode()
            }
        case (.home, .k3):
            screen = .menu
            menuIndex = 0
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
                    Button(ble.isScanning ? "Scanning..." : "Connect to DigiTape-TX") {
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

    var body: some View {
        ZStack {
            Color.black
            GeometryReader { geo in
                let scale = geo.size.width / 128
                ZStack(alignment: .topLeading) {
                    oledScreen(scale)
                }
                .frame(width: 128, height: 64, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
            }
        }
        .aspectRatio(128.0 / 64.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.gray.opacity(0.7), lineWidth: 2)
        )
        .shadow(radius: 8, y: 2)
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
            SignalBars(percent: sourceIsTag ? 10 : ble.signalPercent)
                .foregroundStyle(.white)
                .frame(width: 22, height: 8)
                .position(x: 79, y: 5)
            BatteryIcon(percent: ble.batteryPercent)
                .foregroundStyle(.white)
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
            oledText(ble.sensorType.label, x: 66, y: 13, size: 8)
            oledText("LINK   \(ble.linkOK ? "OK" : "--")", x: 0, y: 25, size: 8)
            oledText("SIGNAL", x: 0, y: 37, size: 8)
            SignalBars(percent: ble.signalPercent)
                .foregroundStyle(.white)
                .frame(width: 22, height: 8)
                .position(x: 54, y: 41)
            oledText("\(ble.signalPercent)%", x: 82, y: 37, size: 8)
            oledText("RESP   \(ble.responseMode.label)", x: 0, y: 49, size: 8)
            oledText("PKT \(ble.packetCounter)", x: 0, y: 58, size: 8)
            oledText("BACK", x: rightX("BACK"), y: 55, size: 8)
        }
    }

    private var aboutScreen: some View {
        ZStack(alignment: .topLeading) {
            header("ABOUT")
            oledText("DigiTape RX", x: 0, y: 16, size: 8)
            oledText("APP 2.0.2", x: 0, y: 28, size: 8)
            oledText("Display 128x64", x: 0, y: 40, size: 8)
            oledText("BATTERY: \(ble.batteryPercent)%", x: 0, y: 54, size: 8)
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
                .fill(.white)
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
            .font(.system(size: size, weight: .regular, design: .monospaced))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .offset(x: CGFloat(x), y: CGFloat(y))
    }

    private var sourceLabel: String {
        if sourceIsTag { return "TAG-01" }
        if ble.emulatorMode { return "EMU" }
        return ble.sensorType.label
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

    private func rightX(_ text: String) -> Int {
        max(0, 127 - text.count * 5)
    }
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
        .buttonStyle(.borderedProminent)
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

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("Mode", value: ble.emulatorMode ? "Emulator" : "BLE Live")
                LabeledContent("Link", value: ble.linkOK ? "OK" : "--")
                LabeledContent("Sensor", value: ble.sensorType.label)
                LabeledContent("RSSI", value: "\(ble.rssi) dBm")
                LabeledContent("Signal", value: "\(ble.signalPercent)%")
                LabeledContent("Packet", value: "\(ble.packetCounter)")
                LabeledContent("TX FW", value: ble.txVersion)
                LabeledContent("Status", value: ble.status)
            }
            .navigationTitle("Diagnostics")
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
                    .background(Rectangle().fill(index < filledBars ? Color.white : Color.clear))
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
