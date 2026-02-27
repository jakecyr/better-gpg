import SwiftUI
import UniformTypeIdentifiers

struct FileDropZone: View {
    let label: String
    let systemImage: String
    @Binding var droppedURLs: [URL]
    var onTap: (() -> Void)?

    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
                )

            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        // Use .fileURL drop type so Finder drags are accepted, then load via NSURL
        // (which conforms to NSItemProviderReading — URL alone does not on macOS)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: NSURL.self) { item, _ in
                    guard let url = item as? URL else { return }
                    DispatchQueue.main.async { droppedURLs.append(url) }
                }
            }
            return true
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}
