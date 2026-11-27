import Foundation

/// Results from the built-in Speedtest & Network Diagnostics suite.
public struct SpeedtestResult: Equatable, Sendable {
    public var downloadMbps: Double
    public var uploadMbps: Double
    public var pingMs: Int
    public var jitterMs: Int
    public var timestamp: Date

    public init(
        downloadMbps: Double = 0,
        uploadMbps: Double = 0,
        pingMs: Int = 0,
        jitterMs: Int = 0,
        timestamp: Date = Date()
    ) {
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.pingMs = pingMs
        self.jitterMs = jitterMs
        self.timestamp = timestamp
    }

    public var formattedDownloadMbps: String {
        String(format: "%.1f Mbps", downloadMbps)
    }

    public var formattedUploadMbps: String {
        String(format: "%.1f Mbps", uploadMbps)
    }
}

/// Public IP, location, and DNS latency diagnostic report.
public struct NetworkIdentityReport: Equatable, Sendable {
    public var publicIp: String
    public var countryCode: String
    public var colo: String
    public var tlsVersion: String
    public var dnsLatencyMs: Int?
    public var checkedAt: Date

    public init(
        publicIp: String,
        countryCode: String = "",
        colo: String = "",
        tlsVersion: String = "",
        dnsLatencyMs: Int? = nil,
        checkedAt: Date = Date()
    ) {
        self.publicIp = publicIp
        self.countryCode = countryCode
        self.colo = colo
        self.tlsVersion = tlsVersion
        self.dnsLatencyMs = dnsLatencyMs
        self.checkedAt = checkedAt
    }

    /// Parses key=value lines from `https://1.1.1.1/cdn-cgi/trace`.
    public static func parseCloudflareTrace(_ text: String, dnsLatencyMs: Int? = nil) -> NetworkIdentityReport? {
        var fields = [String: String]()
        for line in text.split(whereSeparator: \.isNewline) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        guard let ip = fields["ip"], !ip.isEmpty else { return nil }
        return NetworkIdentityReport(
            publicIp: ip,
            countryCode: fields["loc"] ?? "",
            colo: fields["colo"] ?? "",
            tlsVersion: fields["tls"] ?? "",
            dnsLatencyMs: dnsLatencyMs
        )
    }
}

/// Multi-sample ping & jitter result.
public struct PingJitterReport: Equatable, Sendable {
    public var samplesMs: [Int]
    public var minMs: Int
    public var avgMs: Int
    public var maxMs: Int
    public var jitterMs: Int
    public var packetLossPercent: Int

    public init(
        samplesMs: [Int],
        minMs: Int,
        avgMs: Int,
        maxMs: Int,
        jitterMs: Int,
        packetLossPercent: Int
    ) {
        self.samplesMs = samplesMs
        self.minMs = minMs
        self.avgMs = avgMs
        self.maxMs = maxMs
        self.jitterMs = jitterMs
        self.packetLossPercent = packetLossPercent
    }

    /// Computes min, average, max, mean consecutive difference (jitter), and loss % from raw samples.
    public static func summarize(samples: [Int?]) -> PingJitterReport {
        let valid = samples.compactMap { $0 }
        guard !valid.isEmpty else {
            return PingJitterReport(samplesMs: [], minMs: 0, avgMs: 0, maxMs: 0, jitterMs: 0, packetLossPercent: 100)
        }
        let minVal = valid.min() ?? 0
        let maxVal = valid.max() ?? 0
        let avgVal = valid.reduce(0, +) / valid.count

        let jitterVal: Int
        if valid.count >= 2 {
            var diffs = 0
            for i in 1..<valid.count {
                diffs += abs(valid[i] - valid[i - 1])
            }
            jitterVal = diffs / (valid.count - 1)
        } else {
            jitterVal = 0
        }

        let totalCount = max(1, samples.count)
        let lostCount = totalCount - valid.count
        let lossPct = (lostCount * 100) / totalCount

        return PingJitterReport(
            samplesMs: valid,
            minMs: minVal,
            avgMs: avgVal,
            maxMs: maxVal,
            jitterMs: jitterVal,
            packetLossPercent: lossPct
        )
    }
}

public enum SpeedtestPhase: String, Equatable, Sendable {
    case idle = "Ready"
    case ping = "Measuring Ping & Jitter..."
    case download = "Testing Download Speed..."
    case upload = "Testing Upload Speed..."
    case completed = "Complete"
    case failed = "Failed"
}

public enum NetworkDiagnosticsService {

    private static var ephemeralSession: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }

    /// Runs a multi-sample TCP ping & jitter check against the target or default anycast resolvers.
    public static func runPingSeries(
        dnsServer: String? = nil,
        count: Int = 5
    ) async -> PingJitterReport {
        var targets = [LatencyProbe.Target]()
        if let dns = dnsServer, !dns.isEmpty {
            targets.append(LatencyProbe.Target(host: dns, port: 53))
            targets.append(LatencyProbe.Target(host: dns, port: 443))
        }
        targets.append(contentsOf: LatencyProbe.defaultTargets)

        var rawSamples = [Int?]()
        for i in 0..<max(1, count) {
            let ms = await LatencyProbe.measure(targets: targets, timeout: 2.0)
            rawSamples.append(ms)
            if i + 1 < count {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
        return PingJitterReport.summarize(samples: rawSamples)
    }

    /// Fetches public exit IP, country code, Cloudflare PoP colo, and DNS latency.
    public static func fetchNetworkIdentity(dnsServer: String? = nil) async -> NetworkIdentityReport? {
        let dnsHost = (dnsServer?.isEmpty == false) ? dnsServer! : "1.1.1.1"
        async let dnsPing = LatencyProbe.measure(
            targets: [
                LatencyProbe.Target(host: dnsHost, port: 53),
                LatencyProbe.Target(host: dnsHost, port: 443)
            ],
            timeout: 2.5
        )

        let traceUrls = [
            "https://1.1.1.1/cdn-cgi/trace",
            "https://1.0.0.1/cdn-cgi/trace",
            "https://cloudflare.com/cdn-cgi/trace"
        ]

        let session = ephemeralSession
        for urlString in traceUrls {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let text = String(data: data, encoding: .utf8) else { continue }
                let dnsMs = await dnsPing
                if let report = NetworkIdentityReport.parseCloudflareTrace(text, dnsLatencyMs: dnsMs) {
                    return report
                }
            } catch {
                continue
            }
        }
        return nil
    }

    /// Runs a quick 3-stage Speedtest (Ping/Jitter -> Download Mbps -> Upload Mbps) routed through the active interface/tunnel.
    public static func runSpeedtest(
        dnsServer: String? = nil,
        downloadBytes: Int = 5_000_000,
        uploadBytes: Int = 2_000_000,
        onPhase: (@Sendable (SpeedtestPhase) -> Void)? = nil
    ) async throws -> SpeedtestResult {
        onPhase?(.ping)
        let pingReport = await runPingSeries(dnsServer: dnsServer, count: 4)

        onPhase?(.download)
        let downMbps = try await measureDownloadMbps(bytes: downloadBytes)

        onPhase?(.upload)
        let upMbps = await measureUploadMbps(bytes: uploadBytes)

        onPhase?(.completed)
        return SpeedtestResult(
            downloadMbps: downMbps,
            uploadMbps: upMbps,
            pingMs: pingReport.avgMs,
            jitterMs: pingReport.jitterMs
        )
    }

    public static func measureDownloadMbps(bytes: Int = 5_000_000) async throws -> Double {
        let session = ephemeralSession
        let urls = [
            "https://speed.cloudflare.com/__down?bytes=\(bytes)",
            "https://speed.hetzner.de/10MB.bin"
        ]

        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let start = DispatchTime.now()
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      data.count > 64_000 else { continue }
                let elapsedSec = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
                guard elapsedSec > 0.01 else { continue }
                let bits = Double(data.count) * 8.0
                return (bits / elapsedSec) / 1_000_000.0
            } catch {
                continue
            }
        }
        throw NSError(
            domain: "NetworkDiagnostics",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not reach speedtest server. Check your internet or tunnel connection."]
        )
    }

    public static func measureUploadMbps(bytes: Int = 2_000_000) async -> Double {
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else { return 0 }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let payload = Data(repeating: 0x41, count: bytes)

        let session = ephemeralSession
        let start = DispatchTime.now()
        do {
            let (_, response) = try await session.upload(for: request, from: payload)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return 0 }
            let elapsedSec = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
            guard elapsedSec > 0.01 else { return 0 }
            let bits = Double(payload.count) * 8.0
            return (bits / elapsedSec) / 1_000_000.0
        } catch {
            return 0
        }
    }
}
