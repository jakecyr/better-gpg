import SwiftUI
import UniformTypeIdentifiers

struct FileDropZone: View {
    let label: String
    let systemImage: String
    let allowedTypes: [UTType]
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
        .onDrop(of: allowedTypes.isEmpty ? [UTType.item] : allowedTypes, isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var loaded: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true) {
                    loaded.append(url)
                } else if let url = item as? URL {
                    loaded.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            droppedURLs.append(contentsOf: loaded)
        }
        return true
    }
}
