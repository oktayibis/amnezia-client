import SwiftUI
import AmneziaCore
#if canImport(UIKit)
import UIKit
#endif

public struct ServerDetailView: View {
    @ObservedObject var appState: AppState
    @State var profile: ServerProfile
    @Environment(\.dismiss) private var dismiss
    @State private var isRevealingPrivateKey = false
    @State private var isEditingName = false
    @State private var serverNameText: String = ""
    @State private var copiedMessage: String?

    public init(appState: AppState, profile: ServerProfile) {
        self.appState = appState
        self._profile = State(initialValue: profile)
        self._serverNameText = State(initialValue: profile.name)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    // Server Overview Header
                    Section {
                        HStack(spacing: 14) {
                            Text(profile.flagEmoji)
                                .font(.system(size: 34))

                            VStack(alignment: .leading, spacing: 4) {
                                if isEditingName {
                                    TextField("Server Name", text: $serverNameText)
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.white)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    Text(profile.name)
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }

                                Text(profile.protocolType.badgeTitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(profile.protocolType == .amneziaWg ? .purple : .blue)
                            }

                            Spacer()

                            Button(action: {
                                if isEditingName {
                                    profile.name = serverNameText
                                    appState.updateProfile(profile)
                                    isEditingName = false
                                } else {
                                    isEditingName = true
                                }
                            }) {
                                Text(isEditingName ? "Save" : "Edit")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .listRowBackground(Color(white: 0.12))

                    // Connection Parameters
                    Section(header: Text("CONNECTION SETTINGS").font(.system(size: 12, weight: .bold)).foregroundColor(.secondary)) {
                        detailRow(title: "Endpoint", value: profile.endpointString)
                        detailRow(title: "Client Address", value: profile.clientAddresses.joined(separator: ", "))
                        detailRow(title: "DNS Servers", value: profile.dnsServers.joined(separator: ", "))
                        detailRow(title: "Allowed IPs", value: profile.allowedIps.joined(separator: ", "))
                        if let mtu = profile.mtu {
                            detailRow(title: "MTU", value: "\(mtu)")
                        }
                        if let keepalive = profile.persistentKeepaliveValue {
                            detailRow(title: "Persistent Keepalive", value: "\(keepalive)s")
                        }
                    }
                    .listRowBackground(Color(white: 0.12))

                    // Keys
                    Section(header: Text("CRYPTOGRAPHIC KEYS").font(.system(size: 12, weight: .bold)).foregroundColor(.secondary)) {
                        detailRow(title: "Server Public Key", value: profile.serverPublicKey, canCopy: true)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Client Private Key")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)

                                Text(isRevealingPrivateKey ? profile.clientPrivateKey : "••••••••••••••••••••••••••••••••")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button(action: { isRevealingPrivateKey.toggle() }) {
                                Image(systemName: isRevealingPrivateKey ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let psk = profile.presharedKey {
                            detailRow(title: "Preshared Key", value: psk, canCopy: true)
                        }
                    }
                    .listRowBackground(Color(white: 0.12))

                    // AmneziaWG Obfuscation parameters (if applicable)
                    if let awg = profile.awgParameters, awg.hasObfuscation {
                        Section(header: Text("AMNEZIAWG OBFUSCATION (AWG)").font(.system(size: 12, weight: .bold)).foregroundColor(.purple)) {
                            if let jc = awg.jc { detailRow(title: "Junk Packet Count (Jc)", value: "\(jc)") }
                            if let jmin = awg.jmin { detailRow(title: "Junk Min Size (Jmin)", value: "\(jmin)") }
                            if let jmax = awg.jmax { detailRow(title: "Junk Max Size (Jmax)", value: "\(jmax)") }
                            if let s1 = awg.s1 { detailRow(title: "Init Junk Size (S1)", value: "\(s1)") }
                            if let s2 = awg.s2 { detailRow(title: "Response Junk Size (S2)", value: "\(s2)") }
                            if let s3 = awg.s3 { detailRow(title: "Cookie Reply Junk Size (S3)", value: "\(s3)") }
                            if let s4 = awg.s4 { detailRow(title: "Transport Junk Size (S4)", value: "\(s4)") }
                            if let h1 = awg.h1 { detailRow(title: "Init Magic Header (H1)", value: h1) }
                            if let h2 = awg.h2 { detailRow(title: "Response Magic Header (H2)", value: h2) }
                            if let h3 = awg.h3 { detailRow(title: "Underload Magic Header (H3)", value: h3) }
                            if let h4 = awg.h4 { detailRow(title: "Transport Magic Header (H4)", value: h4) }
                            if let i1 = awg.i1 { detailRow(title: "Signature Packet (I1)", value: i1) }
                            if let i2 = awg.i2 { detailRow(title: "Signature Packet (I2)", value: i2) }
                            if let i3 = awg.i3 { detailRow(title: "Signature Packet (I3)", value: i3) }
                            if let i4 = awg.i4 { detailRow(title: "Signature Packet (I4)", value: i4) }
                            if let i5 = awg.i5 { detailRow(title: "Signature Packet (I5)", value: i5) }
                            ForEach(awg.orderedAwg3, id: \.key) { item in
                                detailRow(title: item.key, value: item.value, canCopy: item.key == "HeaderProtectionKey")
                            }
                        }
                        .listRowBackground(Color(white: 0.12))
                    }

                    // Share & Export Actions
                    Section {
                        Button(action: copyVpnUrl) {
                            HStack {
                                Label("Copy vpn:// URL", systemImage: "link")
                                    .foregroundColor(.white)
                                Spacer()
                                if let copiedMessage {
                                    Text(copiedMessage)
                                        .font(.system(size: 12))
                                        .foregroundColor(.green)
                                }
                            }
                        }

                        Button(role: .destructive, action: {
                            appState.deleteProfile(profile)
                            dismiss()
                        }) {
                            Label("Delete Server", systemImage: "trash")
                        }
                    }
                    .listRowBackground(Color(white: 0.12))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Server Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    private func detailRow(title: String, value: String, canCopy: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }

            Spacer()

            if canCopy {
                Button(action: {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = value
                    copiedMessage = "Copied!"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedMessage = nil
                    }
                    #endif
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func copyVpnUrl() {
        do {
            let url = try AmneziaUrlDecoder.encodeToUrl(profile)
            #if canImport(UIKit)
            UIPasteboard.general.string = url
            #endif
            copiedMessage = "Copied URL!"
            HapticFeedback.notification(type: .success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copiedMessage = nil
            }
        } catch {
            copiedMessage = "Failed"
        }
    }
}
