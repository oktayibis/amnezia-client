import SwiftUI
import AmneziaCore

public struct DashboardView: View {
    @ObservedObject var appState: AppState
    @State private var showServerListSheet = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                // Background Gradient
                backgroundLayer

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Header Status Pill
                        headerSection

                        // Clipboard Auto-Detection Banner
                        if let detected = appState.detectedClipboardUrl {
                            clipboardBanner(detected: detected)
                        }

                        // Centerpiece Connect Button
                        VStack(spacing: 2) {
                            ConnectButton(appState: appState)
                                .frame(height: 230)

                            Text(connectionSubtitle)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.65))
                        }

                        // Security Telemetry Chips (matching Android TV & Mobile)
                        securityChipsRow

                        // Server Selector Card
                        ConnectionStatusCard(appState: appState) {
                            if appState.profiles.isEmpty {
                                appState.isAddServerPresented = true
                            } else {
                                showServerListSheet = true
                            }
                        }

                        // Real-time Traffic Stats (Ping, Download, Upload, Duration)
                        LiveTrafficStatsView(appState: appState)

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        appState.importFromClipboard()
                    }) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("AWG CONNECT")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color.white.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        appState.isAddServerPresented = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showServerListSheet) {
                ServerListView(appState: appState, isPresentedAsSheet: true)
            }
            .sheet(isPresented: $appState.isAddServerPresented) {
                AddServerSheet(appState: appState)
            }
            .sheet(isPresented: $appState.isNetworkToolsPresented) {
                NetworkToolsView(appState: appState)
            }
            .alert("AWG Connect", isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { if !$0 { appState.errorMessage = nil } }
            )) {
                #if DEBUG
                if appState.errorMessage?.contains("Simulated Tunnel Engine") == true {
                    Button("Enable Simulation") {
                        appState.setSimulatedTunnel(true)
                        appState.errorMessage = nil
                        appState.toggleConnection()
                    }
                }
                #endif
                Button("OK", role: .cancel) {
                    appState.errorMessage = nil
                }
            } message: {
                if let msg = appState.errorMessage {
                    Text(msg)
                }
            }
        }
    }

    // MARK: - Subviews

    private var connectionSubtitle: String {
        if appState.connectionState.isConnected {
            return "Tunnel is active & secured"
        } else if appState.connectionState.isBusy {
            return "Establishing tunnel..."
        } else {
            return "Tap power button to connect"
        }
    }

    private var securityChipsRow: some View {
        HStack(spacing: 6) {
            securityChip(icon: "checkmark.shield.fill", label: "Zero logs")
            securityChip(icon: "bolt.shield.fill", label: "AmneziaWG")
            securityChip(icon: "lock.icloud.fill", label: "Private DNS")
            Button(action: {
                appState.measureLatency()
            }) {
                HStack(spacing: 4) {
                    if appState.isMeasuringPing {
                        ProgressView()
                            .scaleEffect(0.65)
                            .tint(.green)
                    } else {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    Text(appState.connectionStats.latencyMs.map { "\($0) ms" }
                         ?? appState.selectedProfile?.pingMs.map { "\($0) ms" }
                         ?? "Ping")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.14))
                        .overlay(
                            Capsule()
                                .stroke(Color.green.opacity(0.35), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(appState.isMeasuringPing)
        }
    }

    private func securityChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.green)
            Text(label)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var headerSection: some View {
        HStack {
            StatusPill(state: appState.connectionState)
            Spacer()
            #if DEBUG
            if appState.isSimulatedTunnel {
                Text("SIMULATED")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.2))
                    .foregroundColor(.yellow)
                    .clipShape(Capsule())
            }
            #endif
        }
    }

    private func clipboardBanner(detected: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard.fill")
                .foregroundColor(.yellow)
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 2) {
                Text("Configuration in Clipboard")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)

                Text("Tap to import immediately")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Import") {
                do {
                    _ = try appState.importFromText(detected)
                    appState.detectedClipboardUrl = nil
                } catch {
                    appState.errorMessage = error.localizedDescription
                }
            }
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.yellow)
            .foregroundColor(.black)
            .clipShape(Capsule())

            Button(action: {
                appState.detectedClipboardUrl = nil
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var backgroundLayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Subtle ambient radial glow
            RadialGradient(
                colors: [
                    appState.connectionState.isConnected ? Color.green.opacity(0.18) :
                    appState.connectionState.isConnecting ? Color.orange.opacity(0.18) :
                    Color.blue.opacity(0.06),
                Color.clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 450
            )
            .ignoresSafeArea()
        }
    }
}
