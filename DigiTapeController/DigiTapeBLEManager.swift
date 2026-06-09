import Foundation
@preconcurrency import CoreBluetooth
import SwiftUI

private enum DigiTapeBLEUUID {
    static let service = CBUUID(string: "6f8a1500-b5a3-4f4a-9d7f-1a2b3c4d5e6f")
    static let distance = CBUUID(string: "6f8a1501-b5a3-4f4a-9d7f-1a2b3c4d5e6f")
    static let settings = CBUUID(string: "6f8a1502-b5a3-4f4a-9d7f-1a2b3c4d5e6f")
}

@MainActor
final class DigiTapeBLEManager: NSObject, ObservableObject {
    @Published var isBluetoothReady = false
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var status = "Idle"
    @Published var distanceCM: UInt16 = 0
    @Published var errorFlag: UInt8 = 1
    @Published var packetCounter: UInt16 = 0
    @Published var responseMode: ResponseMode = .normal
    @Published var sensorType: SensorType = .sr04
    @Published var txVersion = "--"
    @Published var rssi: Int = -100
    @Published var offsetInches: Int16 = 0
    @Published var emulatorMode = true
    @Published var emulatorBattery = 82.0
    @Published var emulatorSignal = 92.0
    @Published var emulatorDistanceInches = 152.0

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var distanceCharacteristic: CBCharacteristic?
    private var settingsCharacteristic: CBCharacteristic?
    private var rssiTimer: Timer?

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

    var linkOK: Bool { emulatorMode || (isConnected && errorFlag == 0) }

    func startLiveMode() {
        emulatorMode = false
        guard isBluetoothReady else {
            status = "Bluetooth not ready"
            return
        }
        scan()
    }

    func startEmulatorMode() {
        emulatorMode = true
        stopScan()
        disconnect()
        status = "Emulator mode"
    }

    func scan() {
        guard isBluetoothReady else { return }
        status = "Scanning for DigiTape-TX..."
        isScanning = true
        central.scanForPeripherals(withServices: [DigiTapeBLEUUID.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func disconnect() {
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        rssiTimer?.invalidate()
        rssiTimer = nil
        isConnected = false
        peripheral = nil
        distanceCharacteristic = nil
        settingsCharacteristic = nil
    }

    func sendSettings() {
        let settings = SettingsPacket(offsetInches: offsetInches, responseMode: responseMode)
        guard !emulatorMode, let peripheral, let settingsCharacteristic else { return }
        peripheral.writeValue(settings.data, for: settingsCharacteristic, type: .withoutResponse)
        status = "Settings sent"
    }

    func nudgeOffset(_ delta: Int16) {
        offsetInches += delta
        sendSettings()
    }

    func setResponse(_ mode: ResponseMode) {
        responseMode = mode
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
        Task { @MainActor in
            self.rssi = RSSI.intValue
            self.status = "Found DigiTape-TX"
            self.peripheral = peripheral
            self.peripheral?.delegate = self
            self.stopScan()
            central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.isConnected = true
            self.status = "Connected"
            peripheral.discoverServices([DigiTapeBLEUUID.service])
            self.rssiTimer?.invalidate()
            self.rssiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak peripheral] _ in
                peripheral?.readRSSI()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            self.status = "Disconnected"
            self.rssiTimer?.invalidate()
            self.rssiTimer = nil
        }
    }
}

extension DigiTapeBLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([DigiTapeBLEUUID.distance, DigiTapeBLEUUID.settings], for: service)
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
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == DigiTapeBLEUUID.distance, let data = characteristic.value, let packet = DistancePacket(data: data) else { return }
        Task { @MainActor in
            self.distanceCM = packet.distanceCM
            self.errorFlag = packet.errorFlag
            self.packetCounter = packet.packetCounter
            self.responseMode = packet.responseMode
            self.sensorType = packet.sensorType
            self.txVersion = packet.txVersion
            self.status = packet.isValid ? "Live" : "Sensor error"
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        Task { @MainActor in self.rssi = RSSI.intValue }
    }
}
