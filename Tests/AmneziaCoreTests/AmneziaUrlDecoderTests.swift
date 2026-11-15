import XCTest
@testable import AmneziaCore

final class AmneziaUrlDecoderTests: XCTestCase {

    func testDecodeAmneziaJsonAndEncodeRoundtrip() throws {
        let sampleProfile = ServerProfile(
            name: "Frankfurt AmneziaWG",
            protocolType: .amneziaWg,
            endpointHost: "198.51.100.25",
            endpointPort: 51820,
            clientPrivateKey: "yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=",
            serverPublicKey: "HIgoByamLBM63vLzGsm53+zR2yv8a0Q9G4v0vXgZ5xU=",
            presharedKey: "pskSecret1234567890abcdef=",
            clientAddresses: ["10.8.0.2/32"],
            dnsServers: ["1.1.1.1", "1.0.0.1"],
            allowedIps: ["0.0.0.0/0", "::/0"],
            mtu: 1280,
            persistentKeepalive: 25,
            awgParameters: AwgParameters(
                jc: 4,
                jmin: 40,
                jmax: 70,
                s1: 15,
                s2: 30,
                h1: "12345678",
                h2: "87654321",
                h3: "11223344",
                h4: "44332211"
            )
        )

        // Encode to vpn:// URL
        let urlString = try AmneziaUrlDecoder.encodeToUrl(sampleProfile)
        XCTAssertTrue(urlString.hasPrefix("vpn://"))

        // Decode from vpn:// URL
        let decodedProfile = try AmneziaUrlDecoder.decode(urlString)

        XCTAssertEqual(decodedProfile.name, sampleProfile.name)
        XCTAssertEqual(decodedProfile.protocolType, .amneziaWg)
        XCTAssertEqual(decodedProfile.endpointHost, "198.51.100.25")
        XCTAssertEqual(decodedProfile.endpointPort, 51820)
        XCTAssertEqual(decodedProfile.clientPrivateKey, sampleProfile.clientPrivateKey)
        XCTAssertEqual(decodedProfile.serverPublicKey, sampleProfile.serverPublicKey)
        XCTAssertEqual(decodedProfile.presharedKey, sampleProfile.presharedKey)
        XCTAssertEqual(decodedProfile.clientAddresses, ["10.8.0.2/32"])
        XCTAssertEqual(decodedProfile.dnsServers, ["1.1.1.1", "1.0.0.1"])
        XCTAssertEqual(decodedProfile.mtu, 1280)
        XCTAssertEqual(decodedProfile.persistentKeepalive, 25)

        // Check AWG Obfuscation parameters
        let awg = try XCTUnwrap(decodedProfile.awgParameters)
        XCTAssertEqual(awg.jc, 4)
        XCTAssertEqual(awg.jmin, 40)
        XCTAssertEqual(awg.jmax, 70)
        XCTAssertEqual(awg.s1, 15)
        XCTAssertEqual(awg.s2, 30)
        XCTAssertEqual(awg.h1, "12345678")
        XCTAssertEqual(awg.h2, "87654321")
        XCTAssertEqual(awg.h3, "11223344")
        XCTAssertEqual(awg.h4, "44332211")
    }

    func testDecodeRawJsonString() throws {
        let jsonStr = """
        {
          "containers": [
            {
              "container": "amnezia-wireguard",
              "wireguard": {
                "last_config": "{\\"clientPrivKey\\":\\"AAAA...\\",\\"serverPubKey\\":\\"BBBB...\\",\\"clientIp\\":\\"10.0.0.5/32\\",\\"hostName\\":\\"vpn.example.com\\",\\"port\\":51820}"
              }
            }
          ],
          "description": "Standard WireGuard Server",
          "dns1": "8.8.8.8"
        }
        """

        let profile = try AmneziaUrlDecoder.decode(jsonStr)
        XCTAssertEqual(profile.name, "Standard WireGuard Server")
        XCTAssertEqual(profile.protocolType, .wireGuard)
        XCTAssertEqual(profile.endpointHost, "vpn.example.com")
        XCTAssertEqual(profile.endpointPort, 51820)
        XCTAssertEqual(profile.dnsServers, ["8.8.8.8"])
    }

    /// last_config as the official AmneziaVPN client writes it for an AWG 3.1 container
    /// (key names from its WGConfig.swift CodingKeys).
    func testDecodeAwg3JsonAndEncodeRoundtrip() throws {
        let lastConfig: [String: Any] = [
            "client_priv_key": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=",
            "server_pub_key": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb=",
            "psk_key": "ccccccccccccccccccccccccccccccccccccccccccc=",
            "client_ip": "10.8.1.10",
            "hostName": "203.0.113.10",
            "port": 34316,
            "persistent_keep_alive": "22-30",
            "Jc": "4", "H1": "1351553658-1920902942", "S3": "37", "S4": "9",
            "HeaderProtectionKey": "ddddddddddddddddddddddddddddddddddddddddddd=",
            "ContentPaddingAddition": "0-64",
            "RandomTrailers": true,
            "MaxHandshakeAttempts": 18
        ]
        let lastConfigString = String(data: try JSONSerialization.data(withJSONObject: lastConfig), encoding: .utf8)!
        let root: [String: Any] = [
            "containers": [["container": "amnezia-awg", "awg": ["last_config": lastConfigString]]],
            "defaultContainer": "amnezia-awg",
            "description": "AWG 3.1"
        ]
        let json = String(data: try JSONSerialization.data(withJSONObject: root), encoding: .utf8)!

        let profile = try AmneziaUrlDecoder.decode(json)
        XCTAssertEqual(profile.persistentKeepaliveRange, "22-30")
        let awg = try XCTUnwrap(profile.awgParameters)
        XCTAssertEqual(awg.s4, 9)
        XCTAssertEqual(awg.awg3?["HeaderProtectionKey"], "ddddddddddddddddddddddddddddddddddddddddddd=")
        XCTAssertEqual(awg.awg3?["ContentPaddingAddition"], "0-64")
        XCTAssertEqual(awg.awg3?["RandomTrailers"], "true")
        XCTAssertEqual(awg.awg3?["MaxHandshakeAttempts"], "18")

        // What the tunnel receives keeps the AWG 3.x settings.
        let wgQuick = WgQuickConfigParser.serialize(profile)
        XCTAssertTrue(wgQuick.contains("HeaderProtectionKey = ddddddddddddddddddddddddddddddddddddddddddd="))
        XCTAssertTrue(wgQuick.contains("RandomTrailers = true"))
        XCTAssertTrue(wgQuick.contains("PersistentKeepalive = 22-30"))

        // Sharing the profile again (vpn:// export) keeps them too.
        let reimported = try AmneziaUrlDecoder.decode(try AmneziaUrlDecoder.encodeToUrl(profile))
        XCTAssertEqual(reimported.awgParameters?.awg3, awg.awg3)
        XCTAssertEqual(reimported.persistentKeepaliveRange, "22-30")
    }

}
