import SwiftUI
import AmneziaCore

public struct MacDashboardView: View {
    @ObservedObject var appState: MacAppState
    var onOpenServers: (() -> Void)? = nil
    @State private var isHoveringButton = false
    @State private var isConnectAnimating = false

    public init(appState: MacAppState, onOpenServers: (() -> Void)? = nil) {
        self.appState = appState
        self.onOpenServers = onOpenServers
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                // Top Status Bar Banner
                topStatusBar

                // Clipboard Import Banner if detected
                if let detected = appState.detectedClipboardUrl {
                    clipboardBanner(detected: detected)
                }

                // Centerpiece Connect Button
                connectButtonSection

                // Connection Duration Timer
                if appState.connectionState.isConnected {
                    connectionDurationBadge
                }

                // Live Speed Gauges & Traffic Stats
                trafficStatsSection

                // Active Server Information Card
                activeServerCard
            }
            .padding(32)
            .frame(maxWidth: 680)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(
                    gradient: Gradient(colors: [
                        accentGlowColor.opacity(0.12),
                        Color.clear
                    ]),
                    center: .top,
                    startRadius: 20,
                    endRadius: 400
                )
            }
        )
    }

    // MARK: - Top Status Bar
    private var topStatusBar: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.8), radius: 4)

                Text(statusText.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(statusColor)
                    .tracking(1.2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())

            Spacer()

            #if DEBUG
            if appState.isSimulatedTunnel {
                Text("SIMULATED TUNNEL")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.yellow.opacity(0.15))
                    .foregroundColor(.yellow)
                    .clipShape(Capsule())
            }
            #endif
        }
    }

    // MARK: - Clipboard Banner
    private func clipboardBanner(detected: String) -> some View {
        MacGlassCard(cornerRadius: 12, strokeColor: .green.opacity(0.3)) {
            HStack(spacing: 14) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 3) {
                    Text("VPN Configuration Detected in Clipboard")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("Found a valid configuration link. Click to import.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Import Now") {
                    do {
                        _ = try appState.importFromText(detected)
                        appState.dismissClipboardBanner()
                    } catch {
                        appState.errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button(action: { appState.dismissClipboardBanner() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
        }
    }

    // MARK: - Connect Button Section
    private var connectButtonSection: some View {
        VStack(spacing: 18) {
            ZStack {
                // Outer ambient glow ring
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                buttonAccentColor.opacity(appState.connectionState.isConnected ? 0.35 : 0.1),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 60,
                            endRadius: 130
                        )
                    )
                    .frame(width: 260, height: 260)
                    .scaleEffect(appState.connectionState.isBusy ? 1.08 : 1.0)
                    .animation(
                        appState.connectionState.isBusy
                        ? Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                        : .default,
                        value: appState.connectionState.isBusy
                    )

                // Concentric stroke ring
                Circle()
                    .stroke(buttonAccentColor.opacity(0.3), lineWidth: 2)
                    .frame(width: 172, height: 172)

                // Interactive Main Button
                Button(action: {
                    appState.toggleConnection()
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        buttonAccentColor.opacity(isHoveringButton ? 0.95 : 0.85),
                                        buttonAccentColor.opacity(0.65)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 144, height: 144)
                            .shadow(color: buttonAccentColor.opacity(0.5), radius: isHoveringButton ? 16 : 8, x: 0, y: 6)

                        VStack(spacing: 6) {
                            if appState.connectionState.isBusy {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.2)
                            } else {
                                Image(systemName: "power")
                                    .font(.system(size: 42, weight: .semibold))
                                    .foregroundColor(.white)

                                Text(buttonLabel.uppercased())
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white.opacity(0.9))
                                    .tracking(1.5)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .scaleEffect(isHoveringButton ? 1.04 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHoveringButton)
                .onHover { isHoveringButton = $0 }
            }
        }
    }

    // MARK: - Duration Badge
    private var connectionDurationBadge: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))

                Text("Connected for \(appState.connectionStats.formattedDuration)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }

            if let ping = appState.connectionStats.latencyMs ?? appState.selectedProfile?.pingMs {
                Text("•")
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundColor(.green)
                        .font(.system(size: 11))
                    Text("\(ping) ms")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.green)
                }
            }

            if appState.connectionStats.lastHandshake != nil {
                Text("•")
                    .foregroundColor(.secondary)
                Text("Handshake \(appState.connectionStats.formattedHandshakeAge())")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }

    // MARK: - Traffic Stats Section
    @ViewBuilder
    private var trafficStatsSection: some View {
        if appState.providesTrafficStats {
            HStack(spacing: 18) {
            // Download Gauge
            MacGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.green)
                        Text("DOWNLOAD")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    Text(appState.connectionStats.formattedDownSpeed)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Session: \(appState.connectionStats.formattedBytesIn)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(18)
            }

            // Upload Gauge
            MacGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                        Text("UPLOAD")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    Text(appState.connectionStats.formattedUpSpeed)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Session: \(appState.connectionStats.formattedBytesOut)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(18)
            }
        }
        }
    }

    // MARK: - Active Server Card
    private var activeServerCard: some View {
        MacGlassCard {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "globe.europe.africa.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                }

                if let profile = appState.selectedProfile {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(profile.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)

                            Text(profile.protocolType.badgeTitle)
                                .font(.system(size: 10, weight: .heavy))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(profile.protocolType == .amneziaWg ? Color.purple.opacity(0.3) : Color.blue.opacity(0.3))
                                .foregroundColor(profile.protocolType == .amneziaWg ? .purple : .blue)
                                .clipShape(Capsule())
                        }

                        Text(profile.endpointString)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No Server Selected")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        Text("Drag & drop a .vpn file here or select from Servers")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if onOpenServers != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(18)
            .contentShape(Rectangle())
            .onTapGesture {
                onOpenServers?()
            }
        }
    }

    // MARK: - Computed Colors & Labels
    private var buttonAccentColor: Color {
        switch appState.connectionState {
        case .connected: return .green
        case .connecting, .disconnecting, .reconnecting: return .orange
        case .disconnected: return Color(white: 0.25)
        case .error: return .red
        }
    }

    private var accentGlowColor: Color {
        switch appState.connectionState {
        case .connected: return .green
        case .connecting, .disconnecting, .reconnecting: return .orange
        case .disconnected: return .blue
        case .error: return .red
        }
    }

    private var statusColor: Color {
        switch appState.connectionState {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnecting: return .red
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var statusText: String {
        switch appState.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Negotiating Handshake..."
        case .disconnecting: return "Disconnecting..."
        case .reconnecting: return "Reconnecting..."
        case .disconnected: return "Not Protected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var buttonLabel: String {
        switch appState.connectionState {
        case .connected: return "Disconnect"
        case .connecting: return "Connecting"
        case .disconnecting: return "Disconnecting"
        case .reconnecting: return "Reconnecting"
        case .disconnected: return "Connect"
        case .error: return "Retry"
        }
    }
}
