import SwiftUI

struct DropReviewSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State var items: [IncomingFile]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("These files need different actions")
                .font(.title2.bold())
            Text("BetterGPG will import keys, encrypt ordinary files, and open encrypted files.")
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        FileChip(url: item.url, detail: item.actionTitle) {
                            items.removeAll { $0.id == item.id }
                        }
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Continue") {
                    let chosen = items
                    dismiss()
                    appState.continueReview(chosen)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(items.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
    }
}
