import SwiftUI

/// Shown when decryption fails because the user doesn't have a matching secret key.
/// Displays who encrypted the file and whose keys are included.
struct DecryptionFailedView: View {
    let items: [(URL, EncryptionInfo)]
    let appState: AppState
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cannot Decrypt")
                        .font(.headline)
                    Text("Your key is not included in these files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { onDismiss?() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        EncryptionInfoPanel(fileURL: item.0, info: item.1, appState: appState, showDoneButton: false)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 420, minHeight: 400)
    }
}
