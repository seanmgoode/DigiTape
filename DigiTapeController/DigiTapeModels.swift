import Foundation

enum ThemeColor: UInt8, CaseIterable, Identifiable {
    case white = 0
    case green = 1
    case blue = 2
    case red = 3
    case yellow = 4
    case orange = 5
    case purple = 6
    case gray = 7

    var id: UInt8 { rawValue }

    var label: String {
        switch self {
        case .white: return "WHITE"
        case .green: return "GREEN"
        case .blue: return "BLUE"
        case .red: return "RED"
        case .yellow: return "YELLOW"
        case .orange: return "ORANGE"
        case .purple: return "PURPLE"
        case .gray: return "GRAY"
        }
    }
}

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

    // Supports legacy 15/16-byte payloads, payloads with TX input voltage appended,
    // and current firmware packets with the DT protocol trailer appended.
    init?(data: Data) {
        let packetData: Data
        if let trailerOffset = data.digitapeProtocolTrailerOffset {
            packetData = data.prefix(trailerOffset)
        } else if data.count > 18 {
            packetData = data.prefix(16)
        } else {
            packetData = data
        }

        guard packetData.count == 15 || packetData.count == 16 || packetData.count == 17 || packetData.count == 18 else { return nil }
        func u16(_ offset: Int) -> UInt16 {
            UInt16(packetData[offset]) | (UInt16(packetData[offset + 1]) << 8)
        }

        distanceCM = u16(0)
        errorFlag = packetData[2]

        let aligned = packetData.count == 16 || packetData.count == 18
        let packetOffset = aligned ? 4 : 3
        packetCounter = u16(packetOffset)
        responseMode = ResponseMode(rawValue: packetData[packetOffset + 2]) ?? .normal
        sensorType = SensorType(rawValue: packetData[packetOffset + 3]) ?? .unknown

        let versionStart = packetOffset + 4
        let versionBytes = packetData[versionStart..<min(versionStart + 8, packetData.count)]
        txVersion = String(bytes: versionBytes.prefix { $0 != 0 }, encoding: .utf8) ?? "--"

        let voltageOffset = versionStart + 8
        if packetData.count >= voltageOffset + 2 {
            inputMillivolts = u16(voltageOffset)
        } else {
            inputMillivolts = nil
        }
    }
}

private extension Data {
    var digitapeProtocolTrailerOffset: Int? {
        guard count >= 16 else { return nil }
        let bytes = [UInt8](self)
        for offset in 2...(bytes.count - 14) {
            if bytes[offset] == 0x44, bytes[offset + 1] == 0x54, bytes[offset + 2] == 0x02 {
                return offset
            }
        }
        return nil
    }
}

struct SettingsPacket {
    static let baseLength = 7
    static let fullLength = 45

    var offsetInches: Int16
    var responseMode: ResponseMode
    var unitMode: UInt8 = 0
    var themeColor: UInt8 = 0
    var reserved: UInt8 = 0
    var distanceFontSize: UInt8 = 0
    var parameterSnapshot: ParameterSnapshot?

    init(offsetInches: Int16, responseMode: ResponseMode, unitMode: UInt8 = 0, themeColor: UInt8 = 0, reserved: UInt8 = 0, distanceFontSize: UInt8 = 0, parameterSnapshot: ParameterSnapshot? = nil) {
        self.offsetInches = offsetInches
        self.responseMode = responseMode
        self.unitMode = unitMode
        self.themeColor = themeColor
        self.reserved = reserved
        self.distanceFontSize = distanceFontSize
        self.parameterSnapshot = parameterSnapshot
    }

    init?(data: Data) {
        guard data.count >= 6 else { return nil }
        let rawOffset = UInt16(data[0]) | (UInt16(data[1]) << 8)
        offsetInches = Int16(bitPattern: rawOffset)
        responseMode = ResponseMode(rawValue: data[2]) ?? .normal
        unitMode = data[3]
        themeColor = data[4]
        reserved = data[5]
        distanceFontSize = data.count >= 7 ? data[6] : 0
        parameterSnapshot = ParameterSnapshot(data: data)
    }

    var data: Data {
        var bytes = Data()
        let rawOffset = UInt16(bitPattern: offsetInches)
        bytes.append(UInt8(rawOffset & 0x00FF))
        bytes.append(UInt8((rawOffset >> 8) & 0x00FF))
        bytes.append(responseMode.rawValue)
        bytes.append(unitMode)
        bytes.append(themeColor)
        bytes.append(reserved)
        bytes.append(distanceFontSize)
        parameterSnapshot?.append(to: &bytes)
        return bytes
    }
}

struct ParameterSnapshot {
    static let version: UInt8 = 1
    var revision: UInt16 = 1
    var marks: [(inches: Int, colorIndex: UInt8)] = []
    var limitsActive = false
    var minLimitInches = 1
    var maxLimitInches = 99 * 12 + 99
    var lockouts: [(min: Int, max: Int)] = []

    init(revision: UInt16 = 1, marks: [(inches: Int, colorIndex: UInt8)] = [], limitsActive: Bool = false, minLimitInches: Int = 1, maxLimitInches: Int = 99 * 12 + 99, lockouts: [(min: Int, max: Int)] = []) {
        self.revision = revision
        self.marks = Array(marks.prefix(4))
        self.limitsActive = limitsActive
        self.minLimitInches = minLimitInches
        self.maxLimitInches = maxLimitInches
        self.lockouts = Array(lockouts.prefix(4))
    }

    init?(data: Data) {
        guard data.count >= SettingsPacket.fullLength else { return nil }
        guard data[7] == Self.version else { return nil }
        revision = UInt16(data[8]) | (UInt16(data[9]) << 8)
        let markCount = min(Int(data[10]), 4)
        var parsedMarks: [(inches: Int, colorIndex: UInt8)] = []
        for index in 0..<markCount {
            let base = 11 + index * 2
            parsedMarks.append((Self.readInt16(data, at: base), data[19 + index]))
        }
        marks = parsedMarks
        let flags = data[23]
        limitsActive = (flags & 0x01) != 0
        minLimitInches = max(1, Self.readInt16(data, at: 24))
        maxLimitInches = max(minLimitInches + 1, Self.readInt16(data, at: 26))
        let lockoutCount = min(Int(data[28]), 4)
        var parsedLockouts: [(min: Int, max: Int)] = []
        for index in 0..<lockoutCount {
            let minValue = Self.readInt16(data, at: 29 + index * 2)
            let maxValue = Self.readInt16(data, at: 37 + index * 2)
            parsedLockouts.append((minValue, max(maxValue, minValue + 1)))
        }
        lockouts = parsedLockouts
    }

    func append(to data: inout Data) {
        data.append(Self.version)
        Self.appendInt16(Int(revision), to: &data)
        data.append(UInt8(min(marks.count, 4)))
        for index in 0..<4 {
            Self.appendInt16(index < marks.count ? marks[index].inches : 0, to: &data)
        }
        for index in 0..<4 {
            data.append(index < marks.count ? marks[index].colorIndex : 0)
        }
        data.append(limitsActive ? 1 : 0)
        Self.appendInt16(minLimitInches, to: &data)
        Self.appendInt16(maxLimitInches, to: &data)
        data.append(UInt8(min(lockouts.count, 4)))
        for index in 0..<4 {
            Self.appendInt16(index < lockouts.count ? lockouts[index].min : 0, to: &data)
        }
        for index in 0..<4 {
            Self.appendInt16(index < lockouts.count ? lockouts[index].max : 0, to: &data)
        }
    }

    private static func readInt16(_ data: Data, at offset: Int) -> Int {
        guard offset + 1 < data.count else { return 0 }
        let raw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        return Int(Int16(bitPattern: raw))
    }

    private static func appendInt16(_ value: Int, to data: inout Data) {
        let clamped = max(Int(Int16.min), min(Int(Int16.max), value))
        let raw = UInt16(bitPattern: Int16(clamped))
        data.append(UInt8(raw & 0x00FF))
        data.append(UInt8((raw >> 8) & 0x00FF))
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
        let channel: String?
        let sha256: String?
        let signature: String?
        let signatureAlgorithm: String?
        let role: String?
        let hardware: String?
        let boardType: String?
        let hardwareRevision: String?
        let friendlyName: String?

        enum CodingKeys: String, CodingKey {
            case target
            case id
            case version
            case url
            case file
            case size
            case bytes
            case notes
            case description
            case channel
            case sha256
            case signature
            case signatureAlgorithm
            case role
            case hardware
            case boardType
            case hardwareRevision
            case friendlyName
            case label
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let decodedTarget = try container.decodeIfPresent(String.self, forKey: .target)
                ?? container.decodeIfPresent(String.self, forKey: .id)
                ?? "unknown"
            target = decodedTarget
            version = try container.decodeIfPresent(String.self, forKey: .version)
                ?? container.decodeIfPresent(String.self, forKey: .label)
                ?? decodedTarget
            if let directURL = try container.decodeIfPresent(URL.self, forKey: .url) {
                url = directURL
            } else if let file = try container.decodeIfPresent(String.self, forKey: .file), let fileURL = URL(string: file) {
                url = fileURL
            } else {
                throw DecodingError.keyNotFound(CodingKeys.url, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Firmware URL or file path missing"))
            }
            size = try container.decodeIfPresent(Int.self, forKey: .size)
                ?? container.decodeIfPresent(Int.self, forKey: .bytes)
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
                ?? container.decodeIfPresent(String.self, forKey: .description)
            channel = try container.decodeIfPresent(String.self, forKey: .channel)
            sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
            signature = try container.decodeIfPresent(String.self, forKey: .signature)
            signatureAlgorithm = try container.decodeIfPresent(String.self, forKey: .signatureAlgorithm)
            role = try container.decodeIfPresent(String.self, forKey: .role)
            hardware = try container.decodeIfPresent(String.self, forKey: .hardware)
                ?? container.decodeIfPresent(String.self, forKey: .label)
            boardType = try container.decodeIfPresent(String.self, forKey: .boardType)
            hardwareRevision = try container.decodeIfPresent(String.self, forKey: .hardwareRevision)
            friendlyName = try container.decodeIfPresent(String.self, forKey: .friendlyName)
        }

        var id: String { "\(target.uppercased())-\(version)-\(url.absoluteString)" }
    }

    let releasedAt: String?
    let package: String?
    let manifest: String?
    let manifestSha256: String?
    let manifestSignature: String?
    let files: [FirmwareFile]

    enum CodingKeys: String, CodingKey {
        case releasedAt
        case generated
        case created
        case package
        case manifest
        case manifestSha256
        case manifestSignature
        case files
        case firmware
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        releasedAt = try container.decodeIfPresent(String.self, forKey: .releasedAt)
            ?? container.decodeIfPresent(String.self, forKey: .generated)
            ?? container.decodeIfPresent(String.self, forKey: .created)
        package = try container.decodeIfPresent(String.self, forKey: .package)
        manifest = try container.decodeIfPresent(String.self, forKey: .manifest)
        manifestSha256 = try container.decodeIfPresent(String.self, forKey: .manifestSha256)
        manifestSignature = try container.decodeIfPresent(String.self, forKey: .manifestSignature)
        files = try container.decodeIfPresent([FirmwareFile].self, forKey: .files)
            ?? container.decodeIfPresent([FirmwareFile].self, forKey: .firmware)
            ?? []
    }

    func file(for route: String) -> FirmwareFile? {
        files.first { $0.target.caseInsensitiveCompare(route) == .orderedSame || ($0.role ?? "").caseInsensitiveCompare(route) == .orderedSame }
    }
}
