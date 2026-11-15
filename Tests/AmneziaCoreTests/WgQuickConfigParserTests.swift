import XCTest
@testable import AmneziaCore

final class WgQuickConfigParserTests: XCTestCase {

    func testParseAmneziaWgConf() throws {
        let conf = """
        [Interface]
        Address = 10.8.0.2/32, fd00::2/64
        PrivateKey = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=
        DNS = 1.1.1.1, 1.0.0.1
        MTU = 1360
        Jc = 4
        Jmin = 40
        Jmax = 70
        S1 = 15
        S2 = 30
        H1 = 10000001
        H2 = 10000002
        H3 = 10000003
        H4 = 10000004

        [Peer]
        PublicKey = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb=
        PresharedKey = ccccccccccccccccccccccccccccccccccccccccccc=
        Endpoint = 203.0.113.10:51820
        AllowedIPs = 0.0.0.0/0, ::/0
        PersistentKeepalive = 25
        """

        let profile = try WgQuickConfigParser.parse(conf, profileName: "Test AWG")

        XCTAssertEqual(profile.name, "Test AWG")
        XCTAssertEqual(profile.protocolType, .amneziaWg)
        XCTAssertEqual(profile.endpointHost, "203.0.113.10")
        XCTAssertEqual(profile.endpointPort, 51820)
        XCTAssertEqual(profile.clientAddresses, ["10.8.0.2/32", "fd00::2/64"])
        XCTAssertEqual(profile.dnsServers, ["1.1.1.1", "1.0.0.1"])
        XCTAssertEqual(profile.mtu, 1360)
        XCTAssertEqual(profile.persistentKeepalive, 25)

        let awg = try XCTUnwrap(profile.awgParameters)
        XCTAssertEqual(awg.jc, 4)
        XCTAssertEqual(awg.jmin, 40)
        XCTAssertEqual(awg.jmax, 70)
        XCTAssertEqual(awg.s1, 15)
        XCTAssertEqual(awg.s2, 30)
        XCTAssertEqual(awg.h1, "10000001")
        XCTAssertEqual(awg.h2, "10000002")
        XCTAssertEqual(awg.h3, "10000003")
        XCTAssertEqual(awg.h4, "10000004")

        // Roundtrip serialization
        let serialized = WgQuickConfigParser.serialize(profile)
        XCTAssertTrue(serialized.contains("Jc = 4"))
        XCTAssertTrue(serialized.contains("H1 = 10000001"))
        XCTAssertTrue(serialized.contains("Endpoint = 203.0.113.10:51820"))
    }

    func testParseStandardWireGuardConf() throws {
        let conf = """
        [Interface]
        Address = 10.0.0.2/32
        PrivateKey = Key123456789=
        DNS = 8.8.8.8

        [Peer]
        PublicKey = Key987654321=
        Endpoint = 192.0.2.1:51820
        AllowedIPs = 0.0.0.0/0
        """

        let profile = try WgQuickConfigParser.parse(conf)
        XCTAssertEqual(profile.protocolType, .wireGuard)
        XCTAssertNil(profile.awgParameters)
    }

    // MARK: - AmneziaWG 3.x

    private let awg3Conf = """
    [Interface]
    Address = 10.8.1.10/32
    DNS = 1.1.1.1, 1.0.0.1
    PrivateKey = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=
    Jc = 4
    Jmin = 10
    Jmax = 50
    S1 = 115
    S2 = 36
    S3 = 37
    S4 = 9
    H1 = 1351553658-1920902942
    H2 = 1985824122-2031951811
    H3 = 2100088783-2119911158
    H4 = 2128748706-2129059843
    I1 = <r 2><b 0x8580>
    HeaderProtectionKey = ddddddddddddddddddddddddddddddddddddddddddd=
    ContentPaddingAddition = 0-64
    RekeyAfterTime = 120
    RekeyTimeout = 5
    RejectAfterTime = 180
    KeepaliveTimeout = 10
    MaxHandshakeAttempts = 18
    RandomTrailers = true
    DisableCookies = false

    [Peer]
    PublicKey = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb=
    PresharedKey = ccccccccccccccccccccccccccccccccccccccccccc=
    AllowedIPs = 0.0.0.0/0, ::/0
    Endpoint = 203.0.113.10:34316
    PersistentKeepalive = 22-30
    """

    func testParseAwg3KeysAndKeepaliveRange() throws {
        let profile = try WgQuickConfigParser.parse(awg3Conf)

        XCTAssertEqual(profile.protocolType, .amneziaWg)
        XCTAssertNil(profile.persistentKeepalive)
        XCTAssertEqual(profile.persistentKeepaliveRange, "22-30")
        XCTAssertEqual(profile.persistentKeepaliveValue, "22-30")

        let awg = try XCTUnwrap(profile.awgParameters)
        XCTAssertEqual(awg.s4, 9)
        XCTAssertEqual(awg.awg3?["HeaderProtectionKey"], "ddddddddddddddddddddddddddddddddddddddddddd=")
        XCTAssertEqual(awg.awg3?["ContentPaddingAddition"], "0-64")
        XCTAssertEqual(awg.awg3?["RandomTrailers"], "true")
        XCTAssertEqual(awg.awg3?["DisableCookies"], "false")
        XCTAssertEqual(awg.awg3?.count, AwgParameters.awg3Keys.count)
    }

    func testAwg3RoundtripKeepsEveryKeyInTemplateOrder() throws {
        let serialized = WgQuickConfigParser.serialize(try WgQuickConfigParser.parse(awg3Conf))

        // Every AWG 3.x line reaches the engine unchanged.
        for line in awg3Conf.split(separator: "\n") where AwgParameters.awg3Keys.contains(where: { line.hasPrefix($0 + " =") }) {
            XCTAssertTrue(serialized.contains(line), "missing \(line)")
        }
        XCTAssertTrue(serialized.contains("PersistentKeepalive = 22-30"))

        let positions = AwgParameters.awg3Keys.compactMap { serialized.range(of: "\n\($0) = ")?.lowerBound }
        XCTAssertEqual(positions, positions.sorted())

        // A second pass is stable.
        XCTAssertEqual(WgQuickConfigParser.serialize(try WgQuickConfigParser.parse(serialized)), serialized)
    }

    func testParseKeepalive() {
        XCTAssertTrue(WgQuickConfigParser.parseKeepalive("25") == (25, nil))
        XCTAssertTrue(WgQuickConfigParser.parseKeepalive(" 22 - 30 ") == (nil, "22-30"))
        XCTAssertTrue(WgQuickConfigParser.parseKeepalive("30-22") == (nil, nil))
        XCTAssertTrue(WgQuickConfigParser.parseKeepalive("abc") == (nil, nil))
        XCTAssertTrue(WgQuickConfigParser.parseKeepalive(nil) == (nil, nil))
    }

    func testAwg2ConfHasNoAwg3Settings() throws {
        let serialized = WgQuickConfigParser.serialize(try WgQuickConfigParser.parse(awg3Conf
            .split(separator: "\n")
            .filter { line in !AwgParameters.awg3Keys.contains(where: { line.hasPrefix($0) }) }
            .joined(separator: "\n")))
        XCTAssertFalse(AwgParameters.awg3Keys.contains(where: { serialized.contains($0) }))
    }

    func testProfilesSavedBeforeAwg3StillDecode() throws {
        // Shape of a profile persisted by the previous release: no awg3, no persistentKeepaliveRange.
        let legacy = """
        {"id":"7B1E5C3A-6C2E-4F8E-9E4B-2C7D1F0A9B11","name":"Old","protocolType":"AmneziaWG",
         "endpointHost":"203.0.113.10","endpointPort":51820,"clientPrivateKey":"a","serverPublicKey":"b",
         "clientAddresses":["10.8.0.2/32"],"dnsServers":["1.1.1.1"],"allowedIps":["0.0.0.0/0"],
         "persistentKeepalive":25,"awgParameters":{"jc":4,"h1":"1"},"createdAt":0}
        """
        let profile = try JSONDecoder().decode(ServerProfile.self, from: Data(legacy.utf8))
        XCTAssertEqual(profile.persistentKeepalive, 25)
        XCTAssertNil(profile.persistentKeepaliveRange)
        XCTAssertNil(profile.awgParameters?.awg3)
    }
}
