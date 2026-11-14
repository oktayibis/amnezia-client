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

    var errorDescription: String? {
        switch self {
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
        guard let conf = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,
              let configString = conf["config"] as? String else {
            completionHandler(PacketTunnelProviderError.savedProtocolConfigurationIsInvalid)
            return
        }

        let tunnelConfiguration: TunnelConfiguration
        do {
            tunnelConfiguration = try TunnelConfiguration(fromWgQuickConfig: configString,
                                                          called: conf["profileName"] as? String)
        } catch {
            os_log("Config parse failed: %{public}@", log: log, type: .error, String(describing: error))
            completionHandler(PacketTunnelProviderError.savedProtocolConfigurationIsInvalid)
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
                os_log("Tunnel started on %{public}@", log: log, type: .info, self.adapter.interfaceName ?? "unknown")
                completionHandler(nil)
                return
            }

            os_log("Tunnel start failed: %{public}@", log: log, type: .error, String(describing: adapterError))
            switch adapterError {
            case .cannotLocateTunnelFileDescriptor:
                completionHandler(PacketTunnelProviderError.couldNotDetermineFileDescriptor)
            case .dnsResolution:
                completionHandler(PacketTunnelProviderError.dnsResolutionFailure)
            case .setNetworkSettings:
                completionHandler(PacketTunnelProviderError.couldNotSetNetworkSettings)
            case .startWireGuardBackend:
                completionHandler(PacketTunnelProviderError.couldNotStartBackend)
            case .invalidState:
                completionHandler(PacketTunnelProviderError.couldNotStartBackend)
            }
        }
    }

    open override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
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
