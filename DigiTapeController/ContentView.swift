import SwiftUI

struct ContentView: View {
    @StateObject private var ble = DigiTapeBLEManager()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(ble: ble)
                .tabItem { Label("RX", systemImage: "dot.radiowaves.left.and.right") }
                .tag(0)
            SettingsView(ble: ble)
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
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

struct HomeView: View {
    @ObservedObject var ble: DigiTapeBLEManager

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(ble.emulatorMode ? "EMU" : ble.sensorType.label)
                    .font(.headline.monospaced())
                Spacer()
                SignalBars(percent: ble.signalPercent)
                BatteryIcon(percent: ble.batteryPercent)
            }

            Spacer()

            Text(ble.linkOK ? ble.displayDistance : "--' --\"")
                .font(.system(size: 64, weight: .bold, design: .monospaced))
                .minimumScaleFactor(0.5)

            Text(ble.status)
                .font(.headline)
                .foregroundStyle(ble.linkOK ? .green : .red)

            Spacer()

            HStack {
                Text("OFF \(ble.offsetInches >= 0 ? "+" : "")\(ble.offsetInches)\"")
                Spacer()
                Text(ble.responseMode.label)
            }
            .font(.body.monospaced())
        }
        .padding()
    }
}

struct SettingsView: View {
    @ObservedObject var ble: DigiTapeBLEManager

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    Toggle("Emulator Mode", isOn: Binding(
                        get: { ble.emulatorMode },
                        set: { $0 ? ble.startEmulatorMode() : ble.startLiveMode() }
                    ))
                    Button(ble.isScanning ? "Scanning..." : "Connect to DigiTape-TX") { ble.startLiveMode() }
                        .disabled(ble.emulatorMode == false && ble.isScanning)
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
            .navigationTitle("DigiTape")
        }
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
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: 5, height: CGFloat(6 + index * 4))
                    .opacity(percent >= (index + 1) * 20 ? 1.0 : 0.2)
            }
        }
        .frame(width: 42, height: 28)
    }
}

struct BatteryIcon: View {
    let percent: Int
    var body: some View {
        HStack(spacing: 2) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).stroke(lineWidth: 2).frame(width: 34, height: 16)
                RoundedRectangle(cornerRadius: 2).frame(width: max(2, CGFloat(percent) / 100 * 28), height: 10).padding(.leading, 3)
            }
            RoundedRectangle(cornerRadius: 1).frame(width: 3, height: 8)
        }
    }
}

#Preview {
    ContentView()
}
