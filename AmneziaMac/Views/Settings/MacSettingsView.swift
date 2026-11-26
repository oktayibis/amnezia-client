import SwiftUI
import AmneziaCore

public struct MacSettingsView: View {
    @ObservedObject var appState: MacAppState
    @AppStorage("amnezia_mac_kill_switch") private var isKillSwitchEnabled: Bool = false
    @AppStorage("amnezia_mac_connect_on_launch") private var isConnectOnLaunch: Bool = false
    @AppStorage("amnezia_mac_dns_provider") private var selectedDns: String = DnsProvider.serverDefault.rawValue
    @AppStorage("amnezia_mac_custom_dns") private var customDnsIp: String = ""

    public init(appState: MacAppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("PREFERENCES")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                // Security & Behavior Section
                VStack(alignment: .leading, spacing: 14) {
                    Text("TUNNEL & SECURITY")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    MacGlassCard {
                        VStack(spacing: 0) {
                            Toggle(isOn: $isKillSwitchEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Kill Switch")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("Block all outgoing internet traffic if the VPN tunnel disconnects unexpectedly")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(14)

                            Divider()

                            Toggle(isOn: $isConnectOnLaunch) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Connect on Launch")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("Automatically establish tunnel to active server when AWG Connect launches")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(14)
                        }
                    }
                }

                // DNS Section
                VStack(alignment: .leading, spacing: 14) {
                    Text("DNS CONFIGURATION")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    MacGlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker("DNS Resolver", selection: $selectedDns) {
                                ForEach(DnsProvider.allCases) { provider in
                                    Text(provider.rawValue).tag(provider.rawValue)
                                }
                            }
                            .pickerStyle(.menu)

                            if selectedDns == DnsProvider.custom.rawValue {
                                TextField("Enter DNS Server IP (e.g. 9.9.9.9)", text: $customDnsIp)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Text("Secure DNS resolves domain names inside the encrypted tunnel, preventing ISP eavesdropping.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                    }
                }

                // Diagnostics & Developer Mode
                #if DEBUG
                VStack(alignment: .leading, spacing: 14) {
                    Text("DEVELOPER / DIAGNOSTICS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    MacGlassCard {
                        Toggle(isOn: Binding(
                            get: { appState.isSimulatedTunnel },
                            set: { appState.setSimulatedTunnel($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Simulated Tunnel Engine")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Simulates packet flow, bandwidth meters, and connection states. Ideal for local testing.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tint(.yellow)
                        .padding(14)
                    }
                }
                #endif

                // About Section
                VStack(alignment: .leading, spacing: 14) {
                    Text("ABOUT")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    MacGlassCard {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Version")
                                    .foregroundColor(.white)
                                Spacer()
                                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                                Text("\(version) (\(build))")
                                    .foregroundColor(.secondary)
                            }

                            Divider()

                            HStack {
                                Text("Protocols Supported")
                                    .foregroundColor(.white)
                                Spacer()
                                Text("AmneziaWG, WireGuard")
                                    .foregroundColor(.secondary)
                            }

                            Divider()

                            HStack {
                                Text("Privacy Policy")
                                    .foregroundColor(.white)
                                Spacer()
                                Link("Online Policy", destination: URL(string: "https://github.com/oktayibis/amnezia-clinet/blob/main/PRIVACY.md")!)
                            }

                            Divider()

                            HStack {
                                Text("Open Source Project")
                                    .foregroundColor(.white)
                                Spacer()
                                Link("GitHub Repository", destination: URL(string: "https://github.com/oktayibis/amnezia-clinet")!)
                            }
                        }
                        .font(.system(size: 12))
                        .padding(14)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 640)
        }
    }
}
