import SwiftUI

/// Asks the user to confirm a server's host key fingerprint.
struct HostKeyRequest: Identifiable {
    let id = UUID()
    let error: HostKeyError
    let trust: () -> Void
}

struct HostKeySheet: View {
    let request: HostKeyRequest
    @Environment(\.dismiss) private var dismiss

    private var error: HostKeyError { request.error }

    private var title: String {
        switch error.kind {
        case .unknown: return L.hostKeyUnknownTitle
        case .changed: return L.hostKeyChangedTitle
        case .revoked: return L.hostKeyRevokedTitle
        }
    }

    private var symbol: String {
        error.kind == .unknown ? "questionmark.key.filled" : "exclamationmark.shield.fill"
    }

    private var tint: Color {
        error.kind == .unknown ? .accentColor : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.title3.weight(.semibold))
            }

            Text("\(error.host):\(error.port)")
                .font(.callout)
                .foregroundStyle(.secondary)

            switch error.kind {
            case .unknown:
                Text(.init(L.hostKeyUnknownDetail))
                    .fixedSize(horizontal: false, vertical: true)
            case .changed:
                Text(.init(L.hostKeyChangedDetail))
                    .fixedSize(horizontal: false, vertical: true)
            case .revoked:
                Text(.init(L.hostKeyRevokedDetail))
                    .fixedSize(horizontal: false, vertical: true)
            }

            fingerprintBox(label: error.kind == .changed ? L.newFingerprint : L.fingerprint, value: error.fingerprint, tint: tint)

            if error.kind == .changed, !error.knownFingerprints.isEmpty {
                ForEach(Array(error.knownFingerprints.enumerated()), id: \.offset) { _, known in
                    fingerprintBox(label: L.previouslyTrustedFingerprint, value: known, tint: .secondary)
                }
            }

            Text(L.keyAlgorithm(error.algorithm))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(L.nothingSentYet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(L.cancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if error.kind != .revoked {
                    Button(error.kind == .changed ? L.replaceAndTrust : L.trustAndConnect,
                           role: error.kind == .changed ? .destructive : nil) {
                        request.trust()
                        dismiss()
                    }
                    // Deliberately not the default action: accepting should be a
                    // decision, not a reflex press of Return.
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 480)
    }

    private func fingerprintBox(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
