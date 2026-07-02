import Foundation
@preconcurrency import CoreBluetooth
import CryptoKit
import SwiftUI

private enum DigiTapeBLEUUID {
    static let service = CBUUID(string: "6f8a1500-b5a3-4f4a-9d7f-1a2b3c4d5e6f")
    static let distance = CBUUID(string: "6f8a1501-b5a3-4f4a-9d7f-1a2b3c4d5e6f")
    static let settings = CBUUID(string: "6f8a1502-b5a3-4f4a-9d7f-1a2b3c4d5e6f")
    static let status = CBUUID(string: "6f8a1503-b5a3-4f4a-9d7f-1a2b3c4d5e6f")
    static let otaControl = CBUUID(string: "6f8a15f1-b5a3-4f4a-9d7f-1a2b3c4d5e6f")
    static let otaData = CBUUID(string: "6f8a15f2-b5a3-4f4a-9d7f-1a2b3c4d5e6f")
    static let otaStatus = CBUUID(string: "6f8a15f3-b5a3-4f4a-9d7f-1a2b3c4d5e6f")
}

private enum DigiTapeBLETarget {
    case rx
    case tx

    var displayName: String {
        switch self {
        case .rx: return "DigiTape-RX"
        case .tx: return "DigiTape-TX"
        }
    }

    var acceptedNames: [String] {
        switch self {
        case .rx:
            return [
                "DigiTape-RX", "DigiTape RX", "DigiTapeRX", "DigiTape_RX",
                "MiniRX", "Mini RX", "MiniRx 1.8",
                "RX 2.41", "RX 2.41 AMOLED"
            ]
        case .tx:
            return ["DigiTape-TX", "DigiTape TX", "DigiTapeTX", "DigiTape_TX", "DigiTape TX 2", "TX 2", "Proto1", "Proto 1", "DigiTape Proto1", "DigiTape-Proto1"]
        }
    }
}

@MainActor
final class DigiTapeBLEManager: NSObject, ObservableObject {
    @Published var isBluetoothReady = false
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var status = "Idle"
    @Published var scanDebug = "Scan idle"
    @Published var connectionRoute = "--"
    @Published var distanceCM: UInt16 = 0
    @Published var errorFlag: UInt8 = 1
    @Published var packetCounter: UInt16 = 0
    @Published var responseMode: ResponseMode = .normal
    @Published var sensorType: SensorType = .sr04
    @Published var txVersion = "--"
    @Published var txInputMillivolts: UInt16?
    @Published var rxVersion = "--"
    @Published var rxPowerSource = "--"
    @Published var rxBatteryPercent: Int?
    @Published var rxBatteryMillivolts: UInt16?
    @Published var rxBusMillivolts: UInt16?
    @Published var rxSystemMillivolts: UInt16?
    @Published var uwbStatus = "--"
    @Published var rssi: Int = -100
    @Published var offsetInches: Int16 = 0
    @Published var themeColor: ThemeColor = .green
    @Published var distanceFontSize: UInt8 = 96
    @Published var parameterSnapshot = ParameterSnapshot()
    @Published var emulatorMode = true
    @Published private var packetFreshnessTick = 0
    @Published var emulatorBattery = 82.0
    @Published var emulatorSignal = 92.0
    @Published var emulatorDistanceInches = 152.0
    @Published var otaReady = false
    @Published var otaInProgress = false
    @Published var otaProgress = 0.0
    @Published var otaStatus = "OTA idle"
    @Published var firmwareManifestURL = "https://digitape.co/firmware/latest.json"
    @Published var cloudFirmwareStatus = "Cloud idle"
    @Published var availableFirmware: [FirmwareManifest.FirmwareFile] = []
    @Published var isCheckingCloudFirmware = false
    @Published var isDownloadingFirmware = false

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var distanceCharacteristic: CBCharacteristic?
    private var settingsCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var otaControlCharacteristic: CBCharacteristic?
    private var otaDataCharacteristic: CBCharacteristic?
    private var otaStatusCharacteristic: CBCharacteristic?
    private var rssiTimer: Timer?
    private var distanceReadTimer: Timer?
    private var packetFreshnessTimer: Timer?
    private var lastPacketDate: Date?
    private var pendingResponseMode: ResponseMode?
    private var pendingResponseDeadline: Date?
    private var parameterRevision: UInt16 = 1
    private var scanFallbackTimer: Timer?
    private var connectFallbackTimer: Timer?
    private var broadScanTimer: Timer?
    private var rxPreferenceTimer: Timer?
    private var scanTarget: DigiTapeBLETarget = .rx
    private var connectingTarget: DigiTapeBLETarget?
    private var connectedTarget: DigiTapeBLETarget?
    nonisolated(unsafe) private var triedFullServiceDiscovery = false
    private var wantsLiveConnection = false
    private var otaPayload = Data()
    private var otaOffset = 0
    private var otaWaitingForBeginAck = false
    private var otaWaitingForEndAck = false
    private var otaStartedAt: Date?
    private let otaChunkSize = 180
    private var manualTXRouteUntil: Date?
    private var reconnectRXAfterTXFirmwareUpdate = false
    private let rxReleaseTXCommand: UInt8 = 1
    private var hasCheckedCloudFirmware = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var displayDistance: String {
        let total = max(0, currentDistanceInches + Double(offsetInches))
        let rounded = Int(total.rounded())
        return "\(rounded / 12)' \(rounded % 12)\""
    }

    var liveDistance: String {
        let rounded = max(0, Int(currentDistanceInches.rounded()))
        return "\(rounded / 12)' \(rounded % 12)\""
    }

    var currentDistanceInches: Double {
        emulatorMode ? emulatorDistanceInches : Double(distanceCM).cmToInches
    }

    var signalPercent: Int {
        if emulatorMode { return Int(emulatorSignal.rounded()) }
        if !isConnected { return 0 }
        if rssi >= -40 { return 100 }
        if rssi <= -100 { return 0 }
        return Int(((Double(rssi) + 100.0) / 60.0 * 100.0).rounded())
    }

    var batteryPercent: Int { Int(emulatorBattery.rounded()) }

    var txInputVoltageText: String {
        if emulatorMode {
            return String(format: "%.1fV", emulatorInputVoltage)
        }
        guard let txInputMillivolts else { return "USB" }
        return String(format: "%.1fV", Double(txInputMillivolts) / 1000.0)
    }

    private var emulatorInputVoltage: Double {
        3.3 + (emulatorBattery / 100.0) * 0.9
    }

    func installedFirmwareVersion(for route: String) -> String {
        route.uppercased() == "RX" ? rxVersion : txVersion
    }

    var linkOK: Bool {
        _ = packetFreshnessTick
        if emulatorMode { return true }
        guard isConnected, let lastPacketDate else { return false }
        let maxPacketAge = sensorType == .tag ? 3.5 : 3.0
        return Date().timeIntervalSince(lastPacketDate) <= maxPacketAge
    }

    var sensorOK: Bool {
        linkOK && errorFlag == 0
    }

    var packetAgeText: String {
        _ = packetFreshnessTick
        guard let lastPacketDate else { return "--" }
        return String(format: "%.1fs", Date().timeIntervalSince(lastPacketDate))
    }

    var tagLinkText: String {
        guard sensorType == .tag else { return "Off" }
        if linkOK { return "Live" }
        return errorFlag == 0 ? "Searching" : "Error"
    }

    var txRouteLockText: String {
        _ = packetFreshnessTick
        guard connectionRoute == "TX", sensorType == .tag else { return "Normal" }
        guard let manualTXRouteUntil, Date() < manualTXRouteUntil else { return "Normal" }
        return "TX pinned"
    }

    func startLiveMode() {
        wantsLiveConnection = true
        emulatorMode = false
        guard isBluetoothReady else {
            status = "Bluetooth not ready"
            return
        }
        stopScan()
        scan()
    }

    func startDirectTXMode() {
        wantsLiveConnection = true
        emulatorMode = false
        scanTarget = .tx
        connectingTarget = nil
        connectedTarget = nil
        connectionRoute = "--"
        scanDebug = "TX DEBUG: starting direct TX scan"
        manualTXRouteUntil = Date().addingTimeInterval(600)
        reconnectRXAfterTXFirmwareUpdate = false
        guard isBluetoothReady else {
            status = "Bluetooth not ready"
            scanDebug = "TX DEBUG: waiting for Bluetooth, target TX"
            return
        }
        stopScan()
        connectToTarget(.tx, txHoldSeconds: 600)
    }

    func startEmulatorMode() {
        wantsLiveConnection = false
        emulatorMode = true
        stopScan()
        disconnect()
        status = "Emulator mode"
    }

    func scan() {
        startScan(for: .rx, allowFallback: true)
    }

    func refreshConnection() {
        wantsLiveConnection = true
        emulatorMode = false
        manualTXRouteUntil = nil
        reconnectRXAfterTXFirmwareUpdate = false
        scanTarget = .rx
        status = "Refreshing RX connection..."
        scanFallbackTimer?.invalidate()
        scanFallbackTimer = nil
        connectFallbackTimer?.invalidate()
        connectFallbackTimer = nil
        rxPreferenceTimer?.invalidate()
        rxPreferenceTimer = nil
        connectingTarget = nil
        connectedTarget = nil
        connectionRoute = "--"
        distanceCharacteristic = nil
        settingsCharacteristic = nil
        statusCharacteristic = nil
        clearRXPowerStatus()
        clearOTAState(resetStatus: true)
        stopPacketFreshnessTimer()
        lastPacketDate = nil

        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        } else {
            startScan(for: .rx, allowFallback: true)
        }
    }

    func stopScan() {
        scanFallbackTimer?.invalidate()
        scanFallbackTimer = nil
        broadScanTimer?.invalidate()
        broadScanTimer = nil
        central.stopScan()
        isScanning = false
    }

    func disconnect() {
        wantsLiveConnection = false
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        rssiTimer?.invalidate()
        rssiTimer = nil
        connectFallbackTimer?.invalidate()
        connectFallbackTimer = nil
        rxPreferenceTimer?.invalidate()
        rxPreferenceTimer = nil
        connectingTarget = nil
        connectedTarget = nil
        connectionRoute = "--"
        stopPacketFreshnessTimer()
        isConnected = false
        peripheral = nil
        distanceCharacteristic = nil
        settingsCharacteristic = nil
        statusCharacteristic = nil
        clearRXPowerStatus()
        clearOTAState(resetStatus: true)
        lastPacketDate = nil
    }

    private func clearRXPowerStatus() {
        rxPowerSource = "--"
        rxBatteryPercent = nil
        rxBatteryMillivolts = nil
        rxBusMillivolts = nil
        rxSystemMillivolts = nil
    }

    func requestStatusUpdate() {
        guard isConnected,
              !emulatorMode,
              let peripheral,
              let statusCharacteristic,
              statusCharacteristic.properties.contains(.read) else { return }
        peripheral.readValue(for: statusCharacteristic)
    }

    func checkCloudFirmwareIfNeeded() {
        guard !hasCheckedCloudFirmware, !isCheckingCloudFirmware else { return }
        hasCheckedCloudFirmware = true
        checkCloudFirmware()
    }

    func checkCloudFirmware() {
        guard let url = URL(string: firmwareManifestURL), url.scheme == "https" else {
            cloudFirmwareStatus = "Set HTTPS manifest URL"
            return
        }

        isCheckingCloudFirmware = true
        cloudFirmwareStatus = "Checking cloud..."

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                let manifest = try JSONDecoder().decode(FirmwareManifest.self, from: data)
                await MainActor.run {
                    self.availableFirmware = manifest.files
                    self.cloudFirmwareStatus = manifest.files.isEmpty ? "No firmware listed" : "Cloud firmware ready"
                    self.isCheckingCloudFirmware = false
                }
            } catch {
                await MainActor.run {
                    self.cloudFirmwareStatus = "Cloud check failed"
                    self.isCheckingCloudFirmware = false
                }
            }
        }
    }

func downloadAndUpdateFirmware(for route: String? = nil) {
    let selectedRoute = route ?? connectionRoute
    guard selectedRoute != "--" else {
        cloudFirmwareStatus = "Connect to RX or TX"
        return
    }

    guard let firmware = availableFirmware.first(where: { $0.target.caseInsensitiveCompare(selectedRoute) == .orderedSame }) else {
        cloudFirmwareStatus = "No \(selectedRoute) cloud firmware"
        return
    }

    downloadAndUpdateFirmware(firmware)
}

func downloadAndUpdateFirmware(_ firmware: FirmwareManifest.FirmwareFile) {
    guard connectionRoute != "--" else {
        cloudFirmwareStatus = "Connect to RX or TX"
        return
    }

    guard otaReady, !otaInProgress else {
        cloudFirmwareStatus = "OTA unavailable"
        return
    }

    isDownloadingFirmware = true
    cloudFirmwareStatus = "Downloading \(firmware.target) \(firmware.version)..."

    Task {
        do {
            let firmwareURL = self.resolvedFirmwareURL(firmware.url)
            let (data, response) = try await URLSession.shared.data(from: firmwareURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            await MainActor.run {
                self.isDownloadingFirmware = false
                guard let expectedSize = firmware.size else {
                    self.cloudFirmwareStatus = "Firmware size missing"
                    self.otaStatus = "OTA blocked: manifest size missing"
                    return
                }

                guard data.count == expectedSize else {
                    self.isDownloadingFirmware = false
                    self.cloudFirmwareStatus = "Firmware size mismatch"
                    self.otaStatus = "OTA blocked: size mismatch"
                    return
                }

                let actualSHA256 = Self.sha256Hex(data)
                guard let expectedSHA256 = firmware.sha256?.lowercased(), !expectedSHA256.isEmpty else {
                    self.cloudFirmwareStatus = "Firmware hash missing"
                    self.otaStatus = "OTA blocked: manifest hash missing"
                    return
                }

                guard actualSHA256 == expectedSHA256 else {
                    self.isDownloadingFirmware = false
                    self.cloudFirmwareStatus = "Firmware hash mismatch"
                    self.otaStatus = "OTA blocked: hash mismatch"
                    return
                }

                self.isDownloadingFirmware = false
                self.cloudFirmwareStatus = "Verified \(firmware.target) \(firmware.version)"
                self.startFirmwareUpdate(data: data, filename: firmwareURL.lastPathComponent, sha256Hex: actualSHA256)
            }
        } catch {
            await MainActor.run {
                self.isDownloadingFirmware = false
                self.cloudFirmwareStatus = "Download failed"
            }
        }
    }
}

    private func resolvedFirmwareURL(_ url: URL) -> URL {
        if url.scheme == "http" || url.scheme == "https" {
            return url
        }
        if let manifestURL = URL(string: firmwareManifestURL), let resolved = URL(string: url.relativeString, relativeTo: manifestURL)?.absoluteURL {
            return resolved
        }
        return url
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func startFirmwareUpdate(data: Data, filename: String, sha256Hex: String? = nil) {
        guard !data.isEmpty else {
            otaStatus = "Empty firmware file"
            return
        }

        guard let peripheral, let otaControlCharacteristic, otaDataCharacteristic != nil else {
            otaStatus = "OTA unavailable"
            return
        }

        otaPayload = data
        otaOffset = 0
        otaProgress = 0
        otaInProgress = true
        otaWaitingForBeginAck = true
        otaWaitingForEndAck = false
        otaStartedAt = Date()
        otaStatus = "Starting \(filename)"

        var command = Data([1])
        let size = UInt32(data.count)
        command.append(UInt8(size & 0xFF))
        command.append(UInt8((size >> 8) & 0xFF))
        command.append(UInt8((size >> 16) & 0xFF))
        command.append(UInt8((size >> 24) & 0xFF))
        if let sha256Hex, let hashData = Self.dataFromHex(sha256Hex), hashData.count == 32 {
            command.append(hashData)
        }
        peripheral.writeValue(command, for: otaControlCharacteristic, type: .withResponse)
    }

    static func dataFromHex(_ hex: String) -> Data? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count % 2 == 0 else { return nil }
        var data = Data()
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    func abortFirmwareUpdate() {
        if let peripheral, let otaControlCharacteristic {
            peripheral.writeValue(Data([3]), for: otaControlCharacteristic, type: .withResponse)
        }
        clearOTAState(resetStatus: false)
        otaStatus = "OTA aborted"
    }

func switchConnectionRoute(to route: String) {
    let normalized = route.uppercased()
    guard normalized == "RX" || normalized == "TX" else { return }
    if connectionRoute == normalized { return }

    connectToTarget(normalized == "TX" ? .tx : .rx, txHoldSeconds: normalized == "TX" ? 120 : nil)
}

func switchConnectionRouteForFirmwareUpdate(to route: String) {
    let normalized = route.uppercased()
    guard normalized == "RX" || normalized == "TX" else { return }
    if connectionRoute == normalized { return }

    wantsLiveConnection = true
    emulatorMode = false

    if normalized == "TX", connectedTarget == .rx {
        reconnectRXAfterTXFirmwareUpdate = true
        connectToTarget(.tx, txHoldSeconds: 180)
        return
    }

    switchConnectionRoute(to: normalized)
}

func switchConnectionRoute() {
    wantsLiveConnection = true
    emulatorMode = false

    guard isBluetoothReady else {
        status = "Bluetooth not ready"
        return
    }

    let target: DigiTapeBLETarget
    if connectedTarget == .rx || (!isConnected && scanTarget == .rx) {
        target = .tx
    } else {
        target = .rx
    }

    connectToTarget(target, txHoldSeconds: target == .tx ? 120 : nil)
}

    func sendSettings(reservedCommand: UInt8 = 0) {
        var snapshot = parameterSnapshot
        snapshot.revision = parameterRevision
        let settings = SettingsPacket(
            offsetInches: offsetInches,
            responseMode: responseMode,
            themeColor: themeColor.rawValue,
            reserved: reservedCommand,
            distanceFontSize: distanceFontSize,
            parameterSnapshot: snapshot
        )
        guard !emulatorMode, let peripheral, let settingsCharacteristic else { return }

        let writeType: CBCharacteristicWriteType
        if settingsCharacteristic.properties.contains(.write) {
            writeType = .withResponse
        } else if settingsCharacteristic.properties.contains(.writeWithoutResponse) {
            writeType = .withoutResponse
        } else {
            status = "Settings write unavailable"
            return
        }

        peripheral.writeValue(settings.data, for: settingsCharacteristic, type: writeType)
        status = writeType == .withResponse ? "Sending settings..." : "Settings sent"
    }

    func setParameterSnapshot(_ snapshot: ParameterSnapshot) {
        parameterRevision &+= 1
        var nextSnapshot = snapshot
        nextSnapshot.revision = parameterRevision
        parameterSnapshot = nextSnapshot
        sendSettings()
    }

    func nudgeOffset(_ delta: Int16) {
        offsetInches += delta
        sendSettings()
    }

    func setThemeColor(_ color: ThemeColor) {
        themeColor = color
        sendSettings()
    }

    func setResponse(_ mode: ResponseMode) {
        responseMode = mode
        if !emulatorMode {
            pendingResponseMode = mode
            pendingResponseDeadline = Date().addingTimeInterval(1.5)
        }
        sendSettings()
    }

    func selectTXTagSource() {
        wantsLiveConnection = true
        emulatorMode = false
        manualTXRouteUntil = Date().addingTimeInterval(600)
        if connectionRoute != "TX" {
            switchConnectionRoute(to: "TX")
            return
        }
        sendSettings(reservedCommand: 2)
        status = "Selecting TAG..."
    }

    func selectTXSensorSource() {
        wantsLiveConnection = true
        emulatorMode = false
        manualTXRouteUntil = Date().addingTimeInterval(600)
        if connectionRoute != "TX" {
            switchConnectionRoute(to: "TX")
            return
        }
        sendSettings(reservedCommand: 3)
        status = "Selecting TX sensor..."
    }

}

extension DigiTapeBLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            isBluetoothReady = central.state == .poweredOn
            status = isBluetoothReady ? "Bluetooth ready" : "Bluetooth unavailable"
            if isBluetoothReady && wantsLiveConnection && !emulatorMode && !isConnected && !isScanning {
                startScan(for: scanTarget, allowFallback: shouldFallbackFromRXToTX)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let deviceName = advertisedName ?? peripheral.name ?? ""
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let hasDigiTapeService = advertisedServices.contains(DigiTapeBLEUUID.service)

    Task { @MainActor in
        let serviceLabel = advertisedServices.map { $0.uuidString }.joined(separator: ",")
        self.scanDebug = "Saw \(deviceName.isEmpty ? "unnamed" : deviceName) rssi \(RSSI.intValue) \(hasDigiTapeService ? "svc yes" : "svc no") \(serviceLabel.isEmpty ? "" : serviceLabel)"
        let nameMatchesTarget = self.scanTarget.matches(deviceName)
        let nameMatchesOtherTarget = self.scanTarget.other.matches(deviceName)
        let hasKnownDigiTapeName = DigiTapeBLETarget.isKnownDigiTapeName(deviceName)
        let ambiguousDigiTapeName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "digitape-"
        let shouldAvoidAmbiguousRX = self.scanTarget == .rx && ambiguousDigiTapeName
        let serviceOnlyMatch = hasDigiTapeService &&
            !shouldAvoidAmbiguousRX &&
            !nameMatchesOtherTarget &&
            (deviceName.isEmpty || !hasKnownDigiTapeName || nameMatchesTarget)
        let protoTXMatch = self.scanTarget == .tx && DigiTapeBLETarget.tx.matches(deviceName)
        let shouldConnect = nameMatchesTarget || protoTXMatch || serviceOnlyMatch
        if !shouldConnect {
            self.status = "Ignored \(deviceName.isEmpty ? "unnamed" : deviceName)"
            return
        }

            self.rssi = RSSI.intValue
            self.status = "Found \(self.scanTarget.displayName): \(deviceName.isEmpty ? "service match" : deviceName)"
            self.scanDebug = "Connecting \(deviceName.isEmpty ? self.scanTarget.displayName : deviceName) rssi \(RSSI.intValue)"
            self.peripheral = peripheral
            self.peripheral?.delegate = self
            self.connectingTarget = self.scanTarget
            self.triedFullServiceDiscovery = false
            self.stopScan()
            central.connect(peripheral)
            self.startConnectionFallbackTimer()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.connectFallbackTimer?.invalidate()
            self.connectFallbackTimer = nil
            self.connectedTarget = self.connectingTarget
            self.triedFullServiceDiscovery = false
            self.connectionRoute = self.connectedTarget?.routeLabel ?? "--"
            self.isConnected = false
            self.status = "Connected to \(self.connectedTarget?.displayName ?? "DigiTape")"
            self.scanDebug = "Connected, discovering DigiTape service"
            peripheral.discoverServices([DigiTapeBLEUUID.service])
            self.rssiTimer?.invalidate()
            self.rssiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak peripheral] _ in
                peripheral?.readRSSI()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            let failedTarget = self.connectingTarget ?? self.scanTarget
            self.connectFallbackTimer?.invalidate()
            self.connectFallbackTimer = nil
            self.connectingTarget = nil
            self.peripheral = nil
            self.status = "Could not connect to \(failedTarget.displayName), retrying..."
            if self.wantsLiveConnection && !self.emulatorMode {
                self.startScan(for: failedTarget, allowFallback: self.shouldFallbackFromRXToTX)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            self.status = "Disconnected"
            self.rssiTimer?.invalidate()
            self.rssiTimer = nil
            self.distanceReadTimer?.invalidate()
            self.distanceReadTimer = nil
            self.connectFallbackTimer?.invalidate()
            self.connectFallbackTimer = nil
            self.rxPreferenceTimer?.invalidate()
            self.rxPreferenceTimer = nil
            self.connectingTarget = nil
            self.connectedTarget = nil
            self.triedFullServiceDiscovery = false
            self.connectionRoute = "--"
            self.peripheral = nil
            self.distanceCharacteristic = nil
            self.settingsCharacteristic = nil
            self.statusCharacteristic = nil
            self.clearRXPowerStatus()
            self.clearOTAState(resetStatus: true)
            self.stopPacketFreshnessTimer()
            self.lastPacketDate = nil

            if self.wantsLiveConnection && !self.emulatorMode {
                self.startScan(for: self.scanTarget, allowFallback: self.shouldFallbackFromRXToTX)
            }
        }
    }
}

extension DigiTapeBLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            Task { @MainActor in
                self.status = "Service discovery failed"
                self.scanDebug = error.localizedDescription
                self.isConnected = false
                self.connectedTarget = nil
                self.connectingTarget = nil
                self.connectionRoute = "--"
                self.distanceCharacteristic = nil
                self.settingsCharacteristic = nil
                self.statusCharacteristic = nil
                self.clearRXPowerStatus()
                self.stopPacketFreshnessTimer()
                self.lastPacketDate = nil
                self.central.cancelPeripheralConnection(peripheral)
            }
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            if !triedFullServiceDiscovery {
                Task { @MainActor in
                    self.triedFullServiceDiscovery = true
                    self.scanDebug = "DigiTape service missing; checking all services"
                }
                peripheral.discoverServices(nil)
                return
            }
            Task { @MainActor in
                self.status = "No DigiTape service"
                self.scanDebug = "Connected but no services discovered"
                self.isConnected = false
                self.connectedTarget = nil
                self.connectingTarget = nil
                self.triedFullServiceDiscovery = false
                self.connectionRoute = "--"
                self.distanceCharacteristic = nil
                self.settingsCharacteristic = nil
                self.statusCharacteristic = nil
                self.clearRXPowerStatus()
                self.stopPacketFreshnessTimer()
                self.lastPacketDate = nil
                self.central.cancelPeripheralConnection(peripheral)
            }
            return
        }
        let serviceLabels = services.map { $0.uuid.uuidString }.joined(separator: ",")
        let digitapeServices = services.filter { $0.uuid == DigiTapeBLEUUID.service }
        guard !digitapeServices.isEmpty else {
            if !triedFullServiceDiscovery {
                Task { @MainActor in
                    self.triedFullServiceDiscovery = true
                    self.scanDebug = "DigiTape service missing; checking all services"
                }
                peripheral.discoverServices(nil)
                return
            }
            Task { @MainActor in
                self.status = "No DigiTape service"
                self.scanDebug = "Services: \(serviceLabels.isEmpty ? "none" : serviceLabels)"
                self.isConnected = false
                self.connectedTarget = nil
                self.connectingTarget = nil
                self.triedFullServiceDiscovery = false
                self.connectionRoute = "--"
                self.distanceCharacteristic = nil
                self.settingsCharacteristic = nil
                self.statusCharacteristic = nil
                self.clearRXPowerStatus()
                self.stopPacketFreshnessTimer()
                self.lastPacketDate = nil
                self.central.cancelPeripheralConnection(peripheral)
            }
            return
        }
        Task { @MainActor in self.scanDebug = "Service found, discovering chars" }
        for service in digitapeServices {
            peripheral.discoverCharacteristics([
                DigiTapeBLEUUID.distance,
                DigiTapeBLEUUID.settings,
                DigiTapeBLEUUID.status,
                DigiTapeBLEUUID.otaControl,
                DigiTapeBLEUUID.otaData,
                DigiTapeBLEUUID.otaStatus
            ], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error {
                self.status = "Characteristic discovery failed"
                self.scanDebug = error.localizedDescription
                return
            }
            guard let characteristics = service.characteristics else {
                self.status = "No characteristics"
                self.scanDebug = "DigiTape service had no chars"
                return
            }
            self.scanDebug = "Chars: \(characteristics.count)"
            for characteristic in characteristics {
                if characteristic.uuid == DigiTapeBLEUUID.distance {
                    self.distanceCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    if characteristic.properties.contains(.read) {
                        peripheral.readValue(for: characteristic)
                    }
                    self.startDistanceReadFallback()
                } else if characteristic.uuid == DigiTapeBLEUUID.settings {
                    self.settingsCharacteristic = characteristic
                    if characteristic.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: characteristic)
                    }
                    if characteristic.properties.contains(.read) {
                        peripheral.readValue(for: characteristic)
                    }
                } else if characteristic.uuid == DigiTapeBLEUUID.status {
                    self.statusCharacteristic = characteristic
                    if characteristic.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: characteristic)
                    }
                    peripheral.readValue(for: characteristic)
                } else if characteristic.uuid == DigiTapeBLEUUID.otaControl {
                    self.otaControlCharacteristic = characteristic
                    self.updateOTAReady()
                } else if characteristic.uuid == DigiTapeBLEUUID.otaData {
                    self.otaDataCharacteristic = characteristic
                    self.updateOTAReady()
                } else if characteristic.uuid == DigiTapeBLEUUID.otaStatus {
                    self.otaStatusCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    self.updateOTAReady()
                }
            }
            guard self.distanceCharacteristic != nil else {
                self.status = "No distance stream"
                self.scanDebug = "DigiTape service missing distance char"
                self.connectedTarget = nil
                self.connectingTarget = nil
                self.connectionRoute = "--"
                self.distanceCharacteristic = nil
                self.settingsCharacteristic = nil
                self.statusCharacteristic = nil
                self.clearRXPowerStatus()
                self.stopPacketFreshnessTimer()
                self.lastPacketDate = nil
                self.central.cancelPeripheralConnection(peripheral)
                return
            }
            self.isConnected = true
            self.status = "Connected to \(self.connectedTarget?.displayName ?? "DigiTape")"
            self.startPacketFreshnessTimer()
            self.scheduleRXPreferenceCheckIfNeeded()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == DigiTapeBLEUUID.status, let data = characteristic.value {
            let message = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor in self.parseFirmwareStatus(message) }
            return
        }

        if characteristic.uuid == DigiTapeBLEUUID.otaStatus, let data = characteristic.value {
            let message = String(data: data, encoding: .utf8) ?? "OTA status"
            Task { @MainActor in self.otaStatus = message }
            return
        }

        if characteristic.uuid == DigiTapeBLEUUID.settings, let data = characteristic.value, let settings = SettingsPacket(data: data) {
            Task { @MainActor in
                self.offsetInches = settings.offsetInches
                if let pendingMode = self.pendingResponseMode, pendingMode == settings.responseMode {
                    self.pendingResponseMode = nil
                    self.pendingResponseDeadline = nil
                }
                self.responseMode = settings.responseMode
                self.themeColor = ThemeColor(rawValue: settings.themeColor) ?? .green
                if settings.distanceFontSize > 0 {
                    self.distanceFontSize = settings.distanceFontSize
                }
                if let snapshot = settings.parameterSnapshot {
                    self.parameterSnapshot = snapshot
                    self.parameterRevision = max(self.parameterRevision, snapshot.revision)
                }
            }
            return
        }

        guard characteristic.uuid == DigiTapeBLEUUID.distance, let data = characteristic.value else { return }
        guard let packet = DistancePacket(data: data) else {
            Task { @MainActor in
                self.scanDebug = "Distance parse failed len \(data.count)"
            }
            return
        }
        Task { @MainActor in
            self.distanceCM = packet.distanceCM
            self.errorFlag = packet.errorFlag
            self.packetCounter = packet.packetCounter
            if let pendingMode = self.pendingResponseMode {
                if packet.responseMode == pendingMode {
                    self.pendingResponseMode = nil
                    self.pendingResponseDeadline = nil
                    self.responseMode = packet.responseMode
                } else if let deadline = self.pendingResponseDeadline, Date() < deadline {
                    self.responseMode = pendingMode
                } else {
                    self.pendingResponseMode = nil
                    self.pendingResponseDeadline = nil
                    self.responseMode = packet.responseMode
                }
            } else {
                self.responseMode = packet.responseMode
            }
            self.sensorType = packet.sensorType
            if self.connectedTarget == .tx && packet.sensorType == .tag {
                self.manualTXRouteUntil = Date().addingTimeInterval(600)
                self.rxPreferenceTimer?.invalidate()
                self.rxPreferenceTimer = nil
            }
            self.txVersion = packet.txVersion
            self.txInputMillivolts = packet.inputMillivolts
            self.lastPacketDate = Date()
            self.packetFreshnessTick &+= 1
            self.status = packet.isValid ? "Live" : "Sensor error"
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        Task { @MainActor in self.rssi = RSSI.intValue }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if characteristic.uuid == DigiTapeBLEUUID.otaControl || characteristic.uuid == DigiTapeBLEUUID.otaData {
                self.handleOTAWritableAck(for: characteristic, error: error)
                return
            }

            guard characteristic.uuid == DigiTapeBLEUUID.settings else { return }

            if let error {
                self.status = "Settings failed: \(error.localizedDescription)"
            } else {
                self.status = "Settings accepted"
            }
        }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        Task { @MainActor in
            self.sendOTAChunks()
        }
    }
}

private extension DigiTapeBLETarget {
    var routeLabel: String {
        switch self {
        case .rx: return "RX"
        case .tx: return "TX"
        }
    }

    var other: DigiTapeBLETarget {
        switch self {
        case .rx: return .tx
        case .tx: return .rx
        }
    }

    func matches(_ name: String) -> Bool {
        let normalizedName = Self.normalizedName(name)
        guard !normalizedName.isEmpty else { return false }
        return acceptedNames.contains { normalizedName.contains(Self.normalizedName($0)) }
    }

    static func isKnownDigiTapeName(_ name: String) -> Bool {
        rx.matches(name) || tx.matches(name)
    }

    private static func normalizedName(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }
}

private extension DigiTapeBLEManager {
    var shouldFallbackFromRXToTX: Bool {
        true
    }

    func connectToTarget(_ target: DigiTapeBLETarget, txHoldSeconds: TimeInterval?) {
        wantsLiveConnection = true
        emulatorMode = false
        scanTarget = target
        manualTXRouteUntil = target == .tx ? Date().addingTimeInterval(txHoldSeconds ?? 120) : nil

        guard isBluetoothReady else {
            status = "Bluetooth not ready"
            scanDebug = "Waiting for Bluetooth, target \(target.routeLabel)"
            return
        }

        if connectedTarget == target, isConnected {
            connectionRoute = target.routeLabel
            return
        }

        scanFallbackTimer?.invalidate()
        scanFallbackTimer = nil
        broadScanTimer?.invalidate()
        broadScanTimer = nil
        connectFallbackTimer?.invalidate()
        connectFallbackTimer = nil
        rxPreferenceTimer?.invalidate()
        rxPreferenceTimer = nil

        if target == .tx, connectedTarget == .rx, let peripheral {
            status = "Releasing TX..."
            sendSettings(reservedCommand: rxReleaseTXCommand)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self, weak peripheral] in
                guard let self, let peripheral, self.peripheral === peripheral, self.scanTarget == .tx else { return }
                self.connectionRoute = "--"
                self.distanceCharacteristic = nil
                self.settingsCharacteristic = nil
                self.statusCharacteristic = nil
                self.clearRXPowerStatus()
                self.stopPacketFreshnessTimer()
                self.lastPacketDate = nil
                self.central.cancelPeripheralConnection(peripheral)
            }
            return
        }

        connectionRoute = "--"
        distanceCharacteristic = nil
        settingsCharacteristic = nil
        statusCharacteristic = nil
        clearRXPowerStatus()
        stopPacketFreshnessTimer()
        lastPacketDate = nil

        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        } else {
            startScan(for: target, allowFallback: target == .rx ? shouldFallbackFromRXToTX : false)
        }
    }

    func startScan(for target: DigiTapeBLETarget, allowFallback: Bool) {
        guard isBluetoothReady else { return }

        scanFallbackTimer?.invalidate()
        scanFallbackTimer = nil
        broadScanTimer?.invalidate()
        broadScanTimer = nil
        scanTarget = target
        status = "Scanning for \(target.displayName)..."
        scanDebug = "Scanning \(target.routeLabel) by service UUID"
        isScanning = true
        central.stopScan()
        central.scanForPeripherals(withServices: [DigiTapeBLEUUID.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

        broadScanTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isScanning, !self.isConnected, self.scanTarget == target else { return }
                self.scanDebug = "Scanning \(target.routeLabel) broadly"
                self.central.stopScan()
                self.central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            }
        }

        switch target {
        case .rx where allowFallback:
            scanFallbackTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isScanning, !self.isConnected else { return }
                    self.manualTXRouteUntil = Date().addingTimeInterval(120)
                    self.startScan(for: .tx, allowFallback: false)
                }
            }
        case .tx:
            let timeout: TimeInterval = manualTXRouteUntil == nil ? 8.0 : 45.0
            scanFallbackTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isScanning, !self.isConnected, self.wantsLiveConnection else { return }
                    if let manualTXRouteUntil = self.manualTXRouteUntil, Date() < manualTXRouteUntil {
                        self.startScan(for: .tx, allowFallback: false)
                    } else {
                        self.manualTXRouteUntil = nil
                        self.startScan(for: .rx, allowFallback: true)
                    }
                }
            }
        default:
            break
        }
    }

    func startConnectionFallbackTimer() {
        connectFallbackTimer?.invalidate()
        connectFallbackTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isConnected, self.wantsLiveConnection, !self.emulatorMode else { return }
                let target = self.connectingTarget ?? self.scanTarget
                if let peripheral = self.peripheral {
                    self.central.cancelPeripheralConnection(peripheral)
                }
                self.connectingTarget = nil
                self.peripheral = nil
                self.status = "\(target.displayName) unavailable, retrying..."
                self.startScan(for: target, allowFallback: self.shouldFallbackFromRXToTX)
            }
        }
    }

func startDistanceReadFallback() {
    distanceReadTimer?.invalidate()
    distanceReadTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
        Task { @MainActor in
            guard let self,
                  self.isConnected,
                  !self.emulatorMode,
                  let peripheral = self.peripheral,
                  let characteristic = self.distanceCharacteristic,
                  characteristic.properties.contains(.read) else { return }
            peripheral.readValue(for: characteristic)
        }
    }
}

func scheduleRXPreferenceCheckIfNeeded() {
    rxPreferenceTimer?.invalidate()
    rxPreferenceTimer = nil

    guard connectedTarget == .tx, wantsLiveConnection, !emulatorMode else { return }
    if let manualTXRouteUntil, Date() < manualTXRouteUntil { return }

    rxPreferenceTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
        Task { @MainActor in
            guard let self, self.connectedTarget == .tx, self.wantsLiveConnection, !self.emulatorMode else { return }
            self.status = "Retrying DigiTape-RX..."
            if let peripheral = self.peripheral {
                self.central.cancelPeripheralConnection(peripheral)
            } else {
                self.startScan(for: .rx, allowFallback: false)
            }
        }
    }
}

func parseFirmwareStatus(_ message: String) {
    let parts = message.split(separator: " ")
    guard !parts.isEmpty else { return }

    var keyValueStart = 0
    if parts.count >= 2 {
        let target = parts[0].uppercased()
        let version = String(parts[1])
        if target == "RX" {
            rxVersion = version
            keyValueStart = 2
        } else if target == "TX" {
            txVersion = version
            keyValueStart = 2
        }
    }

    for part in parts.dropFirst(keyValueStart) {
        let fields = part.split(separator: "=", maxSplits: 1)
        guard fields.count == 2 else { continue }
        let key = fields[0].lowercased()
        let value = String(fields[1])
        if key == "uwb" {
            uwbStatus = Self.displayStatus(for: value)
        } else if key == "src" || key == "source" {
            rxPowerSource = Self.displayPowerSource(value)
        } else if key == "batt" || key == "battery" {
            let percent = Int(value)
            rxBatteryPercent = (percent ?? -1) >= 0 ? percent : nil
        } else if key == "vbat" || key == "battmv" {
            rxBatteryMillivolts = Self.millivolts(from: value)
        } else if key == "vbus" || key == "usbmv" {
            rxBusMillivolts = Self.millivolts(from: value)
        } else if key == "vsys" || key == "sysmv" {
            rxSystemMillivolts = Self.millivolts(from: value)
        }
    }
}

private static func millivolts(from value: String) -> UInt16? {
    guard let parsed = UInt16(value), parsed > 0 else { return nil }
    return parsed
}

private static func displayPowerSource(_ value: String) -> String {
    switch value.lowercased() {
    case "usb", "vbus":
        return "USB"
    case "battery", "bat":
        return "BAT"
    default:
        return value.isEmpty ? "--" : value
    }
}

private static func displayStatus(for value: String) -> String {
    switch value.lowercased() {
    case "ready", "ok", "online":
        return "OK"
    case "offline", "failed", "fail":
        return "--"
    case "disabled":
        return "--"
    default:
        return "--"
    }
}

func updateOTAReady() {
    otaReady = otaControlCharacteristic != nil && otaDataCharacteristic != nil
    if otaReady && otaStatus == "OTA idle" {
        otaStatus = "OTA ready"
    }
}

func clearOTAState(resetStatus: Bool) {
    otaControlCharacteristic = nil
    otaDataCharacteristic = nil
    otaStatusCharacteristic = nil
    otaReady = false
    otaInProgress = false
    otaProgress = 0
    otaPayload = Data()
    otaOffset = 0
    otaWaitingForBeginAck = false
    otaWaitingForEndAck = false
    otaStartedAt = nil
    if resetStatus {
        otaStatus = "OTA idle"
    }
}

func handleOTAWritableAck(for characteristic: CBCharacteristic, error: Error?) {
    if let error {
        otaStatus = "OTA failed: \(error.localizedDescription)"
        otaInProgress = false
        return
    }

    guard characteristic.uuid == DigiTapeBLEUUID.otaControl else { return }

    if otaWaitingForBeginAck {
        otaWaitingForBeginAck = false
        sendOTAChunks()
    } else if otaWaitingForEndAck {
        otaWaitingForEndAck = false
        otaInProgress = false
        otaProgress = 1
        otaPayload = Data()
        otaStartedAt = nil
        otaStatus = "OTA sent, rebooting"
        if reconnectRXAfterTXFirmwareUpdate && connectedTarget == .tx {
            scanTarget = .rx
            manualTXRouteUntil = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.reconnectRXAfterTXFirmwareUpdate else { return }
                self.reconnectRXAfterTXFirmwareUpdate = false
                if let peripheral = self.peripheral {
                    self.central.cancelPeripheralConnection(peripheral)
                } else {
                    self.startScan(for: .rx, allowFallback: false)
                }
            }
        }
    }
}

func otaTransferStatusText() -> String {
    guard let otaStartedAt else {
        return "Sending \(Int(otaProgress * 100))%"
    }

    let elapsed = max(0.1, Date().timeIntervalSince(otaStartedAt))
    let kbPerSecond = Double(otaOffset) / 1024.0 / elapsed
    return String(format: "Sending %d%% %.1f KB/s", Int(otaProgress * 100), kbPerSecond)
}

func sendOTAChunks() {
    guard otaInProgress, !otaWaitingForBeginAck, !otaWaitingForEndAck,
          let peripheral, let otaDataCharacteristic, let otaControlCharacteristic else { return }

    while otaOffset < otaPayload.count, peripheral.canSendWriteWithoutResponse {
        let maxWriteLength = peripheral.maximumWriteValueLength(for: .withoutResponse)
        let chunkSize = min(otaChunkSize, max(20, maxWriteLength))
        let end = min(otaOffset + chunkSize, otaPayload.count)
        let chunk = otaPayload.subdata(in: otaOffset..<end)
        otaOffset = end
        otaProgress = Double(otaOffset) / Double(otaPayload.count)
        otaStatus = otaTransferStatusText()
        peripheral.writeValue(chunk, for: otaDataCharacteristic, type: .withoutResponse)
    }

    if otaOffset >= otaPayload.count {
        otaWaitingForEndAck = true
        otaStatus = "Finishing OTA"
        peripheral.writeValue(Data([2]), for: otaControlCharacteristic, type: .withResponse)
    }
}

    func startPacketFreshnessTimer() {
        packetFreshnessTimer?.invalidate()
        packetFreshnessTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.packetFreshnessTick &+= 1
            }
        }
    }

    func stopPacketFreshnessTimer() {
        packetFreshnessTimer?.invalidate()
        packetFreshnessTimer = nil
    }
}
