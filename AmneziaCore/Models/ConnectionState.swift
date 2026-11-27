import Foundation

/// State of the VPN Tunnel
public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case reconnecting
    case error(String)

    public var isConnected: Bool {
        self == .connected
    }

    public var isConnecting: Bool {
        self == .connecting || self == .reconnecting
    }

    public var isBusy: Bool {
        self == .connecting || self == .disconnecting || self == .reconnecting
    }

    public var displayTitle: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting..."
        case .reconnecting: return "Reconnecting..."
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

/// Real-time connection traffic and metrics
public struct ConnectionStatistics: Equatable, Sendable {
    public var bytesIn: UInt64
    public var bytesOut: UInt64
    public var currentDownSpeed: Double // bytes per second
    public var currentUpSpeed: Double   // bytes per second
    public var connectedSince: Date?
    public var latencyMs: Int?
    /// Most recent completed WireGuard handshake reported by the engine.
    public var lastHandshake: Date?

    public init(
        bytesIn: UInt64 = 0,
        bytesOut: UInt64 = 0,
        currentDownSpeed: Double = 0,
        currentUpSpeed: Double = 0,
        connectedSince: Date? = nil,
        latencyMs: Int? = nil,
        lastHandshake: Date? = nil
    ) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.currentDownSpeed = currentDownSpeed
        self.currentUpSpeed = currentUpSpeed
        self.connectedSince = connectedSince
        self.latencyMs = latencyMs
        self.lastHandshake = lastHandshake
    }

    /// "--" until measured, otherwise e.g. "42 ms".
    public var formattedLatency: String {
        latencyMs.map { "\($0) ms" } ?? "--"
    }

    /// Age of the last handshake, e.g. "12s ago" / "2m ago", or "--".
    public func formattedHandshakeAge(now: Date = Date()) -> String {
        guard let lastHandshake else { return "--" }
        let age = max(0, Int(now.timeIntervalSince(lastHandshake)))
        if age < 60 { return "\(age)s ago" }
        if age < 3600 { return "\(age / 60)m ago" }
        return "\(age / 3600)h ago"
    }

    public var duration: TimeInterval {
        guard let connectedSince else { return 0 }
        return max(0, Date().timeIntervalSince(connectedSince))
    }

    public var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    public var formattedDownSpeed: String {
        formatByteSpeed(currentDownSpeed)
    }

    public var formattedUpSpeed: String {
        formatByteSpeed(currentUpSpeed)
    }

    public var formattedBytesIn: String {
        formatBytes(bytesIn)
    }

    public var formattedBytesOut: String {
        formatBytes(bytesOut)
    }

    private func formatByteSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576.0)
        } else if bytesPerSec >= 1024 {
            return String(format: "%.0f KB/s", bytesPerSec / 1024.0)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
