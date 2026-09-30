import SwiftUI
import UniformTypeIdentifiers

enum FileDrop {
    static func load(_ providers: [NSItemProvider]) async -> [URL] {
        await withTaskGroup(of: URL?.self) { group in
            for provider in providers {
                group.addTask {
                    guard provider.canLoadObject(ofClass: NSURL.self) else { return nil }
                    return await withCheckedContinuation { continuation in
                        provider.loadObject(ofClass: NSURL.self) { object, _ in
                            continuation.resume(returning: object as? URL)
                        }
                    }
                }
            }
            var urls: [URL] = []
            for await url in group {
                if let url { urls.append(url) }
            }
            return urls
        }
    }
}

struct FileDropZone: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var onURLs: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
                )

            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 180)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                let urls = await FileDrop.load(providers)
                guard !urls.isEmpty else { return }
                onURLs(urls)
            }
            return true
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}

struct FileGlyph: View {
    let url: URL
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: size, height: size)
    }
}

struct FileChip: View {
    let url: URL
    var detail: String?
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            FileGlyph(url: url, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
