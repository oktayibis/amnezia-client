import SwiftUI
import Combine
import AmneziaCore
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    @Published public var profiles: [ServerProfile] = []
    @Published public var selectedProfile: ServerProfile?
    @Published public var connectionState: ConnectionState = .disconnected
    @Published public var connectionStats: ConnectionStatistics = ConnectionStatistics()
    
    // UI Navigation & Sheets
    @Published public var isAddServerPresented: Bool = false
    @Published public var activeSheet: SheetType? = nil
    @Published public var errorMessage: String? = nil
    @Published public var detectedClipboardUrl: String? = nil
    @Published public var isSimulatedTunnel: Bool = false
    @Published public var isPrivacyNoticePresented: Bool = false

    public enum SheetType: Identifiable {
        case qrScanner
        case photoPicker
        case manualInput
        case serverDetail(ServerProfile)
        case shareQr(ServerProfile)

        public var id: String {
            switch self {
            case .qrScanner: return "qrScanner"
            case .photoPicker: return "photoPicker"
            case .manualInput: return "manualInput"
            case .serverDetail(let p): return "detail-\(p.id)"
            case .shareQr(let p): return "share-\(p.id)"
            }
        }
    }

    private let storage = ProfileStorage.shared
    private var tunnelService: TunnelService

    public var providesTrafficStats: Bool {
        tunnelService.providesTrafficStats
    }

    public init(tunnelService: TunnelService? = nil) {
        #if targetEnvironment(simulator)
        let defaultService: TunnelService = MockTunnelService.shared
        self.isSimulatedTunnel = true
        #elseif DEBUG
        let savedSim = UserDefaults.standard.bool(forKey: "amnezia_simulated_tunnel")
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
        UserDefaults.standard.set(simulated, forKey: "amnezia_simulated_tunnel")
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
                Task { @MainActor in
                    self?.connectionState = state
                }
            }
            mock.onStatsChange = { [weak self] stats in
                Task { @MainActor in
                    self?.connectionStats = stats
                }
            }
        }
        #if canImport(NetworkExtension)
        if let ne = tunnelService as? NetworkExtensionTunnelService {
            ne.onStateChange = { [weak self] state in
                Task { @MainActor in
                    self?.connectionState = state
                }
            }
            ne.onStatsChange = { [weak self] stats in
                Task { @MainActor in
                    self?.connectionStats = stats
                }
            }
        }
        #endif
        
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
        let killSwitch = UserDefaults.standard.bool(forKey: "amnezia_kill_switch")
        let dnsRaw = UserDefaults.standard.string(forKey: "amnezia_dns_provider") ?? DnsProvider.serverDefault.rawValue
        let dnsProvider = DnsProvider(rawValue: dnsRaw) ?? .serverDefault
        let dnsOverride: [String]?
        if !dnsProvider.ips.isEmpty {
            dnsOverride = dnsProvider.ips
        } else if dnsProvider == .custom,
                  let customIp = UserDefaults.standard.string(forKey: "amnezia_custom_dns"),
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
        HapticFeedback.selection()

        // If connected, reconnect to the newly selected profile
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
        HapticFeedback.impact(style: .heavy)
        let isPrivacyAccepted = UserDefaults.standard.bool(forKey: "awg_privacy_notice_accepted")
        if !isPrivacyAccepted {
            isPrivacyNoticePresented = true
            HapticFeedback.notification(type: .warning)
            return
        }

        Task {
            do {
                if connectionState.isConnected || connectionState.isBusy {
                    try await tunnelService.stopTunnel()
                    HapticFeedback.notification(type: .warning)
                } else {
                    guard let profile = selectedProfile else {
                        HapticFeedback.notification(type: .warning)
                        isAddServerPresented = true
                        return
                    }
                    let options = currentTunnelOptions()
                    try await tunnelService.startTunnel(with: profile, options: options)
                    HapticFeedback.notification(type: .success)
                }
            } catch {
                handleTunnelError(error)
            }
        }
    }

    private func handleTunnelError(_ error: Error) {
        let desc = error.localizedDescription
        if desc.localizedCaseInsensitiveContains("permission denied") {
            errorMessage = "VPN configuration permission was denied. Open Settings → General → VPN & Device Management to allow."
        } else {
            errorMessage = desc
        }
        HapticFeedback.notification(type: .error)
    }

    public func addProfile(_ profile: ServerProfile) {
        storage.addProfile(profile)
        loadProfiles()
        selectProfile(profile)
        HapticFeedback.notification(type: .success)
    }

    public func updateProfile(_ profile: ServerProfile) {
        storage.updateProfile(profile)
        loadProfiles()
    }

    public func deleteProfile(_ profile: ServerProfile) {
        if connectionState.isConnected && selectedProfile?.id == profile.id {
            Task {
                try? await tunnelService.stopTunnel()
            }
        }
        if selectedProfile?.id == profile.id {
            selectedProfile = nil
        }
        storage.deleteProfile(id: profile.id)
        loadProfiles()
        HapticFeedback.notification(type: .warning)
    }

    public func importFromText(_ input: String) throws -> ServerProfile {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile: ServerProfile

        let lower = trimmed.lowercased()
        if lower.hasPrefix("vpn://") || lower.hasPrefix("awgconnect://") || lower.hasPrefix("amnezia://") {
            profile = try AmneziaUrlDecoder.decode(trimmed)
        } else if trimmed.contains("[Interface]") && trimmed.contains("[Peer]") {
            profile = try WgQuickConfigParser.parse(trimmed)
        } else if trimmed.hasPrefix("{") {
            profile = try AmneziaUrlDecoder.decode(trimmed)
        } else {
            // Try base64 URL decode
            profile = try AmneziaUrlDecoder.decode("vpn://\(trimmed)")
        }

        addProfile(profile)
        return profile
    }

    public func importFromFile(url: URL) throws -> ServerProfile {
        let data = try Data(contentsOf: url)
        if let str = String(data: data, encoding: .utf8) {
            return try importFromText(str)
        }
        if let decompressed = try? ZlibHelper.decompressQt(data),
           let decompressedStr = String(data: decompressed, encoding: .utf8) {
            return try importFromText(decompressedStr)
        }
        throw AmneziaDecoderError.base64DecodingFailed
    }

    public func checkClipboardForConfig() {
        #if canImport(UIKit)
        if let string = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !string.isEmpty {
            if string.lowercased().hasPrefix("vpn://") ||
               (string.contains("[Interface]") && string.contains("[Peer]")) {
                detectedClipboardUrl = string
            }
        }
        #endif
    }

    public func importFromClipboard() {
        #if canImport(UIKit)
        if let string = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !string.isEmpty {
            do {
                _ = try importFromText(string)
                detectedClipboardUrl = nil
                HapticFeedback.notification(type: .success)
            } catch {
                errorMessage = error.localizedDescription
                HapticFeedback.notification(type: .error)
            }
        } else {
            errorMessage = "Clipboard is empty or does not contain valid configuration."
            HapticFeedback.notification(type: .warning)
        }
        #endif
    }
}
