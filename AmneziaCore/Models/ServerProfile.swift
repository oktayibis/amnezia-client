import Foundation

public enum ProtocolType: String, Codable, Sendable, CaseIterable {
    case amneziaWg = "AmneziaWG"
    case wireGuard = "WireGuard"
    case openVpn = "OpenVPN"
    case xray = "XRay"

    public var badgeTitle: String {
        switch self {
        case .amneziaWg: return "AWG (Obfuscated)"
        case .wireGuard: return "WireGuard"
        case .openVpn: return "OpenVPN"
        case .xray: return "XRay"
        }
    }
}

/// Unified VPN Server Configuration Profile
public struct ServerProfile: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var protocolType: ProtocolType
    
    // Endpoint
    public var endpointHost: String
    public var endpointPort: UInt16
    
    // Cryptographic Keys
    public var clientPrivateKey: String
    public var serverPublicKey: String
    public var presharedKey: String?
    
    // Network Settings
    public var clientAddresses: [String]
    public var dnsServers: [String]
    public var allowedIps: [String]
    public var mtu: UInt16?
    public var persistentKeepalive: UInt16?
    /// AmneziaWG 3.x allows a randomized keepalive range such as "22-30".
    /// When set it takes precedence over `persistentKeepalive`.
    public var persistentKeepaliveRange: String?
    
    // AmneziaWG Obfuscation (if applicable)
    public var awgParameters: AwgParameters?
    
    // Metadata
    public var rawConfig: String?
    public var createdAt: Date
    public var lastConnectedAt: Date?
    public var pingMs: Int?
    public var countryCode: String?

    public init(
        id: UUID = UUID(),
        name: String,
        protocolType: ProtocolType = .amneziaWg,
        endpointHost: String,
        endpointPort: UInt16 = 51820,
        clientPrivateKey: String,
        serverPublicKey: String,
        presharedKey: String? = nil,
        clientAddresses: [String],
        dnsServers: [String] = ["1.1.1.1", "1.0.0.1"],
        allowedIps: [String] = ["0.0.0.0/0", "::/0"],
        mtu: UInt16? = nil,
        persistentKeepalive: UInt16? = 25,
        persistentKeepaliveRange: String? = nil,
        awgParameters: AwgParameters? = nil,
        rawConfig: String? = nil,
        createdAt: Date = Date(),
        lastConnectedAt: Date? = nil,
        pingMs: Int? = nil,
        countryCode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.protocolType = protocolType
        self.endpointHost = endpointHost
        self.endpointPort = endpointPort
        self.clientPrivateKey = clientPrivateKey
        self.serverPublicKey = serverPublicKey
        self.presharedKey = presharedKey
        self.clientAddresses = clientAddresses
        self.dnsServers = dnsServers
        self.allowedIps = allowedIps
        self.mtu = mtu
        self.persistentKeepalive = persistentKeepalive
        self.persistentKeepaliveRange = persistentKeepaliveRange
        self.awgParameters = awgParameters
        self.rawConfig = rawConfig
        self.createdAt = createdAt
        self.lastConnectedAt = lastConnectedAt
        self.pingMs = pingMs
        self.countryCode = countryCode
    }

    /// The PersistentKeepalive value as written in wg-quick: the range if present, else the number.
    public var persistentKeepaliveValue: String? {
        persistentKeepaliveRange ?? persistentKeepalive.map(String.init)
    }

    /// Full formatted endpoint "host:port"
    public var endpointString: String {
        "\(endpointHost):\(endpointPort)"
    }

    /// Country emoji flag based on countryCode if available, else a globe
    public var flagEmoji: String {
        guard let countryCode = countryCode?.uppercased(), countryCode.count == 2 else {
            return "🌐"
        }
        let base: UInt32 = 127397
        var scalarView = String.UnicodeScalarView()
        for scalar in countryCode.unicodeScalars {
            if let newScalar = UnicodeScalar(base + scalar.value) {
                scalarView.append(newScalar)
            }
        }
        return String(scalarView)
    }
}
