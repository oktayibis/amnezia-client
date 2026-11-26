import Foundation
#if canImport(NetworkExtension)
import NetworkExtension
import os
import WireGuardKit

enum PacketTunnelProviderError: String, Error, LocalizedError {
    case savedProtocolConfigurationIsInvalid
    case dnsResolutionFailure
    case couldNotStartBackend
    case couldNotDetermineFileDescriptor
    case couldNotSetNetworkSettings
    case serverDidNotRespond

    /// Errors cross the XPC boundary to the app; an explicit NSLocalizedDescriptionKey
    /// keeps the message readable through `fetchLastDisconnectError`.
    var nsError: NSError {
        NSError(domain: "com.oktayibis.awgconnect.tunnel", code: 1,
                userInfo: [NSLocalizedDescriptionKey: errorDescription ?? rawValue])
    }

    var errorDescription: String? {
        switch self {
        case .serverDidNotRespond:
            return "The server did not respond. This profile may no longer be valid on the server, or another VPN may be active."
        case .savedProtocolConfigurationIsInvalid: return "The saved tunnel configuration is invalid."
        case .dnsResolutionFailure: return "Could not resolve the server address."
        case .couldNotStartBackend: return "The AmneziaWG engine failed to start."
        case .couldNotDetermineFileDescriptor: return "Could not find the tunnel interface."
        case .couldNotSetNetworkSettings: return "Could not apply tunnel network settings."
        }
    }
}

open class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = OSLog(subsystem: "com.oktayibis.awgconnect.tunnel", category: "tunnel")

    private lazy var adapter: WireGuardAdapter = {
        WireGuardAdapter(with: self) { [log] level, message in
            os_log("%{public}@", log: log, type: level == .error ? .error : .debug, message)
        }
    }()

    open override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        handshakeQueue.sync { isStopping = false }

        guard let conf = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,
              let configString = conf["config"] as? String else {
            completionHandler(PacketTunnelProviderError.savedProtocolConfigurationIsInvalid.nsError)
            return
        }

        let tunnelConfiguration: TunnelConfiguration
        do {
            tunnelConfiguration = try TunnelConfiguration(fromWgQuickConfig: configString,
                                                          called: conf["profileName"] as? String)
        } catch {
            os_log("Config parse failed: %{public}@", log: log, type: .error, String(describing: error))
            completionHandler(PacketTunnelProviderError.savedProtocolConfigurationIsInvalid.nsError)
            return
        }

        if let dnsOverride = conf["dnsOverride"] as? [String] {
            let servers = dnsOverride.compactMap { DNSServer(from: $0) }
            if !servers.isEmpty {
                tunnelConfiguration.interface.dns = servers
            }
        }

        adapter.start(tunnelConfiguration: tunnelConfiguration) { [log] adapterError in
            guard let adapterError else {
                os_log("Engine started on %{public}@, waiting for first handshake", log: log, type: .info,
                       self.adapter.interfaceName ?? "unknown")
                self.waitForFirstHandshake(completionHandler: completionHandler)
                return
            }

            os_log("Tunnel start failed: %{public}@", log: log, type: .error, String(describing: adapterError))
            switch adapterError {
            case .cannotLocateTunnelFileDescriptor:
                completionHandler(PacketTunnelProviderError.couldNotDetermineFileDescriptor.nsError)
            case .dnsResolution:
                completionHandler(PacketTunnelProviderError.dnsResolutionFailure.nsError)
            case .setNetworkSettings:
                completionHandler(PacketTunnelProviderError.couldNotSetNetworkSettings.nsError)
            case .startWireGuardBackend:
                completionHandler(PacketTunnelProviderError.couldNotStartBackend.nsError)
            case .invalidState:
                completionHandler(PacketTunnelProviderError.couldNotStartBackend.nsError)
            }
        }
    }

    // MARK: - First handshake gate

    /// How long to wait for the server's first handshake response before failing the start.
    /// WireGuard retries the initiation every 5 seconds, so this allows about four attempts.
    private static let handshakeTimeout: TimeInterval = 20
    private static let handshakePollInterval: TimeInterval = 0.25

    private let handshakeQueue = DispatchQueue(label: "com.oktayibis.awgconnect.tunnel.handshake")
    private var isStopping = false

    /// Reports the tunnel as connected only once the server has answered a handshake.
    /// Until then the system shows "Connecting", so a dead or revoked profile no longer
    /// looks connected while no traffic flows.
    private func waitForFirstHandshake(completionHandler: @escaping (Error?) -> Void) {
        let deadline = Date().addingTimeInterval(Self.handshakeTimeout)

        func poll() {
            if isStopping {
                completionHandler(PacketTunnelProviderError.serverDidNotRespond.nsError)
                return
            }
            adapter.getRuntimeConfiguration { [weak self] settings in
                guard let self else { return }
                self.handshakeQueue.async {
                    if let settings, Self.hasCompletedHandshake(settings) {
                        os_log("First handshake completed", log: self.log, type: .info)
                        completionHandler(nil)
                    } else if Date() >= deadline {
                        os_log("No handshake within %.0f s, giving up", log: self.log, type: .error, Self.handshakeTimeout)
                        self.adapter.stop { _ in
                            completionHandler(PacketTunnelProviderError.serverDidNotRespond.nsError)
                        }
                    } else {
                        self.handshakeQueue.asyncAfter(deadline: .now() + Self.handshakePollInterval) { poll() }
                    }
                }
            }
        }

        handshakeQueue.async { poll() }
    }

    /// The UAPI dump reports `last_handshake_time_sec=0` for a peer that never completed one.
    static func hasCompletedHandshake(_ uapi: String) -> Bool {
        uapi.split(separator: "\n").contains { line in
            guard line.hasPrefix("last_handshake_time_sec=") else { return false }
            return line.dropFirst("last_handshake_time_sec=".count) != "0"
        }
    }

    open override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        handshakeQueue.sync { isStopping = true }
        adapter.stop { [log] error in
            if let error {
                os_log("Adapter stop failed: %{public}@", log: log, type: .error, String(describing: error))
            }
            completionHandler()

            #if os(macOS)
            // Same workaround as upstream WireGuard (Apple bug 32073323): the macOS
            // extension process is not torn down reliably, so exit after stopping.
            exit(0)
            #endif
        }
    }

    /// A single zero byte requests the runtime UAPI configuration (rx/tx bytes, last handshake).
    open override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let completionHandler else { return }
        guard messageData.count == 1, messageData[0] == 0 else {
            completionHandler(nil)
            return
        }
        adapter.getRuntimeConfiguration { settings in
            completionHandler(settings?.data(using: .utf8))
        }
    }
}
#endif
