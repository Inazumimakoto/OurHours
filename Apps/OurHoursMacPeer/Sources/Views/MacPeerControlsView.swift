import OurHoursCore
import SwiftUI

struct MacPeerControlsView: View {
    let model: MacPeerModel

    @State private var pastedURL = ""
    @State private var confirmingUnpair = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pairingPanel
                simulationPanel
            }
            .padding(14)
        }
        .background(.quaternary.opacity(0.35))
        .alert("Unpair this Mac?", isPresented: $confirmingUnpair) {
            Button("Cancel", role: .cancel) {}
            Button("Unpair", role: .destructive) {
                model.unpair()
                pastedURL = ""
            }
        } message: {
            Text("This stops recording with the paired device and removes the local pairing configuration.")
        }
    }

    private var pairingPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                pairingStatus
                Divider()

                if let invite = model.invite {
                    inviteCard(invite)
                } else {
                    Button(action: model.generateInviteBundle) {
                        Label(model.snapshot.isPaired ? "Show Invite QR" : "Generate Invite QR", systemImage: "qrcode")
                    }
                    .buttonStyle(.borderedProminent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Peer Pairing URL")
                        .font(.subheadline.weight(.medium))
                    TextField("ourhours://pair/v1?…", text: $pastedURL)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Peer Pairing URL")
                        .onSubmit(applyPairURL)
                }

                HStack {
                    Button("Apply Pair URL", action: applyPairURL)
                        .disabled(pastedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    Button("Unpair", role: .destructive) {
                        confirmingUnpair = true
                    }
                    .disabled(!model.snapshot.isPaired)
                }

                if let error = model.pairingError {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        } label: {
            Text("Pairing")
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var pairingStatus: some View {
        let config = model.snapshot.pairConfiguration
        return VStack(alignment: .leading, spacing: 7) {
            MacPeerBadge(
                title: model.snapshot.isPaired ? "Paired" : "Unpaired",
                color: model.snapshot.isPaired ? .green : .secondary,
                icon: model.snapshot.isPaired ? "link" : "link.badge.plus"
            )
            Text("Pair ID")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(config?.pairID.uuidString ?? "—")
                .font(.caption.monospaced())
                .textSelection(.enabled)

            HStack(spacing: 20) {
                LabeledContent("Local Role", value: config?.localRole.shortCode ?? "—")
                LabeledContent("Key Epoch", value: config.map { String($0.keyEpoch) } ?? "—")
            }
            .font(.callout)
        }
    }

    private func inviteCard(_ invite: MacPeerModel.Invite) -> some View {
        VStack(spacing: 8) {
            Image(invite.qrImage, scale: 1, orientation: .up, label: Text("OurHours pairing QR code"))
                .interpolation(.none)
                .resizable()
                .frame(width: 236, height: 236)
                .padding(24)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.primary.opacity(0.12))
                }

            HStack {
                Button(action: model.copyInviteURL) {
                    Label(model.didCopyInvite ? "Copied" : "Copy URL", systemImage: model.didCopyInvite ? "checkmark" : "doc.on.doc")
                }
                Spacer()
                Button("Hide QR", action: model.hideInvite)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var simulationPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Auto-recording", isOn: Binding(
                    get: { model.snapshot.isAutoRecordingEnabled },
                    set: { model.setAutoRecordingEnabled($0) }
                ))
                Toggle("Advertising override", isOn: Binding(
                    get: { model.snapshot.advertisingOverrideEnabled },
                    set: { model.setAdvertisingOverride($0) }
                ))
                Toggle("Scanning override", isOn: Binding(
                    get: { model.snapshot.scanningOverrideEnabled },
                    set: { model.setScanningOverride($0) }
                ))

                Divider()

                Button("Simulate Disconnect（バイバイ模擬）", action: model.simulateDisconnect)
                Button("Simulate Engine Restart（再起動模擬）", action: model.simulateEngineRestart)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } label: {
            Text("Simulation Controls")
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func applyPairURL() {
        if model.applyPastedPairingURL(pastedURL) {
            pastedURL = ""
        }
    }
}
