import Foundation

public enum WgQuickParserError: Error, LocalizedError {
    case missingInterfaceSection
    case missingPeerSection
    case missingPrivateKey
    case missingPublicKey
    case missingEndpoint
    case invalidEndpoint(String)
    case invalidPort(String)

    public var errorDescription: String? {
        switch self {
        case .missingInterfaceSection:
            return "Configuration is missing [Interface] section"
        case .missingPeerSection:
            return "Configuration is missing [Peer] section"
        case .missingPrivateKey:
            return "Interface is missing PrivateKey"
        case .missingPublicKey:
            return "Peer is missing PublicKey"
        case .missingEndpoint:
            return "Peer is missing Endpoint"
        case .invalidEndpoint(let ep):
            return "Invalid endpoint format: '\(ep)'"
        case .invalidPort(let p):
            return "Invalid port: '\(p)'"
        }
    }
}

public final class WgQuickConfigParser: Sendable {

    /// Parses a wg-quick / awg-quick configuration text into a `ServerProfile`
    public static func parse(_ text: String, profileName: String? = nil) throws -> ServerProfile {
        var interfaceAttrs = [String: String]()
        var peerAttrs = [String: String]()

        enum Section {
            case none
            case interface
            case peer
        }

        var currentSection = Section.none
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip comments
            if let commentIndex = trimmed.firstIndex(of: "#") {
                trimmed = String(trimmed[..<commentIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !trimmed.isEmpty else { continue }

            let lower = trimmed.lowercased()
            if lower == "[interface]" {
                currentSection = .interface
                continue
            } else if lower == "[peer]" {
                currentSection = .peer
                continue
            }

            guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[trimmed.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            switch currentSection {
            case .interface:
                if let existing = interfaceAttrs[key.lowercased()] {
                    interfaceAttrs[key.lowercased()] = existing + "," + value
                } else {
                    interfaceAttrs[key.lowercased()] = value
                }
            case .peer:
                if let existing = peerAttrs[key.lowercased()] {
                    peerAttrs[key.lowercased()] = existing + "," + value
                } else {
                    peerAttrs[key.lowercased()] = value
                }
            case .none:
                break
            }
        }

        guard !interfaceAttrs.isEmpty else {
            throw WgQuickParserError.missingInterfaceSection
        }
        guard !peerAttrs.isEmpty else {
            throw WgQuickParserError.missingPeerSection
        }

        guard let privateKey = interfaceAttrs["privatekey"], !privateKey.isEmpty else {
            throw WgQuickParserError.missingPrivateKey
        }
        guard let publicKey = peerAttrs["publickey"], !publicKey.isEmpty else {
            throw WgQuickParserError.missingPublicKey
        }
        guard let endpoint = peerAttrs["endpoint"], !endpoint.isEmpty else {
            throw WgQuickParserError.missingEndpoint
        }

        // Parse Endpoint host:port
        let (host, port) = try parseEndpoint(endpoint)

        // Parse Addresses
        let addresses: [String]
        if let addr = interfaceAttrs["address"] {
            addresses = addr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        } else {
            addresses = ["10.8.0.2/32"]
        }

        // Parse DNS (ignore unexpanded Amnezia template placeholders like $PRIMARY_DNS / $SECONDARY_DNS)
        let dnsList: [String]
        if let dns = interfaceAttrs["dns"] {
            let parsedDns = dns
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("$") }
            dnsList = parsedDns.isEmpty ? ["1.1.1.1", "1.0.0.1"] : parsedDns
        } else {
            dnsList = ["1.1.1.1", "1.0.0.1"]
        }

        // Parse AllowedIPs
        let allowedIps: [String]
        if let ips = peerAttrs["allowedips"] {
            allowedIps = ips.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        } else {
            allowedIps = ["0.0.0.0/0", "::/0"]
        }

        let presharedKey = peerAttrs["presharedkey"]
        let mtu = interfaceAttrs["mtu"].flatMap { UInt16($0) }
        let (persistentKeepalive, persistentKeepaliveRange) = parseKeepalive(peerAttrs["persistentkeepalive"])

        // Parse AWG Obfuscation parameters
        let awg = AwgParameters(
            jc: interfaceAttrs["jc"].flatMap { UInt16($0) },
            jmin: interfaceAttrs["jmin"].flatMap { UInt16($0) },
            jmax: interfaceAttrs["jmax"].flatMap { UInt16($0) },
            s1: interfaceAttrs["s1"].flatMap { UInt16($0) },
            s2: interfaceAttrs["s2"].flatMap { UInt16($0) },
            s3: interfaceAttrs["s3"].flatMap { UInt16($0) },
            s4: interfaceAttrs["s4"].flatMap { UInt16($0) },
            h1: interfaceAttrs["h1"],
            h2: interfaceAttrs["h2"],
            h3: interfaceAttrs["h3"],
            h4: interfaceAttrs["h4"],
            i1: interfaceAttrs["i1"],
            i2: interfaceAttrs["i2"],
            i3: interfaceAttrs["i3"],
            i4: interfaceAttrs["i4"],
            i5: interfaceAttrs["i5"],
            awg3: Dictionary(uniqueKeysWithValues: AwgParameters.awg3Keys.compactMap { key in
                interfaceAttrs[key.lowercased()].map { (key, $0) }
            })
        )

        let protocolType: ProtocolType = awg.hasObfuscation ? .amneziaWg : .wireGuard
        let name = profileName ?? "AWG (\(host))"

        return ServerProfile(
            name: name,
            protocolType: protocolType,
            endpointHost: host,
            endpointPort: port,
            clientPrivateKey: privateKey,
            serverPublicKey: publicKey,
            presharedKey: presharedKey,
            clientAddresses: addresses,
            dnsServers: dnsList,
            allowedIps: allowedIps,
            mtu: mtu,
            persistentKeepalive: persistentKeepalive,
            persistentKeepaliveRange: persistentKeepaliveRange,
            awgParameters: awg.hasObfuscation ? awg : nil,
            rawConfig: text
        )
    }

    /// Serializes a `ServerProfile` into standard or AmneziaWG `.conf` text
    public static func serialize(_ profile: ServerProfile) -> String {
        var output = "[Interface]\n"
        output += "PrivateKey = \(profile.clientPrivateKey)\n"
        output += "Address = \(profile.clientAddresses.joined(separator: ", "))\n"
        if !profile.dnsServers.isEmpty {
            output += "DNS = \(profile.dnsServers.joined(separator: ", "))\n"
        }
        if let mtu = profile.mtu {
            output += "MTU = \(mtu)\n"
        }

        // AmneziaWG obfuscation parameters
        if let awg = profile.awgParameters {
            if let jc = awg.jc { output += "Jc = \(jc)\n" }
            if let jmin = awg.jmin { output += "Jmin = \(jmin)\n" }
            if let jmax = awg.jmax { output += "Jmax = \(jmax)\n" }
            if let s1 = awg.s1 { output += "S1 = \(s1)\n" }
            if let s2 = awg.s2 { output += "S2 = \(s2)\n" }
            if let s3 = awg.s3 { output += "S3 = \(s3)\n" }
            if let s4 = awg.s4 { output += "S4 = \(s4)\n" }
            if let h1 = awg.h1 { output += "H1 = \(h1)\n" }
            if let h2 = awg.h2 { output += "H2 = \(h2)\n" }
            if let h3 = awg.h3 { output += "H3 = \(h3)\n" }
            if let h4 = awg.h4 { output += "H4 = \(h4)\n" }
            if let i1 = awg.i1 { output += "I1 = \(i1)\n" }
            if let i2 = awg.i2 { output += "I2 = \(i2)\n" }
            if let i3 = awg.i3 { output += "I3 = \(i3)\n" }
            if let i4 = awg.i4 { output += "I4 = \(i4)\n" }
            if let i5 = awg.i5 { output += "I5 = \(i5)\n" }
            for (key, value) in awg.orderedAwg3 { output += "\(key) = \(value)\n" }
        }

        output += "\n[Peer]\n"
        output += "PublicKey = \(profile.serverPublicKey)\n"
        if let psk = profile.presharedKey, !psk.isEmpty {
            output += "PresharedKey = \(psk)\n"
        }
        output += "Endpoint = \(profile.endpointHost):\(profile.endpointPort)\n"
        output += "AllowedIPs = \(profile.allowedIps.joined(separator: ", "))\n"
        if let keepalive = profile.persistentKeepaliveValue {
            output += "PersistentKeepalive = \(keepalive)\n"
        }

        return output
    }

    // MARK: - Helpers

    /// PersistentKeepalive is a number in WireGuard and AWG 2.0, and may be a range ("22-30") in AWG 3.x.
    static func parseKeepalive(_ raw: String?) -> (UInt16?, String?) {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return (nil, nil) }
        if let value = UInt16(raw) { return (value, nil) }
        let bounds = raw.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        if bounds.count == 2, let low = UInt16(bounds[0]), let high = UInt16(bounds[1]), low <= high {
            return (nil, "\(low)-\(high)")
        }
        return (nil, nil)
    }

    private static func parseEndpoint(_ endpoint: String) throws -> (String, UInt16) {
        // Handle IPv6 bracket notation [2001:db8::1]:51820 or ipv4:port
        if endpoint.hasPrefix("[") {
            guard let closeBracket = endpoint.firstIndex(of: "]"),
                  let colonIndex = endpoint[closeBracket...].firstIndex(of: ":") else {
                throw WgQuickParserError.invalidEndpoint(endpoint)
            }
            let host = String(endpoint[endpoint.index(after: endpoint.startIndex)..<closeBracket])
            let portStr = String(endpoint[endpoint.index(after: colonIndex)...])
            guard let port = UInt16(portStr) else {
                throw WgQuickParserError.invalidPort(portStr)
            }
            return (host, port)
        } else {
            let parts = endpoint.components(separatedBy: ":")
            guard parts.count == 2 else {
                throw WgQuickParserError.invalidEndpoint(endpoint)
            }
            let host = parts[0]
            guard let port = UInt16(parts[1]) else {
                throw WgQuickParserError.invalidPort(parts[1])
            }
            return (host, port)
        }
    }
}
