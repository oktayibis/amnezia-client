import Foundation

/// Runtime counters read from the AmneziaWG engine's UAPI dump (`wgGetConfig`),
/// which the tunnel extension returns for a single zero-byte app message.
public struct UapiStatistics: Equatable, Sendable {
    /// Total bytes received from all peers.
    public var rxBytes: UInt64
    /// Total bytes sent to all peers.
    public var txBytes: UInt64
    /// Most recent completed handshake across all peers, if any.
    public var lastHandshake: Date?

    public init(rxBytes: UInt64 = 0, txBytes: UInt64 = 0, lastHandshake: Date? = nil) {
        self.rxBytes = rxBytes
        self.txBytes = txBytes
        self.lastHandshake = lastHandshake
    }

    /// Parses `key=value` UAPI lines. Counters are summed over every peer; a
    /// `last_handshake_time_sec` of 0 means the peer never completed a handshake.
    public static func parse(_ uapi: String) -> UapiStatistics {
        var stats = UapiStatistics()
        var handshakeSec: Int64 = 0
        var latest: TimeInterval = 0

        func commitHandshake(nsec: Int64) {
            guard handshakeSec > 0 else { return }
            let time = TimeInterval(handshakeSec) + TimeInterval(nsec) / 1_000_000_000
            latest = max(latest, time)
            handshakeSec = 0
        }

        for line in uapi.split(whereSeparator: \.isNewline) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq]
            let value = line[line.index(after: eq)...]
            switch key {
            case "public_key":
                commitHandshake(nsec: 0)
            case "rx_bytes":
                stats.rxBytes &+= UInt64(value) ?? 0
            case "tx_bytes":
                stats.txBytes &+= UInt64(value) ?? 0
            case "last_handshake_time_sec":
                commitHandshake(nsec: 0)
                handshakeSec = Int64(value) ?? 0
            case "last_handshake_time_nsec":
                commitHandshake(nsec: Int64(value) ?? 0)
            default:
                break
            }
        }
        commitHandshake(nsec: 0)
        if latest > 0 {
            stats.lastHandshake = Date(timeIntervalSince1970: latest)
        }
        return stats
    }

    /// Bytes per second between two samples; counter resets (engine restart) give 0.
    public static func rate(from old: UInt64, to new: UInt64, over seconds: TimeInterval) -> Double {
        guard seconds > 0, new >= old else { return 0 }
        return Double(new - old) / seconds
    }
}
