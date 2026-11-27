import XCTest
@testable import AmneziaCore

final class UapiStatisticsTests: XCTestCase {

    func testParseUapiSinglePeerWithHandshake() throws {
        let uapi = """
        private_key=0000000000000000000000000000000000000000000000000000000000000000
        jc=5
        jmin=10
        jmax=50
        s1=12
        s2=12
        s3=12
        s4=12
        h1=1
        h2=2
        h3=3
        h4=4
        public_key=1111111111111111111111111111111111111111111111111111111111111111
        preshared_key=2222222222222222222222222222222222222222222222222222222222222222
        endpoint=94.138.209.154:49691
        tx_bytes=204800
        rx_bytes=1048576
        last_handshake_time_sec=1700000000
        last_handshake_time_nsec=500000000
        allowed_ip=0.0.0.0/0
        allowed_ip=::/0
        persistent_keepalive_interval=25-35
        """

        let stats = UapiStatistics.parse(uapi)
        XCTAssertEqual(stats.rxBytes, 1_048_576)
        XCTAssertEqual(stats.txBytes, 204_800)
        let handshake = try XCTUnwrap(stats.lastHandshake)
        XCTAssertEqual(handshake.timeIntervalSince1970, 1_700_000_000.5, accuracy: 0.001)
    }

    func testParseUapiZeroHandshakeIsNil() {
        let uapi = """
        public_key=1111111111111111111111111111111111111111111111111111111111111111
        tx_bytes=148
        rx_bytes=0
        last_handshake_time_sec=0
        last_handshake_time_nsec=0
        """

        let stats = UapiStatistics.parse(uapi)
        XCTAssertEqual(stats.rxBytes, 0)
        XCTAssertEqual(stats.txBytes, 148)
        XCTAssertNil(stats.lastHandshake)
    }

    func testRateCalculationAndCounterReset() {
        XCTAssertEqual(UapiStatistics.rate(from: 1000, to: 3000, over: 2.0), 1000.0, accuracy: 0.01)
        // Counter reset returns 0 instead of underflowing
        XCTAssertEqual(UapiStatistics.rate(from: 5000, to: 1000, over: 1.0), 0.0)
        XCTAssertEqual(UapiStatistics.rate(from: 1000, to: 2000, over: 0.0), 0.0)
    }

    func testConnectionStatisticsFormatting() {
        let now = Date()
        let stats = ConnectionStatistics(
            bytesIn: 2_097_152,
            bytesOut: 524_288,
            currentDownSpeed: 1_572_864,
            currentUpSpeed: 256_000,
            connectedSince: now.addingTimeInterval(-75),
            latencyMs: 38,
            lastHandshake: now.addingTimeInterval(-12)
        )
        XCTAssertEqual(stats.formattedLatency, "38 ms")
        XCTAssertEqual(stats.formattedHandshakeAge(now: now), "12s ago")
        XCTAssertEqual(stats.formattedDownSpeed, "1.5 MB/s")
        XCTAssertEqual(stats.formattedUpSpeed, "250 KB/s")
    }

    func testPingJitterReportSummarize() {
        let report = PingJitterReport.summarize(samples: [30, 40, nil, 50, 36])
        XCTAssertEqual(report.samplesMs, [30, 40, 50, 36])
        XCTAssertEqual(report.minMs, 30)
        XCTAssertEqual(report.maxMs, 50)
        XCTAssertEqual(report.avgMs, 39)
        // Consecutive diffs: |40-30|=10, |50-40|=10, |36-50|=14 -> (10+10+14)/3 = 11
        XCTAssertEqual(report.jitterMs, 11)
        XCTAssertEqual(report.packetLossPercent, 20)
    }

    func testParseCloudflareTrace() throws {
        let trace = """
        fl=29f102
        h=1.1.1.1
        ip=94.138.209.154
        ts=1700000000.123
        visit_scheme=https
        uag=AWGConnect
        colo=FRA
        sliver=none
        http=http/2
        loc=DE
        tls=TLSv1.3
        sni=off
        warp=off
        """
        let identity = try XCTUnwrap(NetworkIdentityReport.parseCloudflareTrace(trace, dnsLatencyMs: 28))
        XCTAssertEqual(identity.publicIp, "94.138.209.154")
        XCTAssertEqual(identity.countryCode, "DE")
        XCTAssertEqual(identity.colo, "FRA")
        XCTAssertEqual(identity.tlsVersion, "TLSv1.3")
        XCTAssertEqual(identity.dnsLatencyMs, 28)
    }
}
