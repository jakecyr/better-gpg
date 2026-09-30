import PDFKit
import Quartz
import SwiftUI

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = document
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: ()) {
        nsView.document = nil
    }
}

struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view: QLPreviewView = QLPreviewView(frame: .zero, style: .normal)
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if (nsView.previewItem as? NSURL) as URL? != url {
            nsView.previewItem = url as NSURL
        }
    }

    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: ()) {
        nsView.previewItem = nil
        nsView.close()
    }
}

struct ImageViewer: View {
    let image: NSImage
    @State private var actualSize = false

    var body: some View {
        Group {
            if actualSize {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                }
            } else {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .onTapGesture(count: 2) { actualSize.toggle() }
        .help("Double-click to switch between fit and actual size")
    }
}
