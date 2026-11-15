import Foundation

public enum AmneziaDecoderError: Error, LocalizedError {
    case invalidUrlScheme
    case base64DecodingFailed
    case jsonParsingFailed(String)
    case unsupportedContainer(String)
    case missingRequiredKeys(String)

    public var errorDescription: String? {
        switch self {
        case .invalidUrlScheme:
            return "URL does not have a valid vpn:// scheme"
        case .base64DecodingFailed:
            return "Failed to decode base64 data"
        case .jsonParsingFailed(let msg):
            return "JSON parsing failed: \(msg)"
        case .unsupportedContainer(let c):
            return "Container '\(c)' is not supported yet"
        case .missingRequiredKeys(let k):
            return "Configuration is missing required keys: \(k)"
        }
    }
}

public final class AmneziaUrlDecoder: Sendable {
    
    /// Decodes a `vpn://...` URL or raw Base64/JSON string into a `ServerProfile`
    public static func decode(_ input: String) throws -> ServerProfile {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Strip vpn:// prefix if present
        var payload = trimmed
        if payload.lowercased().hasPrefix("vpn://") {
            payload = String(payload.dropFirst(6))
            // Clean up any smart dashes or internal whitespace from iOS pasteboard/texteditor
            payload = payload
                .replacingOccurrences(of: "\u{2013}", with: "-") // En-dash
                .replacingOccurrences(of: "\u{2014}", with: "-") // Em-dash
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\t", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
        }
        
        // Try decoding as Base64URL
        guard let data = decodeBase64URL(payload) else {
            // Check if input is already raw JSON
            if let rawData = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
                return try parseAmneziaJson(json, rawConfig: trimmed)
            }
            // Check if input is wg-quick format
            if trimmed.contains("[Interface]") && trimmed.contains("[Peer]") {
                return try WgQuickConfigParser.parse(trimmed)
            }
            throw AmneziaDecoderError.base64DecodingFailed
        }
        
        // Try decompressing with Qt qCompress; fallback to raw data
        let jsonData: Data
        if let decompressed = try? ZlibHelper.decompressQt(data) {
            jsonData = decompressed
        } else {
            jsonData = data
        }
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            if let stringContent = String(data: jsonData, encoding: .utf8) {
                // If it decompressed to a wg-quick config string instead of JSON
                if stringContent.contains("[Interface]") && stringContent.contains("[Peer]") {
                    return try WgQuickConfigParser.parse(stringContent)
                }
                throw AmneziaDecoderError.jsonParsingFailed(stringContent)
            }
            throw AmneziaDecoderError.jsonParsingFailed("Invalid UTF-8 data")
        }
        
        return try parseAmneziaJson(jsonObject, rawConfig: trimmed)
    }

    /// Generates an Amnezia `vpn://...` URL from a `ServerProfile`
    public static func encodeToUrl(_ profile: ServerProfile) throws -> String {
        let json = profileToAmneziaJson(profile)
        let jsonData = try JSONSerialization.data(withJSONObject: json, options: [])
        let compressed = try ZlibHelper.compressQt(jsonData)
        let base64Url = encodeBase64URL(compressed)
        return "vpn://\(base64Url)"
    }

    // MARK: - Internal JSON Parsing

    private static func parseAmneziaJson(_ root: [String: Any], rawConfig: String) throws -> ServerProfile {
        let description = (root["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootHostName = root["hostName"] as? String
        
        var dnsList = [String]()
        if let dns1 = root["dns1"] as? String, !dns1.isEmpty { dnsList.append(dns1) }
        if let dns2 = root["dns2"] as? String, !dns2.isEmpty { dnsList.append(dns2) }

        // Find primary container
        guard let containers = root["containers"] as? [[String: Any]], !containers.isEmpty else {
            // Check if root itself contains last_config or protocol keys directly
            if let lastConfig = root["last_config"] {
                return try parseLastConfig(lastConfig, containerParams: root, root: root, description: description, rootHost: rootHostName, dnsList: dnsList, rawConfig: rawConfig)
            }
            throw AmneziaDecoderError.missingRequiredKeys("containers")
        }

        let defaultContainer = root["defaultContainer"] as? String
        let targetContainer: [String: Any]
        if let defName = defaultContainer, let match = containers.first(where: { ($0["container"] as? String) == defName }) {
            targetContainer = match
        } else if let match = containers.first(where: {
            let c = ($0["container"] as? String)?.lowercased() ?? ""
            return c.contains("awg") || c.contains("wireguard")
        }) {
            targetContainer = match
        } else {
            targetContainer = containers[0]
        }

        let containerType = (targetContainer["container"] as? String) ?? "amnezia-awg"
        
        // Extract protocol dict (e.g. "awg", "wireguard", etc.)
        var protocolConfig: [String: Any]? = nil
        let protocolKey = containerType.replacingOccurrences(of: "amnezia-", with: "")
        
        if let cfg = targetContainer[protocolKey] as? [String: Any] {
            protocolConfig = cfg
        } else if let cfg = targetContainer["awg"] as? [String: Any] {
            protocolConfig = cfg
        } else if let cfg = targetContainer["wireguard"] as? [String: Any] {
            protocolConfig = cfg
        } else {
            for (_, val) in targetContainer {
                if let subDict = val as? [String: Any], subDict["last_config"] != nil {
                    protocolConfig = subDict
                    break
                }
            }
        }

        guard let protoDict = protocolConfig, let lastConfigObj = protoDict["last_config"] else {
            throw AmneziaDecoderError.missingRequiredKeys("last_config in container \(containerType)")
        }

        return try parseLastConfig(lastConfigObj, containerParams: protoDict, containerType: containerType, root: root, description: description, rootHost: rootHostName, dnsList: dnsList, rawConfig: rawConfig)
    }

    private static func parseLastConfig(
        _ lastConfigObj: Any,
        containerParams: [String: Any] = [:],
        containerType: String = "amnezia-awg",
        root: [String: Any],
        description: String?,
        rootHost: String?,
        dnsList: [String],
        rawConfig: String
    ) throws -> ServerProfile {
        var configDict: [String: Any]
        if let str = lastConfigObj as? String {
            guard let data = str.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // If last_config is directly a wg-quick config string (e.g. [Interface]...)
                if str.contains("[Interface]") && str.contains("[Peer]") {
                    return try WgQuickConfigParser.parse(str)
                }
                throw AmneziaDecoderError.jsonParsingFailed("Malformed last_config string")
            }
            configDict = dict
        } else if let dict = lastConfigObj as? [String: Any] {
            configDict = dict
        } else {
            throw AmneziaDecoderError.jsonParsingFailed("last_config is neither string nor dict")
        }

        // Helper to find string across multiple candidate keys (camelCase, snake_case, standard)
        func findString(_ keys: [String]) -> String? {
            for k in keys {
                if let s = configDict[k] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }

        // If configDict has a full wg-quick "config" string and keys are missing, we can also extract from it
        if let embeddedConfig = configDict["config"] as? String,
           (findString(["clientPrivKey", "client_priv_key"]) == nil || findString(["serverPubKey", "server_pub_key"]) == nil),
           let parsed = try? WgQuickConfigParser.parse(embeddedConfig) {
            return parsed
        }

        guard let clientPrivKey = findString(["clientPrivKey", "client_priv_key", "client_private_key", "PrivateKey"]),
              let serverPubKey = findString(["serverPubKey", "server_pub_key", "server_public_key", "PublicKey"]) else {
            throw AmneziaDecoderError.missingRequiredKeys("clientPrivKey, serverPubKey")
        }

        var hostName = findString(["hostName", "host_name", "server_ip", "serverIp", "Endpoint"]) ?? rootHost ?? "127.0.0.1"
        var port: UInt16 = 51820

        if let pInt = configDict["port"] as? Int ?? configDict["server_port"] as? Int {
            port = UInt16(pInt)
        } else if let pStr = findString(["port", "server_port"]), let p = UInt16(pStr) {
            port = p
        }

        // If hostName contains port (e.g. 1.2.3.4:51820)
        if hostName.contains(":") && !hostName.contains("[") {
            let parts = hostName.split(separator: ":")
            if parts.count == 2 {
                hostName = String(parts[0])
                if let p = UInt16(parts[1]) {
                    port = p
                }
            }
        }

        var clientAddresses = [String]()
        if let ipStr = findString(["clientIp", "client_ip", "Address"]) {
            var addr = ipStr
            if !addr.contains("/") {
                addr = addr.contains(":") ? "\(addr)/128" : "\(addr)/32"
            }
            clientAddresses.append(addr)
        } else if let ips = (configDict["clientIp"] as? [String]) ?? (configDict["client_ip"] as? [String]) {
            clientAddresses.append(contentsOf: ips.map { $0.contains("/") ? $0 : ($0.contains(":") ? "\($0)/128" : "\($0)/32") })
        }

        var allowedIps = [String]()
        if let aIps = (configDict["allowedIps"] as? [String]) ?? (configDict["allowed_ips"] as? [String]), !aIps.isEmpty {
            allowedIps = aIps
        } else if let aIpsStr = findString(["allowedIps", "allowed_ips", "AllowedIPs"]) {
            allowedIps = aIpsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            allowedIps = ["0.0.0.0/0", "::/0"]
        }

        let psk = findString(["pskKey", "psk_key", "preshared_key", "PresharedKey"])

        var mtu: UInt16?
        if let mtuInt = configDict["mtu"] as? Int ?? configDict["MTU"] as? Int {
            mtu = UInt16(mtuInt)
        } else if let mtuStr = findString(["mtu", "MTU"]), let m = UInt16(mtuStr) {
            mtu = m
        }

        var keepalive: UInt16?
        var keepaliveRange: String?
        if let kInt = configDict["persistentKeepAlive"] as? Int ?? configDict["persistent_keep_alive"] as? Int {
            keepalive = UInt16(kInt)
        } else if let kStr = findString(["persistentKeepAlive", "persistent_keep_alive", "PersistentKeepalive"]) {
            (keepalive, keepaliveRange) = WgQuickConfigParser.parseKeepalive(kStr)
        }

        // Parse AWG obfuscation parameters from both container parameters and last_config
        var mergedAwgDict = containerParams
        for (k, v) in configDict {
            mergedAwgDict[k] = v
        }
        let awg = parseAwgParams(from: mergedAwgDict)
        let isAwg = containerType.contains("awg") || awg.hasObfuscation
        let protocolType: ProtocolType = isAwg ? .amneziaWg : .wireGuard
        let serverName = description?.isEmpty == false ? description! : "AWG (\(hostName))"

        return ServerProfile(
            name: serverName,
            protocolType: protocolType,
            endpointHost: hostName,
            endpointPort: port,
            clientPrivateKey: clientPrivKey,
            serverPublicKey: serverPubKey,
            presharedKey: psk,
            clientAddresses: clientAddresses.isEmpty ? ["10.8.0.2/32"] : clientAddresses,
            dnsServers: dnsList.isEmpty ? ["1.1.1.1", "1.0.0.1"] : dnsList,
            allowedIps: allowedIps,
            mtu: mtu,
            persistentKeepalive: keepalive,
            persistentKeepaliveRange: keepaliveRange,
            awgParameters: awg.hasObfuscation ? awg : nil,
            rawConfig: rawConfig
        )
    }

    private static func parseAwgParams(from dict: [String: Any]) -> AwgParameters {
        func getUInt16(_ key: String) -> UInt16? {
            if let val = dict[key] as? Int { return UInt16(val) }
            if let val = dict[key.lowercased()] as? Int { return UInt16(val) }
            if let str = dict[key] as? String, let val = UInt16(str.trimmingCharacters(in: .whitespaces)) { return val }
            if let str = dict[key.lowercased()] as? String, let val = UInt16(str.trimmingCharacters(in: .whitespaces)) { return val }
            return nil
        }
        func getString(_ key: String) -> String? {
            if let str = dict[key] as? String, !str.trimmingCharacters(in: .whitespaces).isEmpty {
                return str.trimmingCharacters(in: .whitespaces)
            }
            if let str = dict[key.lowercased()] as? String, !str.trimmingCharacters(in: .whitespaces).isEmpty {
                return str.trimmingCharacters(in: .whitespaces)
            }
            // JSONSerialization hands booleans over as NSNumber, so check for CFBoolean
            // before Int; otherwise `true` would become "1".
            if let number = dict[key] as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
                return number.stringValue
            }
            return nil
        }

        return AwgParameters(
            jc: getUInt16("Jc"),
            jmin: getUInt16("Jmin"),
            jmax: getUInt16("Jmax"),
            s1: getUInt16("S1"),
            s2: getUInt16("S2"),
            s3: getUInt16("S3"),
            s4: getUInt16("S4"),
            h1: getString("H1"),
            h2: getString("H2"),
            h3: getString("H3"),
            h4: getString("H4"),
            i1: getString("I1"),
            i2: getString("I2"),
            i3: getString("I3"),
            i4: getString("I4"),
            i5: getString("I5"),
            awg3: Dictionary(uniqueKeysWithValues: AwgParameters.awg3Keys.compactMap { key in
                getString(key).map { (key, $0) }
            })
        )
    }

    private static func profileToAmneziaJson(_ profile: ServerProfile) -> [String: Any] {
        var lastConfigDict: [String: Any] = [
            "clientPrivKey": profile.clientPrivateKey,
            "serverPubKey": profile.serverPublicKey,
            "clientIp": profile.clientAddresses.first ?? "10.8.0.2/32",
            "hostName": profile.endpointHost,
            "port": Int(profile.endpointPort),
            "allowedIps": profile.allowedIps
        ]
        
        if let psk = profile.presharedKey { lastConfigDict["pskKey"] = psk }
        if let mtu = profile.mtu { lastConfigDict["mtu"] = Int(mtu) }
        if let range = profile.persistentKeepaliveRange {
            lastConfigDict["persistentKeepAlive"] = range
        } else if let keepalive = profile.persistentKeepalive {
            lastConfigDict["persistentKeepAlive"] = Int(keepalive)
        }
        
        if let awg = profile.awgParameters {
            for (k, v) in awg.configDictionary {
                lastConfigDict[k] = v
            }
        }
        
        let lastConfigJsonData = (try? JSONSerialization.data(withJSONObject: lastConfigDict, options: [])) ?? Data()
        let lastConfigJsonString = String(data: lastConfigJsonData, encoding: .utf8) ?? "{}"
        
        let containerName = (profile.protocolType == .amneziaWg) ? "amnezia-awg" : "amnezia-wireguard"
        let protocolKey = (profile.protocolType == .amneziaWg) ? "awg" : "wireguard"
        
        let container: [String: Any] = [
            "container": containerName,
            protocolKey: [
                "last_config": lastConfigJsonString
            ]
        ]
        
        var root: [String: Any] = [
            "containers": [container],
            "defaultContainer": containerName,
            "description": profile.name,
            "hostName": profile.endpointHost
        ]
        
        if profile.dnsServers.indices.contains(0) { root["dns1"] = profile.dnsServers[0] }
        if profile.dnsServers.indices.contains(1) { root["dns2"] = profile.dnsServers[1] }
        
        return root
    }

    // MARK: - Base64URL Helpers

    public static func decodeBase64URL(_ input: String) -> Data? {
        var base64 = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }

    public static func encodeBase64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
