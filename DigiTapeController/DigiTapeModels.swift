import Foundation

enum SensorType: UInt8, CaseIterable, Identifiable {
    case sr04 = 0
    case lidar = 1
    case luna = 2
    case tag = 3
    case unknown = 255

    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .sr04: return "SR04"
        case .lidar: return "GARMIN"
        case .luna: return "LUNA"
        case .tag: return "TAG"
        case .unknown: return "UNKNOWN"
        }
    }
}

enum ResponseMode: UInt8, CaseIterable, Identifiable {
    case fast = 0
    case normal = 1
    case avg = 2
    case slow = 3

    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .fast: return "FAST"
        case .normal: return "NORMAL"
        case .avg: return "SMOOTH"
        case .slow: return "SLOW"
        }
    }
}

struct DistancePacket {
    var distanceCM: UInt16
    var errorFlag: UInt8
    var packetCounter: UInt16
    var responseMode: ResponseMode
    var sensorType: SensorType
    var txVersion: String
    var inputMillivolts: UInt16?

    var isValid: Bool { errorFlag == 0 }

    // Supports legacy 15/16-byte payloads and newer payloads with TX input voltage appended.
    init?(data: Data) {
        guard data.count == 15 || data.count == 16 || data.count == 17 || data.count == 18 else { return nil }
        func u16(_ offset: Int) -> UInt16 {
            UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        }

        distanceCM = u16(0)
        errorFlag = data[2]

        let aligned = data.count == 16
        let packetOffset = aligned ? 4 : 3
        packetCounter = u16(packetOffset)
        responseMode = ResponseMode(rawValue: data[packetOffset + 2]) ?? .normal
        sensorType = SensorType(rawValue: data[packetOffset + 3]) ?? .unknown

        let versionStart = packetOffset + 4
        let versionBytes = data[versionStart..<min(versionStart + 8, data.count)]
        txVersion = String(bytes: versionBytes.prefix { $0 != 0 }, encoding: .utf8) ?? "--"

        let voltageOffset = versionStart + 8
        if data.count >= voltageOffset + 2 {
            inputMillivolts = u16(voltageOffset)
        } else {
            inputMillivolts = nil
        }
    }
}

struct SettingsPacket {
    var offsetInches: Int16
    var responseMode: ResponseMode
    var unitMode: UInt8 = 0
    var lidarConfig: UInt8 = 0
    var reserved: UInt8 = 0

    var data: Data {
        var bytes = Data()
        let rawOffset = UInt16(bitPattern: offsetInches)
        bytes.append(UInt8(rawOffset & 0x00FF))
        bytes.append(UInt8((rawOffset >> 8) & 0x00FF))
        bytes.append(responseMode.rawValue)
        bytes.append(unitMode)
        bytes.append(lidarConfig)
        bytes.append(reserved)
        return bytes
    }
}

extension Double {
    var cmToInches: Double { self * 0.393701 }
}

struct FirmwareManifest: Decodable {
    struct FirmwareFile: Decodable, Identifiable {
        let target: String
        let version: String
        let url: URL
        let size: Int?
        let notes: String?

        var id: String { "\(target.uppercased())-\(version)-\(url.absoluteString)" }
    }

    let releasedAt: String?
    let files: [FirmwareFile]

    func file(for route: String) -> FirmwareFile? {
        files.first { $0.target.caseInsensitiveCompare(route) == .orderedSame }
    }
}
