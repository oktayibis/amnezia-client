import SwiftUI
import AmneziaCore

public struct LiveTrafficStatsView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var stats: ConnectionStatistics {
        appState.connectionStats
    }

    private var isConnected: Bool {
        appState.connectionState.isConnected
    }

    private var pingText: String {
        if let latency = stats.latencyMs ?? appState.selectedProfile?.pingMs {
            return "\(latency) ms"
        }
        return "--"
    }

    public var body: some View {
        if appState.providesTrafficStats {
            VStack(spacing: 12) {
                // 4-Column Network Metrics Strip (matching Android TV / Mobile)
                GlassCard {
                    HStack(spacing: 0) {
                        metricColumn(
                            icon: "waveform.path.ecg",
                            color: .green,
                            label: "PING",
                            value: pingText
                        )

                        Divider()
                            .frame(height: 32)
                            .background(Color.white.opacity(0.1))

                        metricColumn(
                            icon: "arrow.down.circle.fill",
                            color: .green,
                            label: "DOWN",
                            value: isConnected ? stats.formattedDownSpeed : "0 B/s"
                        )

                        Divider()
                            .frame(height: 32)
                            .background(Color.white.opacity(0.1))

                        metricColumn(
                            icon: "arrow.up.circle.fill",
                            color: .cyan,
                            label: "UP",
                            value: isConnected ? stats.formattedUpSpeed : "0 B/s"
                        )

                        Divider()
                            .frame(height: 32)
                            .background(Color.white.opacity(0.1))

                        metricColumn(
                            icon: "timer",
                            color: .orange,
                            label: "TIME",
                            value: isConnected ? stats.formattedDuration : "00:00"
                        )
                    }
                }

                // Detailed Download & Upload Totals + Built-in Speedtest / Network Tools Card
                Button(action: {
                    appState.isNetworkToolsPresented = true
                }) {
                    GlassCard {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.cyan.opacity(0.16))
                                    .frame(width: 40, height: 40)

                                Image(systemName: "speedometer")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.cyan)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Speedtest & Network Diagnostics")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)

                                HStack(spacing: 8) {
                                    if let speed = appState.speedtestResult {
                                        Text("↓ \(speed.formattedDownloadMbps) • ↑ \(speed.formattedUploadMbps)")
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.cyan)
                                    } else {
                                        Text(isConnected ? "Total: ↓\(stats.formattedBytesIn) ↑\(stats.formattedBytesOut) • Handshake \(stats.formattedHandshakeAge())" : "Run Speedtest, Ping/Jitter & Exit IP check")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func metricColumn(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}
