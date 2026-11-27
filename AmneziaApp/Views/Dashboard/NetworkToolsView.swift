import SwiftUI
import AmneziaCore

public struct NetworkToolsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    public init(appState: AppState) {
        self.appState = appState
    }

    private var stats: ConnectionStatistics {
        appState.connectionStats
    }

    private var profile: ServerProfile? {
        appState.selectedProfile
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        // 1. Live Tunnel Diagnostics Card
                        tunnelTelemetrySection

                        // 2. Built-in Speedtest Card
                        speedtestSection

                        // 3. Ping, Jitter & Packet Loss Card
                        pingJitterSection

                        // 4. Exit IP & DNS Verification Card
                        identitySection

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                }
            }
            .navigationTitle("Network Tools & Metrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                if appState.networkIdentity == nil && !appState.isCheckingIdentity {
                    appState.checkNetworkIdentity()
                }
                if appState.pingJitterReport == nil && !appState.isRunningPingSeries {
                    appState.runPingDiagnostics()
                }
            }
        }
    }

    // MARK: - 1. Live Tunnel Telemetry

    private var tunnelTelemetrySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("TUNNEL TELEMETRY", systemImage: "shield.lefthalf.filled")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundColor(.green)

                    Spacer()

                    StatusPill(state: appState.connectionState)
                }

                Divider().background(Color.white.opacity(0.1))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    telemetryItem(title: "Active Server", value: profile?.name ?? "None")
                    telemetryItem(title: "Protocol", value: profile?.protocolType.badgeTitle ?? "--")
                    telemetryItem(title: "Endpoint", value: profile?.endpointString ?? "--")
                    telemetryItem(title: "Tunnel IP", value: profile?.clientAddresses.first ?? "--")
                    telemetryItem(title: "Last Handshake", value: appState.connectionState.isConnected ? stats.formattedHandshakeAge() : "--")
                    telemetryItem(title: "Session Uptime", value: appState.connectionState.isConnected ? stats.formattedDuration : "00:00")
                    telemetryItem(title: "MTU / Keepalive", value: "\(profile?.mtu.map(String.init) ?? "Auto") / \(profile?.persistentKeepaliveValue.map { "\($0)s" } ?? "Off")")
                    telemetryItem(title: "Total RX / TX", value: "\(stats.formattedBytesIn) / \(stats.formattedBytesOut)")
                }
            }
        }
    }

    private func telemetryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 2. Built-in Speedtest

    private var speedtestSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("BUILT-IN SPEEDTEST", systemImage: "speedometer")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundColor(.cyan)

                    Spacer()

                    Text(appState.speedtestPhase.rawValue)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    speedGauge(
                        title: "DOWNLOAD",
                        icon: "arrow.down.circle.fill",
                        color: .green,
                        mbps: appState.speedtestResult?.downloadMbps
                    )

                    speedGauge(
                        title: "UPLOAD",
                        icon: "arrow.up.circle.fill",
                        color: .cyan,
                        mbps: appState.speedtestResult?.uploadMbps
                    )
                }

                if let res = appState.speedtestResult {
                    HStack(spacing: 16) {
                        Label("Ping: \(res.pingMs) ms", systemImage: "waveform.path.ecg")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.green)

                        Label("Jitter: \(res.jitterMs) ms", systemImage: "chart.xyaxis.line")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.orange)

                        Spacer()
                    }
                }

                Button(action: {
                    appState.runSpeedtest()
                }) {
                    HStack(spacing: 8) {
                        if appState.isRunningSpeedtest {
                            ProgressView()
                                .tint(.black)
                            Text(appState.speedtestPhase.rawValue)
                        } else {
                            Image(systemName: "play.fill")
                            Text(appState.speedtestResult == nil ? "Run Speedtest" : "Run Speedtest Again")
                        }
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(appState.isRunningSpeedtest ? Color.cyan.opacity(0.6) : Color.cyan)
                    .foregroundColor(.black)
                    .cornerRadius(12)
                }
                .disabled(appState.isRunningSpeedtest)
            }
        }
    }

    private func speedGauge(title: String, icon: String, color: Color, mbps: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(mbps.map { String(format: "%.1f", $0) } ?? "--")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Mbps")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - 3. Multi-sample Ping & Jitter

    private var pingJitterSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("LATENCY & JITTER PROBE", systemImage: "waveform.path.ecg")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundColor(.orange)

                    Spacer()

                    Button(action: {
                        appState.runPingDiagnostics()
                    }) {
                        HStack(spacing: 4) {
                            if appState.isRunningPingSeries {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(.orange)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Text("Test")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.orange)
                    }
                    .disabled(appState.isRunningPingSeries)
                }

                let report = appState.pingJitterReport
                HStack(spacing: 0) {
                    pingStatPill(label: "AVG PING", value: report.map { "\($0.avgMs) ms" } ?? "--", color: .green)
                    pingStatPill(label: "MIN / MAX", value: report.map { "\($0.minMs)/\($0.maxMs) ms" } ?? "--", color: .white)
                    pingStatPill(label: "JITTER", value: report.map { "\($0.jitterMs) ms" } ?? "--", color: .orange)
                    pingStatPill(label: "LOSS", value: report.map { "\($0.packetLossPercent)%" } ?? "--", color: (report?.packetLossPercent ?? 0) == 0 ? .green : .red)
                }
            }
        }
    }

    private func pingStatPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4. Public Exit IP & DNS Check

    private var identitySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("EXIT IP & DNS CHECK", systemImage: "network")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundColor(.purple)

                    Spacer()

                    Button(action: {
                        appState.checkNetworkIdentity()
                    }) {
                        HStack(spacing: 4) {
                            if appState.isCheckingIdentity {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(.purple)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Text("Verify")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.purple)
                    }
                    .disabled(appState.isCheckingIdentity)
                }

                if let identity = appState.networkIdentity {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        telemetryItem(title: "Public Exit IP", value: identity.publicIp)
                        telemetryItem(title: "Location / PoP", value: [identity.countryCode, identity.colo].filter { !$0.isEmpty }.joined(separator: " • "))
                        telemetryItem(title: "DNS Latency", value: identity.dnsLatencyMs.map { "\($0) ms" } ?? "--")
                        telemetryItem(title: "Transport", value: identity.tlsVersion.isEmpty ? "Encrypted" : identity.tlsVersion)
                    }
                } else {
                    Text(appState.isCheckingIdentity ? "Checking public exit IP and DNS resolver..." : "Tap Verify to check your current exit IP and DNS response time.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
