import SwiftUI
import Combine
import AppKit
import AmneziaCore
import Network

@MainActor
public final class MacAppState: ObservableObject {
    @Published public var connectionState: ConnectionState = .disconnected
    @Published public var connectionStats: ConnectionStatistics = ConnectionStatistics()
    @Published public var profiles: [ServerProfile] = []
    @Published public var selectedProfile: ServerProfile? = nil
    @Published public var errorMessage: String? = nil
    @Published public var detectedClipboardUrl: String? = nil
    @Published public var isSimulatedTunnel: Bool = false
    @Published public var isPrivacyNoticePresented: Bool = false

    private let storage = ProfileStorage.shared
    private var tunnelService: TunnelService
    private var lastCheckedClipboard: String = ""

    public var providesTrafficStats: Bool {
        tunnelService.providesTrafficStats
    }

    public init(tunnelService: TunnelService? = nil) {
        #if DEBUG
        let savedSim = UserDefaults.standard.object(forKey: "amnezia_mac_simulated_tunnel") as? Bool ?? false
        self.isSimulatedTunnel = savedSim
        let defaultService: TunnelService = savedSim ? MockTunnelService.shared : NetworkExtensionTunnelService.shared
        #else
        self.isSimulatedTunnel = false
        let defaultService: TunnelService = NetworkExtensionTunnelService.shared
        #endif
        self.tunnelService = tunnelService ?? defaultService

        loadProfiles()
        setupTunnelCallbacks()
    }

    #if DEBUG
    public func setSimulatedTunnel(_ simulated: Bool) {
        isSimulatedTunnel = simulated
        UserDefaults.standard.set(simulated, forKey: "amnezia_mac_simulated_tunnel")
        if simulated {
            tunnelService = MockTunnelService.shared
        } else {
            #if canImport(NetworkExtension)
            tunnelService = NetworkExtensionTunnelService.shared
            #else
            tunnelService = MockTunnelService.shared
            #endif
        }
        setupTunnelCallbacks()
    }
    #endif

    private func setupTunnelCallbacks() {
        if let mock = tunnelService as? MockTunnelService {
            mock.onStateChange = { [weak self] state in
                DispatchQueue.main.async {
                    self?.connectionState = state
                }
            }
            mock.onStatsChange = { [weak self] stats in
                DispatchQueue.main.async {
                    self?.connectionStats = stats
                }
            }
        } else if let ne = tunnelService as? NetworkExtensionTunnelService {
            ne.onStateChange = { [weak self] state in
                DispatchQueue.main.async {
                    self?.connectionState = state
                }
            }
            ne.onStatsChange = { [weak self] stats in
                DispatchQueue.main.async {
                    self?.connectionStats = stats
                }
            }
        }
        connectionState = tunnelService.currentState
        connectionStats = tunnelService.currentStats
    }

    public func loadProfiles() {
        profiles = storage.loadProfiles()
        if profiles.isEmpty {
            selectedProfile = nil
            return
        }
        if let selected = storage.selectedProfile(), profiles.contains(where: { $0.id == selected.id }) {
            selectedProfile = selected
        } else if let first = profiles.first {
            selectProfile(first)
        } else {
            selectedProfile = nil
        }
    }

    private func currentTunnelOptions() -> TunnelOptions {
        let killSwitch = UserDefaults.standard.bool(forKey: "amnezia_mac_kill_switch")
        let dnsRaw = UserDefaults.standard.string(forKey: "amnezia_mac_dns_provider") ?? DnsProvider.serverDefault.rawValue
        let dnsProvider = DnsProvider(rawValue: dnsRaw) ?? .serverDefault
        let dnsOverride: [String]?
        if !dnsProvider.ips.isEmpty {
            dnsOverride = dnsProvider.ips
        } else if dnsProvider == .custom,
                  let customIp = UserDefaults.standard.string(forKey: "amnezia_mac_custom_dns"),
                  !customIp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dnsOverride = [customIp.trimmingCharacters(in: .whitespacesAndNewlines)]
        } else {
            dnsOverride = nil
        }
        return TunnelOptions(killSwitch: killSwitch, dnsOverride: dnsOverride)
    }

    public func selectProfile(_ profile: ServerProfile) {
        selectedProfile = profile
        storage.selectProfile(id: profile.id)

        if connectionState.isConnected {
            Task {
                do {
                    let options = currentTunnelOptions()
                    try await tunnelService.stopTunnel()
                    try await Task.sleep(nanoseconds: 500_000_000)
                    try await tunnelService.startTunnel(with: profile, options: options)
                } catch {
                    handleTunnelError(error)
                }
            }
        }
    }

    public func toggleConnection() {
        let isPrivacyAccepted = UserDefaults.standard.bool(forKey: "awg_privacy_notice_accepted")
        if !isPrivacyAccepted {
            isPrivacyNoticePresented = true
            errorMessage = "Please review and agree to the Privacy Notice before connecting."
            return
        }

        Task {
            do {
                if connectionState.isConnected || connectionState.isBusy {
                    try await tunnelService.stopTunnel()
                } else {
                    guard let profile = selectedProfile else {
                        errorMessage = "Please import or select a server first"
                        return
                    }
                    let options = currentTunnelOptions()
                    try await tunnelService.startTunnel(with: profile, options: options)
                }
            } catch {
                handleTunnelError(error)
            }
        }
    }

    private func handleTunnelError(_ error: Error) {
        let desc = error.localizedDescription
        if desc.localizedCaseInsensitiveContains("permission denied") {
            errorMessage = "VPN configuration permission was denied. Open System Settings → Network → VPN & Filters to allow the connection profile."
        } else {
            errorMessage = desc
        }
    }

    public func addProfile(_ profile: ServerProfile) {
        storage.addProfile(profile)
        loadProfiles()
        selectProfile(profile)
    }

    public func deleteProfile(_ profile: ServerProfile) {
        if selectedProfile?.id == profile.id {
            selectedProfile = nil
            if connectionState.isConnected {
                Task {
                    try? await tunnelService.stopTunnel()
                }
            }
        }
        storage.deleteProfile(id: profile.id)
        loadProfiles()
    }

    public func renameProfile(_ profile: ServerProfile, to newName: String) {
        var updated = profile
        updated.name = newName
        storage.updateProfile(updated)
        loadProfiles()
    }

    // MARK: - Import Handlers

    public func importFromText(_ text: String) throws -> ServerProfile {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile: ServerProfile

        if trimmed.lowercased().hasPrefix("vpn://") || trimmed.lowercased().hasPrefix("amnezia://") {
            let normalized = trimmed.lowercased().hasPrefix("amnezia://")
                ? "vpn://" + String(trimmed.dropFirst("amnezia://".count))
                : trimmed
            profile = try AmneziaUrlDecoder.decode(normalized)
        } else if trimmed.contains("[Interface]") && trimmed.contains("[Peer]") {
            profile = try WgQuickConfigParser.parse(trimmed, profileName: "Imported Config")
        } else if trimmed.hasPrefix("{") {
            profile = try AmneziaUrlDecoder.decode(trimmed)
        } else {
            profile = try AmneziaUrlDecoder.decode("vpn://\(trimmed)")
        }

        addProfile(profile)
        return profile
    }

    public func importFromFile(url: URL) throws -> ServerProfile {
        let data = try Data(contentsOf: url)
        let profileName = url.deletingPathExtension().lastPathComponent

        if let content = String(data: data, encoding: .utf8) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("[Interface]") && !trimmed.lowercased().hasPrefix("vpn://") && !trimmed.hasPrefix("{") {
                let profile = try WgQuickConfigParser.parse(trimmed, profileName: profileName)
                addProfile(profile)
                return profile
            }
            return try importFromText(trimmed)
        }
        if let decompressed = try? ZlibHelper.decompressQt(data),
           let decompressedStr = String(data: decompressed, encoding: .utf8) {
            return try importFromText(decompressedStr)
        }
        throw AmneziaDecoderError.base64DecodingFailed
    }

    // MARK: - User-triggered Clipboard Handler

    public func checkClipboard() {
        guard let string = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty,
              string != lastCheckedClipboard else { return }

        lastCheckedClipboard = string

        if string.hasPrefix("vpn://") || (string.contains("[Interface]") && string.contains("[Peer]")) {
            self.detectedClipboardUrl = string
        } else {
            self.detectedClipboardUrl = nil
        }
    }

    public func importFromClipboard() {
        guard let string = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else {
            errorMessage = "Clipboard is empty."
            return
        }

        do {
            _ = try importFromText(string)
            self.detectedClipboardUrl = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func dismissClipboardBanner() {
        detectedClipboardUrl = nil
    }
}
