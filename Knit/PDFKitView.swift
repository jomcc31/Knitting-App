import SwiftUI
import PDFKit

// Basic PDF wrapper for SwiftUI
struct PDFKitView: UIViewRepresentable {
    let url: URL

    // Expose the loaded document to the parent
    @Binding var document: PDFDocument?

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.backgroundColor = .systemGroupedBackground

        // Keep gestures active for annotations
        pdfView.isUserInteractionEnabled = true
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        // Load once to preserve scroll state
        if pdfView.document == nil {
            if let doc = PDFDocument(url: url) {
                pdfView.document = doc

                // Return the live document reference
                DispatchQueue.main.async {
                    self.document = doc
                }
            }
        }
    }
}
