import Foundation
#if canImport(NetworkExtension)
import NetworkExtension

public final class NetworkExtensionTunnelService: TunnelService, @unchecked Sendable {
    public static let shared = NetworkExtensionTunnelService()

    private let tunnelBundleId: String
    private var manager: NETunnelProviderManager?
    private var statusObserver: Any?
    private let lock = NSLock()

    private var _state: ConnectionState = .disconnected
    /// Set by `stopTunnel()` so a user-initiated disconnect is not reported as a failure.
    private var userRequestedStop = false
    /// True from `startTunnel` until the tunnel connects or the attempt ends.
    private var startInFlight = false
    private var _stats: ConnectionStatistics = ConnectionStatistics()

    public var onStateChange: ((ConnectionState) -> Void)?
    public var onStatsChange: ((ConnectionStatistics) -> Void)?

    public init(tunnelBundleId: String? = nil) {
        let defaultId = Bundle.main.bundleIdentifier.map { $0 + ".tunnel" } ?? "com.oktayibis.awgconnect.tunnel"
        self.tunnelBundleId = tunnelBundleId ?? defaultId
        setupStatusObserver()
    }

    public var currentState: ConnectionState {
        lock.withLock { _state }
    }

    public var currentStats: ConnectionStatistics {
        lock.withLock { _stats }
    }

    public var providesTrafficStats: Bool {
        false
    }

    public func startTunnel(with profile: ServerProfile, options: TunnelOptions) async throws {
        let mgr = try await getOrCreateManager()
        
        let protocolConfiguration = NETunnelProviderProtocol()
        protocolConfiguration.providerBundleIdentifier = tunnelBundleId
        protocolConfiguration.serverAddress = profile.endpointString
        
        // Pass the serialized wg/awg config to providerConfiguration
        let serializedConfig = WgQuickConfigParser.serialize(profile)
        var providerConfig: [String: Any] = [
            "config": serializedConfig,
            "profileId": profile.id.uuidString,
            "profileName": profile.name,
            "protocolType": profile.protocolType.rawValue
        ]

        if options.killSwitch {
            providerConfig["killSwitch"] = true
            protocolConfiguration.includeAllNetworks = true
        }

        if let dns = options.dnsOverride, !dns.isEmpty {
            providerConfig["dnsOverride"] = dns
        }

        protocolConfiguration.providerConfiguration = providerConfig

        mgr.protocolConfiguration = protocolConfiguration
        mgr.localizedDescription = "AWG Connect: \(profile.name)"
        mgr.isEnabled = true

        try await mgr.saveToPreferences()
        try await mgr.loadFromPreferences()

        guard let session = mgr.connection as? NETunnelProviderSession else {
            throw NSError(domain: "AmneziaTunnel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid tunnel provider session"])
        }

        lock.withLock {
            self.userRequestedStop = false
            self.startInFlight = true
        }
        try session.startVPNTunnel(options: nil)

        lock.withLock {
            self._state = .connecting
        }
        onStateChange?(.connecting)
    }

    public func startTunnel(with profile: ServerProfile) async throws {
        try await startTunnel(with: profile, options: TunnelOptions())
    }

    public func stopTunnel() async throws {
        let mgr = try await getOrCreateManager()
        guard let session = mgr.connection as? NETunnelProviderSession else { return }
        lock.withLock { self.userRequestedStop = true }
        session.stopVPNTunnel()

        lock.withLock {
            self._state = .disconnecting
        }
        onStateChange?(.disconnecting)
    }

    public func reconnect() async throws {
        try await stopTunnel()
        // Wait briefly for tunnel shutdown
        try await Task.sleep(nanoseconds: 500_000_000)
        if let profile = ProfileStorage.shared.selectedProfile() {
            try await startTunnel(with: profile)
        }
    }

    // MARK: - Manager Setup

    private func getOrCreateManager() async throws -> NETunnelProviderManager {
        if let existing = manager {
            return existing
        }

        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let found = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == tunnelBundleId
        }) {
            self.manager = found
            return found
        }

        let newManager = NETunnelProviderManager()
        self.manager = newManager
        return newManager
    }

    private func setupStatusObserver() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let connection = notification.object as? NEVPNConnection else { return }
            self.handleStatusUpdate(connection.status, connection: connection)
        }
    }

    private func handleStatusUpdate(_ status: NEVPNStatus, connection: NEVPNConnection) {
        // A drop to .disconnected while we were still connecting, without the user asking,
        // means the start failed (e.g. no handshake). Surface the extension's reason.
        let failedStart: Bool = lock.withLock {
            if status == .connected { startInFlight = false }
            guard status == .disconnected || status == .invalid, startInFlight else { return false }
            startInFlight = false
            return !userRequestedStop
        }
        if failedStart {
            connection.fetchLastDisconnectError { [weak self] error in
                guard let self else { return }
                let message = error?.localizedDescription ?? "The connection could not be established."
                let failed = ConnectionState.error(message)
                self.lock.withLock {
                    self._state = failed
                    self._stats = ConnectionStatistics()
                }
                DispatchQueue.main.async {
                    self.onStateChange?(failed)
                    self.onStatsChange?(ConnectionStatistics())
                }
            }
            return
        }

        let newState: ConnectionState
        switch status {
        case .invalid, .disconnected:
            newState = .disconnected
        case .connecting:
            newState = .connecting
        case .connected:
            newState = .connected
        case .reasserting:
            newState = .reconnecting
        case .disconnecting:
            newState = .disconnecting
        @unknown default:
            newState = .disconnected
        }

        var statsToReport = ConnectionStatistics()
        lock.withLock {
            self._state = newState
            if newState == .connected {
                self._stats.connectedSince = Date()
            } else if newState == .disconnected {
                self._stats = ConnectionStatistics()
            }
            statsToReport = self._stats
        }

        onStateChange?(newState)
        onStatsChange?(statsToReport)
    }

    deinit {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
#endif
