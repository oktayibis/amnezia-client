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

    private var statsTimer: DispatchSourceTimer?
    private var lastSampleDate: Date?
    private var lastLatencyProbeAt: Date?
    private var latencyProbeInFlight = false
    private var activeProfileDns: [String] = []

    public var onStateChange: ((ConnectionState) -> Void)?
    public var onStatsChange: ((ConnectionStatistics) -> Void)?

    public init(tunnelBundleId: String? = nil) {
        let defaultId = Bundle.main.bundleIdentifier.map { $0 + ".tunnel" } ?? "com.oktayibis.awgconnect.tunnel"
        self.tunnelBundleId = tunnelBundleId ?? defaultId
        setupStatusObserver()
        syncInitialStatus()
    }

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
        var mgr = try await getOrCreateManager()
        try await configureAndSaveManager(mgr, with: profile, options: options)
        // Reload from preferences so NEVPNManager's underlying configuration is fresh on iOS.
        mgr = try await reloadManager(fallback: mgr)

        guard let session = mgr.connection as? NETunnelProviderSession else {
            throw NSError(domain: "AmneziaTunnel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid tunnel provider session"])
        }

        lock.withLock {
            self.userRequestedStop = false
            self.startInFlight = true
            self.activeProfileDns = options.dnsOverride ?? profile.dnsServers
        }
        do {
            try session.startVPNTunnel(options: nil)
        } catch let error as NSError where Self.isConfigurationStaleError(error) {
            // If iOS still reports NEVPNErrorConfigurationStale (e.g. after system VPN settings changed
            // or initial permission dialog), force a fresh load + save + reload cycle and retry once.
            self.manager = nil
            mgr = try await getOrCreateManager()
            try await configureAndSaveManager(mgr, with: profile, options: options)
            mgr = try await reloadManager(fallback: mgr)
            guard let refreshedSession = mgr.connection as? NETunnelProviderSession else {
                lock.withLock { self.startInFlight = false }
                throw NSError(domain: "AmneziaTunnel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid tunnel provider session"])
            }
            do {
                try refreshedSession.startVPNTunnel(options: nil)
            } catch {
                lock.withLock { self.startInFlight = false }
                throw error
            }
        } catch {
            lock.withLock { self.startInFlight = false }
            throw error
        }

        lock.withLock {
            self._state = .connecting
        }
        onStateChange?(.connecting)
    }

    private func configureAndSaveManager(
        _ mgr: NETunnelProviderManager,
        with profile: ServerProfile,
        options: TunnelOptions
    ) async throws {
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
    }

    static func isConfigurationStaleError(_ error: NSError) -> Bool {
        if error.domain == NEVPNErrorDomain && error.code == NEVPNError.configurationStale.rawValue {
            return true
        }
        return error.localizedDescription.localizedCaseInsensitiveContains("configuration is stale")
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
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let matching = managers.filter {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == tunnelBundleId
        }
        if let found = matching.first {
            // Clean up any duplicate managers that could cause stale preference conflicts on iOS
            if matching.count > 1 {
                for duplicate in matching.dropFirst() {
                    try? await duplicate.removeFromPreferences()
                }
            }
            try await found.loadFromPreferences()
            self.manager = found
            return found
        }

        if let existing = manager {
            try await existing.loadFromPreferences()
            return existing
        }

        let newManager = NETunnelProviderManager()
        self.manager = newManager
        return newManager
    }

    private func reloadManager(fallback: NETunnelProviderManager) async throws -> NETunnelProviderManager {
        try await fallback.loadFromPreferences()
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let found = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == tunnelBundleId
        }) {
            try await found.loadFromPreferences()
            self.manager = found
            return found
        }
        self.manager = fallback
        return fallback
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
            let wasConnected = self._state == .connected
            self._state = newState
            if newState == .connected {
                if !wasConnected || self._stats.connectedSince == nil {
                    self._stats.connectedSince = connection.connectedDate ?? Date()
                }
            } else if newState == .disconnected {
                self._stats = ConnectionStatistics()
            }
            statsToReport = self._stats
        }

        if newState == .connected {
            startStatsPolling()
        } else {
            stopStatsPolling()
        }

        onStateChange?(newState)
        onStatsChange?(statsToReport)
    }

    private func syncInitialStatus() {
        Task { [weak self] in
            guard let self else { return }
            guard let managers = try? await NETunnelProviderManager.loadAllFromPreferences(),
                  let found = managers.first(where: {
                      ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.tunnelBundleId
                  }) else { return }
            self.manager = found
            await MainActor.run {
                self.handleStatusUpdate(found.connection.status, connection: found.connection)
            }
        }
    }

    // MARK: - Live UAPI & Latency Polling

    /// Polls the PacketTunnelProvider extension every second via `sendProviderMessage(Data([0]))`
    /// for UAPI rx/tx counters and handshake timestamps, and periodically probes latency.
    private func startStatsPolling() {
        stopStatsPolling()
        lock.withLock {
            self.lastSampleDate = nil
            self.lastLatencyProbeAt = nil
            self.latencyProbeInFlight = false
        }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.pollTunnelStatistics()
        }
        lock.withLock {
            self.statsTimer = timer
        }
        timer.resume()
    }

    private func stopStatsPolling() {
        let timer: DispatchSourceTimer? = lock.withLock {
            let t = self.statsTimer
            self.statsTimer = nil
            self.lastSampleDate = nil
            self.lastLatencyProbeAt = nil
            self.latencyProbeInFlight = false
            return t
        }
        timer?.cancel()
    }

    private func pollTunnelStatistics() {
        let session: NETunnelProviderSession? = lock.withLock {
            guard self._state == .connected else { return nil }
            return self.manager?.connection as? NETunnelProviderSession
        }
        guard let session else { return }

        let now = Date()
        let shouldProbeLatency: Bool = lock.withLock {
            guard !self.latencyProbeInFlight else { return false }
            if let lastProbe = self.lastLatencyProbeAt, now.timeIntervalSince(lastProbe) < 5.0 {
                return false
            }
            self.latencyProbeInFlight = true
            self.lastLatencyProbeAt = now
            return true
        }

        if shouldProbeLatency {
            let dnsServers = lock.withLock { self.activeProfileDns }
            var targets = [LatencyProbe.Target]()
            if let primaryDns = dnsServers.first, !primaryDns.isEmpty {
                targets.append(LatencyProbe.Target(host: primaryDns, port: 53))
                targets.append(LatencyProbe.Target(host: primaryDns, port: 443))
            }
            targets.append(contentsOf: LatencyProbe.defaultTargets)

            Task { [weak self] in
                let ms = await LatencyProbe.measure(targets: targets)
                guard let self else { return }
                var updated: ConnectionStatistics?
                self.lock.withLock {
                    self.latencyProbeInFlight = false
                    guard self._state == .connected else { return }
                    if let ms {
                        self._stats.latencyMs = ms
                        updated = self._stats
                    }
                }
                if let updated {
                    DispatchQueue.main.async {
                        self.onStatsChange?(updated)
                    }
                }
            }
        }

        do {
            try session.sendProviderMessage(Data([0])) { [weak self] responseData in
                guard let self else { return }
                let sampleTime = Date()
                var updated: ConnectionStatistics?

                self.lock.withLock {
                    guard self._state == .connected else { return }
                    if self._stats.connectedSince == nil {
                        self._stats.connectedSince = session.connectedDate ?? sampleTime
                    }
                    if let responseData,
                       let uapiString = String(data: responseData, encoding: .utf8) {
                        let uapi = UapiStatistics.parse(uapiString)
                        if let prevDate = self.lastSampleDate {
                            let dt = sampleTime.timeIntervalSince(prevDate)
                            self._stats.currentDownSpeed = UapiStatistics.rate(
                                from: self._stats.bytesIn,
                                to: uapi.rxBytes,
                                over: dt
                            )
                            self._stats.currentUpSpeed = UapiStatistics.rate(
                                from: self._stats.bytesOut,
                                to: uapi.txBytes,
                                over: dt
                            )
                        }
                        self._stats.bytesIn = uapi.rxBytes
                        self._stats.bytesOut = uapi.txBytes
                        if let hs = uapi.lastHandshake {
                            self._stats.lastHandshake = hs
                        }
                        self.lastSampleDate = sampleTime
                    }
                    updated = self._stats
                }

                if let updated {
                    DispatchQueue.main.async {
                        self.onStatsChange?(updated)
                    }
                }
            }
        } catch {
            // Even if provider message fails transiently, still tick duration for UI
            var updated: ConnectionStatistics?
            lock.withLock {
                if _state == .connected {
                    updated = _stats
                }
            }
            if let updated {
                DispatchQueue.main.async {
                    self.onStatsChange?(updated)
                }
            }
        }
    }

    deinit {
        stopStatsPolling()
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
#endif
