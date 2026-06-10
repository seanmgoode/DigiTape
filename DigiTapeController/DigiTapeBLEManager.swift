import Foundation
@preconcurrency import CoreBluetooth
import SwiftUI

private enum DigiTapeBLEUUID {
    static let service = CBUUID(string: "6f8a1500-b5a3-4f4a-9d7f-1a2b3c4d5e6f")
    static let distance = CBUUID(string: "6f8a1501-b5a3-4f4a-9d7f-1a2b3c4d5e6f")
    static let settings = CBUUID(string: "6f8a1502-b5a3-4f4a-9d7f-1a2b3c4d5e6f")
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
        case .rx: return ["DigiTape-RX", "DigiTape RX", "DigiTapeRX"]
        case .tx: return ["DigiTape-TX", "DigiTape TX", "DigiTapeTX"]
        }
    }
}

@MainActor
final class DigiTapeBLEManager: NSObject, ObservableObject {
    @Published var isBluetoothReady = false
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var status = "Idle"
    @Published var connectionRoute = "--"
    @Published var distanceCM: UInt16 = 0
    @Published var errorFlag: UInt8 = 1
    @Published var packetCounter: UInt16 = 0
    @Published var responseMode: ResponseMode = .normal
    @Published var sensorType: SensorType = .sr04
    @Published var txVersion = "--"
    @Published var rssi: Int = -100
    @Published var offsetInches: Int16 = 0
    @Published var emulatorMode = true
    @Published private var packetFreshnessTick = 0
    @Published var emulatorBattery = 82.0
    @Published var emulatorSignal = 92.0
    @Published var emulatorDistanceInches = 152.0
    @Published var otaReady = false
    @Published var otaInProgress = false
    @Published var otaProgress = 0.0
    @Published var otaStatus = "OTA idle"
    @Published var firmwareManifestURL = "https://github.com/seanmgoode/DigiTape/releases/latest/download/firmware-manifest.json"
    @Published var cloudFirmwareStatus = "Cloud idle"
    @Published var availableFirmware: [FirmwareManifest.FirmwareFile] = []
    @Published var isCheckingCloudFirmware = false
    @Published var isDownloadingFirmware = false

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var distanceCharacteristic: CBCharacteristic?
    private var settingsCharacteristic: CBCharacteristic?
    private var otaControlCharacteristic: CBCharacteristic?
    private var otaDataCharacteristic: CBCharacteristic?
    private var otaStatusCharacteristic: CBCharacteristic?
    private var rssiTimer: Timer?
    private var packetFreshnessTimer: Timer?
    private var lastPacketDate: Date?
    private var pendingResponseMode: ResponseMode?
    private var pendingResponseDeadline: Date?
    private var scanFallbackTimer: Timer?
    private var connectFallbackTimer: Timer?
    private var rxPreferenceTimer: Timer?
    private var scanTarget: DigiTapeBLETarget = .rx
    private var connectingTarget: DigiTapeBLETarget?
    private var connectedTarget: DigiTapeBLETarget?
    private var wantsLiveConnection = false
    private var otaPayload = Data()
    private var otaOffset = 0
    private var otaWaitingForBeginAck = false
    private var otaWaitingForEndAck = false
    private let otaChunkSize = 180
    private let rxReleaseTXCommand: UInt8 = 1
    private var manualTXRouteUntil: Date?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var displayDistance: String {
        let total = max(0, currentDistanceInches + Double(offsetInches))
        let rounded = Int(total.rounded())
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

    var linkOK: Bool {
        _ = packetFreshnessTick
        if emulatorMode { return true }
        guard isConnected, errorFlag == 0, let lastPacketDate else { return false }
        return Date().timeIntervalSince(lastPacketDate) <= 1.5
    }

    func startLiveMode() {
        wantsLiveConnection = true
        emulatorMode = false
        guard isBluetoothReady else {
            status = "Bluetooth not ready"
            return
        }
        scan()
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

    func stopScan() {
        scanFallbackTimer?.invalidate()
        scanFallbackTimer = nil
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
        clearOTAState(resetStatus: true)
        lastPacketDate = nil
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

    guard otaReady, !otaInProgress else {
        cloudFirmwareStatus = "OTA unavailable"
        return
    }

    isDownloadingFirmware = true
    cloudFirmwareStatus = "Downloading \(firmware.target) \(firmware.version)..."

    Task {
        do {
            let (data, response) = try await URLSession.shared.data(from: firmware.url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            await MainActor.run {
                self.isDownloadingFirmware = false
                self.cloudFirmwareStatus = "Downloaded \(firmware.target) \(firmware.version)"
                self.startFirmwareUpdate(data: data, filename: firmware.url.lastPathComponent)
            }
        } catch {
            await MainActor.run {
                self.isDownloadingFirmware = false
                self.cloudFirmwareStatus = "Download failed"
            }
        }
    }
}

    func startFirmwareUpdate(data: Data, filename: String) {
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
        otaStatus = "Starting \(filename)"

        var command = Data([1])
        let size = UInt32(data.count)
        command.append(UInt8(size & 0xFF))
        command.append(UInt8((size >> 8) & 0xFF))
        command.append(UInt8((size >> 16) & 0xFF))
        command.append(UInt8((size >> 24) & 0xFF))
        peripheral.writeValue(command, for: otaControlCharacteristic, type: .withResponse)
    }

    func abortFirmwareUpdate() {
        if let peripheral, let otaControlCharacteristic {
            peripheral.writeValue(Data([3]), for: otaControlCharacteristic, type: .withResponse)
        }
        clearOTAState(resetStatus: false)
        otaStatus = "OTA aborted"
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

    scanTarget = target
    manualTXRouteUntil = target == .tx ? Date().addingTimeInterval(120) : nil
    scanFallbackTimer?.invalidate()
    scanFallbackTimer = nil
    connectFallbackTimer?.invalidate()
    connectFallbackTimer = nil
    rxPreferenceTimer?.invalidate()
    rxPreferenceTimer = nil

    if target == .tx, connectedTarget == .rx, let peripheral {
        sendSettings(reservedCommand: rxReleaseTXCommand)
        status = "Releasing TX from RX..."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak peripheral] in
            guard let self, let peripheral, self.peripheral === peripheral, self.scanTarget == .tx else { return }
            self.connectionRoute = "--"
            self.distanceCharacteristic = nil
            self.settingsCharacteristic = nil
            self.stopPacketFreshnessTimer()
            self.lastPacketDate = nil
            self.central.cancelPeripheralConnection(peripheral)
        }
        return
    }

    connectionRoute = "--"
    distanceCharacteristic = nil
    settingsCharacteristic = nil
    stopPacketFreshnessTimer()
    lastPacketDate = nil

    if let peripheral {
        central.cancelPeripheralConnection(peripheral)
    } else {
        startScan(for: target, allowFallback: target == .rx)
    }
}

    func sendSettings(reservedCommand: UInt8 = 0) {
        let settings = SettingsPacket(offsetInches: offsetInches, responseMode: responseMode, reserved: reservedCommand)
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

    func nudgeOffset(_ delta: Int16) {
        offsetInches += delta
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
}

extension DigiTapeBLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            isBluetoothReady = central.state == .poweredOn
            status = isBluetoothReady ? "Bluetooth ready" : "Bluetooth unavailable"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let deviceName = advertisedName ?? peripheral.name ?? ""

        Task { @MainActor in
            guard self.scanTarget.matches(deviceName) else { return }

            self.rssi = RSSI.intValue
            self.status = "Found \(self.scanTarget.displayName)"
            self.peripheral = peripheral
            self.peripheral?.delegate = self
            self.connectingTarget = self.scanTarget
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
            self.connectionRoute = self.connectedTarget?.routeLabel ?? "--"
            self.isConnected = true
            self.status = "Connected to \(self.connectedTarget?.displayName ?? "DigiTape")"
            self.scheduleRXPreferenceCheckIfNeeded()
            peripheral.discoverServices([DigiTapeBLEUUID.service])
            self.startPacketFreshnessTimer()
            self.rssiTimer?.invalidate()
            self.rssiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak peripheral] _ in
                peripheral?.readRSSI()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.connectFallbackTimer?.invalidate()
            self.connectFallbackTimer = nil
            self.status = "Could not connect to \(self.connectingTarget?.displayName ?? "DigiTape")"
            if self.connectingTarget == .rx {
                self.startScan(for: .tx, allowFallback: false)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            self.status = "Disconnected"
            self.rssiTimer?.invalidate()
            self.rssiTimer = nil
            self.connectFallbackTimer?.invalidate()
            self.connectFallbackTimer = nil
            self.rxPreferenceTimer?.invalidate()
            self.rxPreferenceTimer = nil
            self.connectingTarget = nil
            self.connectedTarget = nil
            self.connectionRoute = "--"
            self.peripheral = nil
            self.distanceCharacteristic = nil
            self.settingsCharacteristic = nil
            self.clearOTAState(resetStatus: true)
            self.stopPacketFreshnessTimer()
            self.lastPacketDate = nil

            if self.wantsLiveConnection && !self.emulatorMode {
                self.startScan(for: self.scanTarget, allowFallback: self.scanTarget == .rx)
            }
        }
    }
}

extension DigiTapeBLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([
                DigiTapeBLEUUID.distance,
                DigiTapeBLEUUID.settings,
                DigiTapeBLEUUID.otaControl,
                DigiTapeBLEUUID.otaData,
                DigiTapeBLEUUID.otaStatus
            ], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard let characteristics = service.characteristics else { return }
            for characteristic in characteristics {
                if characteristic.uuid == DigiTapeBLEUUID.distance {
                    self.distanceCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                } else if characteristic.uuid == DigiTapeBLEUUID.settings {
                    self.settingsCharacteristic = characteristic
                    self.sendSettings()
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
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == DigiTapeBLEUUID.otaStatus, let data = characteristic.value {
            let message = String(data: data, encoding: .utf8) ?? "OTA status"
            Task { @MainActor in self.otaStatus = message }
            return
        }

        guard characteristic.uuid == DigiTapeBLEUUID.distance, let data = characteristic.value, let packet = DistancePacket(data: data) else { return }
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
            self.txVersion = packet.txVersion
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
}

private extension DigiTapeBLETarget {
    var routeLabel: String {
        switch self {
        case .rx: return "RX"
        case .tx: return "TX"
        }
    }

    func matches(_ name: String) -> Bool {
        acceptedNames.contains { name.localizedCaseInsensitiveContains($0) }
    }
}

private extension DigiTapeBLEManager {
    func startScan(for target: DigiTapeBLETarget, allowFallback: Bool) {
        guard isBluetoothReady else { return }

        scanFallbackTimer?.invalidate()
        scanFallbackTimer = nil
        scanTarget = target
        status = "Scanning for \(target.displayName)..."
        isScanning = true
        central.stopScan()
        central.scanForPeripherals(withServices: [DigiTapeBLEUUID.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

        switch target {
        case .rx where allowFallback:
            scanFallbackTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isScanning, !self.isConnected else { return }
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
        connectFallbackTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isConnected, self.connectingTarget == .rx else { return }
                if let peripheral = self.peripheral {
                    self.central.cancelPeripheralConnection(peripheral)
                }
                self.status = "RX unavailable, trying TX..."
                self.startScan(for: .tx, allowFallback: false)
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
                self.startScan(for: .rx, allowFallback: true)
            }
        }
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

    if characteristic.uuid == DigiTapeBLEUUID.otaControl {
        if otaWaitingForBeginAck {
            otaWaitingForBeginAck = false
            sendNextOTAChunk()
        } else if otaWaitingForEndAck {
            otaWaitingForEndAck = false
            otaInProgress = false
            otaProgress = 1
            otaPayload = Data()
            otaStatus = "OTA sent, rebooting"
        }
        return
    }

    if characteristic.uuid == DigiTapeBLEUUID.otaData {
        otaProgress = otaPayload.isEmpty ? 0 : Double(otaOffset) / Double(otaPayload.count)
        sendNextOTAChunk()
    }
}

func sendNextOTAChunk() {
    guard otaInProgress, let peripheral, let otaDataCharacteristic, let otaControlCharacteristic else { return }

    if otaOffset >= otaPayload.count {
        otaWaitingForEndAck = true
        otaStatus = "Finishing OTA"
        peripheral.writeValue(Data([2]), for: otaControlCharacteristic, type: .withResponse)
        return
    }

    let end = min(otaOffset + otaChunkSize, otaPayload.count)
    let chunk = otaPayload.subdata(in: otaOffset..<end)
    otaOffset = end
    otaStatus = "Sending \(Int(otaProgress * 100))%"
    peripheral.writeValue(chunk, for: otaDataCharacteristic, type: .withResponse)
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
