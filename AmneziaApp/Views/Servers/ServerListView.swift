import SwiftUI
import AmneziaCore

public struct ServerListView: View {
    @ObservedObject var appState: AppState
    var isPresentedAsSheet: Bool = false
    @Environment(\.dismiss) private var dismiss
    private enum ActiveSheet: Identifiable {
        case addServer
        case detail(ServerProfile)
        case share(ServerProfile)

        var id: String {
            switch self {
            case .addServer:
                return "addServer"
            case .detail(let profile):
                return "detail_\(profile.id)"
            case .share(let profile):
                return "share_\(profile.id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?

    public init(appState: AppState, isPresentedAsSheet: Bool = false) {
        self.appState = appState
        self.isPresentedAsSheet = isPresentedAsSheet
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if appState.profiles.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(appState.profiles) { profile in
                            serverRow(profile)
                                .listRowBackground(Color(white: 0.12))
                                .listRowSeparatorTint(Color.white.opacity(0.1))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        appState.deleteProfile(profile)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }

                                    Button {
                                        activeSheet = .share(profile)
                                    } label: {
                                        Label("Share", systemImage: "qrcode")
                                    }
                                    .tint(.purple)

                                    Button {
                                        activeSheet = .detail(profile)
                                    } label: {
                                        Label("Details", systemImage: "info.circle")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Servers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isPresentedAsSheet {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            dismiss()
                        }
                        .foregroundColor(.white)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: {
                            appState.measureLatency()
                        }) {
                            if appState.isMeasuringPing {
                                ProgressView()
                                    .tint(.green)
                            } else {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                        }
                        .disabled(appState.isMeasuringPing)

                        Button(action: {
                            activeSheet = .addServer
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .addServer:
                    AddServerSheet(appState: appState)
                case .detail(let profile):
                    ServerDetailView(appState: appState, profile: profile)
                case .share(let profile):
                    ServerShareQrView(profile: profile)
                }
            }
            .onChange(of: appState.profiles.count) { newCount in
                if isPresentedAsSheet && newCount > 0 {
                    dismiss()
                }
            }
        }
    }

    private func serverRow(_ profile: ServerProfile) -> some View {
        let isSelected = appState.selectedProfile?.id == profile.id

        return Button(action: {
            appState.selectProfile(profile)
            if isPresentedAsSheet {
                dismiss()
            }
        }) {
            HStack(spacing: 14) {
                // Country / Server flag
                Text(profile.flagEmoji)
                    .font(.system(size: 28))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(profile.name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 14))
                        }
                    }

                    HStack(spacing: 6) {
                        Text(profile.protocolType.badgeTitle)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(profile.protocolType == .amneziaWg ? Color.purple.opacity(0.3) : Color.blue.opacity(0.3))
                            )
                            .foregroundColor(profile.protocolType == .amneziaWg ? .purple : .blue)

                        Text(profile.endpointString)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Ping Latency
                if let ping = profile.pingMs {
                    Text("\(ping) ms")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.3))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "network.slash")
                .font(.system(size: 54))
                .foregroundColor(.secondary)

            Text("No Servers Added Yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Import a server via QR code or connection URL to start using AWG Connect.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: {
                activeSheet = .addServer
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Server")
                }
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.green)
                .foregroundColor(.black)
                .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
    }
}
