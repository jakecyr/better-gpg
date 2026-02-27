import SwiftUI

struct GPGNotInstalledBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("GPG Not Found")
                    .font(.headline)
                Text("Install GPG to use GPGeze. Run `brew install gnupg` in Terminal, or download GPG Suite from gpgtools.org. Then update the path in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.yellow.opacity(0.4), lineWidth: 1))
    }
}
