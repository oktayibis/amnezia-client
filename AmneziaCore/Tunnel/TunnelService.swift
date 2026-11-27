import Foundation
import Combine

public struct TunnelOptions: Sendable {
    public var killSwitch: Bool
    public var dnsOverride: [String]?

    public init(killSwitch: Bool = false, dnsOverride: [String]? = nil) {
        self.killSwitch = killSwitch
        self.dnsOverride = dnsOverride
    }
}

public protocol TunnelService: AnyObject, Sendable {
    var currentState: ConnectionState { get }
    var currentStats: ConnectionStatistics { get }
    var providesTrafficStats: Bool { get }
    
    func startTunnel(with profile: ServerProfile, options: TunnelOptions) async throws
    func stopTunnel() async throws
    func reconnect() async throws
}

public extension TunnelService {
    func startTunnel(with profile: ServerProfile) async throws {
        try await startTunnel(with: profile, options: TunnelOptions())
    }
}

/// Mock tunnel implementation for testing in Simulator and SwiftUI previews
public final class MockTunnelService: TunnelService, @unchecked Sendable {
    public static let shared = MockTunnelService()

    private var _state: ConnectionState = .disconnected
    private var _stats: ConnectionStatistics = ConnectionStatistics()
    private var statsTimer: Timer?
    private var currentProfile: ServerProfile?
    private let lock = NSLock()

    public var onStateChange: ((ConnectionState) -> Void)?
    public var onStatsChange: ((ConnectionStatistics) -> Void)?

    public init() {}

    public var currentState: ConnectionState {
        lock.withLock { _state }
    }

    public var currentStats: ConnectionStatistics {
        lock.withLock { _stats }
    }

    public var providesTrafficStats: Bool {
        true
    }

    public func startTunnel(with profile: ServerProfile, options: TunnelOptions) async throws {
        lock.withLock {
            self.currentProfile = profile
            self._state = .connecting
        }
        onStateChange?(.connecting)

        // Simulate network handshake delay
        try await Task.sleep(nanoseconds: 800_000_000)

        let initialStats = ConnectionStatistics(
            bytesIn: 1024,
            bytesOut: 512,
            currentDownSpeed: 250_000,
            currentUpSpeed: 80_000,
            connectedSince: Date(),
            latencyMs: profile.pingMs ?? Int.random(in: 18...45),
            lastHandshake: Date()
        )

        lock.withLock {
            self._state = .connected
            self._stats = initialStats
        }
        
        onStateChange?(.connected)
        onStatsChange?(initialStats)

        await MainActor.run {
            self.startStatsSimulation()
        }
    }

    public func stopTunnel() async throws {
        lock.withLock {
            self._state = .disconnecting
        }
        onStateChange?(.disconnecting)

        await MainActor.run {
            self.statsTimer?.invalidate()
            self.statsTimer = nil
        }

        try await Task.sleep(nanoseconds: 400_000_000)

        lock.withLock {
            self._state = .disconnected
            self._stats = ConnectionStatistics()
        }
        
        onStateChange?(.disconnected)
        onStatsChange?(ConnectionStatistics())
    }

    public func reconnect() async throws {
        guard let p = currentProfile else { return }
        try await stopTunnel()
        try await startTunnel(with: p)
    }

    private func startStatsSimulation() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            var updatedStats: ConnectionStatistics?

            self.lock.withLock {
                guard self._state == .connected else { return }

                let downDelta = UInt64.random(in: 120_000...2_400_000)
                let upDelta = UInt64.random(in: 25_000...450_000)
                self._stats.bytesIn += downDelta
                self._stats.bytesOut += upDelta
                self._stats.currentDownSpeed = Double(downDelta)
                self._stats.currentUpSpeed = Double(upDelta)
                updatedStats = self._stats
            }

            if let stats = updatedStats {
                self.onStatsChange?(stats)
            }
        }
    }
}
