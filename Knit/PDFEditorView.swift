import SwiftUI
import PDFKit

// Alternate PDF editor with draw mode controls
struct PDFEditorView: View {
    let url: URL

    // Local editor state
    @State private var pdfDocument: PDFDocument?
    @State private var isDrawMode: Bool = false
    @State private var selectedColor: Color = .yellow
    
    // Available highlight colors
    let colors: [Color] = [.yellow, .green, .cyan, .orange]
    
    var body: some View {
        VStack(spacing: 0) {
            // Drawing toolbar
            HStack {
                // Switch between scrolling and drawing
                Toggle(isOn: $isDrawMode) {
                    Label(isDrawMode ? "Drawing" : "Scrolling", systemImage: isDrawMode ? "pencil.tip.crop.circle.fill" : "hand.draw.fill")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                .toggleStyle(.button)
                .tint(.blue)
                
                Spacer()
                
                // Show colors while drawing
                if isDrawMode {
                    HStack(spacing: 8) {
                        ForEach(colors, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .zIndex(1)
            
            // PDF canvas
            if let document = pdfDocument {
                PDFKitRepresentable(
                    document: document,
                    isDrawMode: $isDrawMode,
                    selectedColor: $selectedColor,
                    fileURL: url
                )
                .ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Pattern")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Load the selected document
            if let doc = PDFDocument(url: url) {
                self.pdfDocument = doc
            }
        }
    }
}

// UIKit bridge for PDF drawing
struct PDFKitRepresentable: UIViewRepresentable {
    let document: PDFDocument
    @Binding var isDrawMode: Bool
    @Binding var selectedColor: Color
    let fileURL: URL

    func makeUIView(context: Context) -> PDFView {
        // Configure the PDF view
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.backgroundColor = .systemBackground
        pdfView.displayMode = .singlePageContinuous
        pdfView.maxScaleFactor = 4.0
        
        // Attach drawing gestures
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        pdfView.addGestureRecognizer(panGesture)
        
        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        // Toggle scroll behavior for draw mode
        if isDrawMode {
            pdfView.isUserInteractionEnabled = true
            if let scrollView = pdfView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
                scrollView.isScrollEnabled = false
            }
        } else {
            if let scrollView = pdfView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
                scrollView.isScrollEnabled = true
            }
        }
        
        context.coordinator.isDrawMode = isDrawMode
        context.coordinator.selectedColor = UIColor(selectedColor)
        context.coordinator.fileURL = fileURL
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        var pdfView: PDFView?
        var isDrawMode: Bool = false
        var selectedColor: UIColor = .yellow
        var fileURL: URL?
        
        // Track the active drawing stroke
        var currentAnnotation: PDFAnnotation?
        var currentPath: UIBezierPath?

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let pdfView = pdfView, let page = pdfView.currentPage, isDrawMode else { return }
            
            let location = gesture.location(in: pdfView)

            // Convert view points into page coordinates
            let pagePoint = pdfView.convert(location, to: page)

            switch gesture.state {
            case .began:
                // Begin a new stroke
                currentPath = UIBezierPath()
                currentPath?.move(to: pagePoint)
                
                // Create the backing annotation
                let annotation = PDFAnnotation(bounds: page.bounds(for: pdfView.displayBox), forType: .ink, withProperties: nil)
                annotation.color = selectedColor.withAlphaComponent(0.4)
                
                // Style it like a highlighter
                let border = PDFBorder()
                border.lineWidth = 20.0
                border.style = .solid
                annotation.border = border
                
                page.addAnnotation(annotation)
                currentAnnotation = annotation
                
            case .changed:
                guard let path = currentPath, let annotation = currentAnnotation else { return }
                
                // Extend the current stroke
                path.addLine(to: pagePoint)
                
                // Mirror the stroke into the PDF
                annotation.add(path)
                
            case .ended:
                // Persist the edited document
                currentPath = nil
                currentAnnotation = nil
                saveDocument()
                
            default:
                break
            }
        }
        
        func saveDocument() {
            guard let url = fileURL, let doc = pdfView?.document else { return }

            // Write annotations back to disk
            doc.write(to: url)
        }
    }
}
