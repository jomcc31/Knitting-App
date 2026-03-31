import SwiftUI
import Charts
import PDFKit
import UniformTypeIdentifiers
import ActivityKit

// Root project screen with counter and pattern tabs
struct RowCounterView: View {
    @Binding var project: KnittingProject
    @AppStorage("appTheme") private var selectedTheme: AppTheme = .teal
    var primaryColor: Color { selectedTheme.color }
    
    // Local navigation state
    @State private var selectedTab = 0
    @State private var isLiveCounterActive = false
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Counter tools
            CounterMainView(project: $project, primaryColor: primaryColor)
                .tabItem { Label("Counter", systemImage: "123.rectangle") }
                .tag(0)
            
            // Pattern viewer and drawing tools
            PatternTabView(project: $project, primaryColor: primaryColor)
                .tabItem { Label("Pattern", systemImage: "doc.text.image") }
                .tag(1)
        }
        .tint(primaryColor)
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.body.weight(.semibold))
                    }
                    .foregroundColor(primaryColor)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if ProjectCounterLiveActivityManager.areActivitiesEnabled {
                    Button(action: toggleLiveCounter) {
                        ZStack {
                            Circle()
                                .fill(isLiveCounterActive ? primaryColor : Color.clear)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                )
                                .frame(width: 32, height: 32)

                            Image(systemName: "apps.iphone")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isLiveCounterActive ? Color(UIColor.darkText) : primaryColor)
                        }
                    }
                    .accessibilityLabel(isLiveCounterActive ? "Stop lock screen counter" : "Start lock screen counter")
                }
            }
        }
        .onAppear(perform: refreshLiveCounterState)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshLiveCounterState()
        }
    }

    // Start or stop the lock screen counter for this project
    private func toggleLiveCounter() {
        Task {
            if isLiveCounterActive {
                await ProjectCounterLiveActivityManager.end(for: project.id)
            } else {
                _ = await ProjectCounterLiveActivityManager.start(for: project)
            }

            await MainActor.run {
                refreshLiveCounterState()
            }
        }
    }

    // Refresh the toolbar state for the current project
    private func refreshLiveCounterState() {
        isLiveCounterActive = ProjectCounterLiveActivityManager.isActive(for: project.id) || ProjectStore.isLiveActivityActive(for: project.id)
    }
}

// Counter tab with notes and project stats
struct CounterMainView: View {
    @Binding var project: KnittingProject
    let primaryColor: Color
    
    // Counter UI state
    @State private var selectedMode: CounterMode = .rows
    @State private var showResetAlert = false
    @State private var showIntervalAlert = false
    @State private var intervalInput = ""
    @FocusState private var isNotesFocused: Bool
    @State private var statsRange: TimeRange = .week
    @State private var rawSelectedDate: Date?
    
    // Counter display modes
    enum CounterMode: String, CaseIterable { case rows = "Rows"; case repeats = "Repeats" }

    // Supported history windows
    enum TimeRange: String, CaseIterable { case week = "Week"; case month = "Month"; case year = "Year" }
    let secondaryColor = Color.gray.opacity(0.2)

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                counterCard
                notesCard
                statsCard
                Spacer()
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .alert("Reset \(selectedMode.rawValue)?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) { resetCurrentMode() }
        } message: { Text("This will reset your \(selectedMode.rawValue.lowercased()) to 0.") }
        .alert("Set Pattern Interval", isPresented: $showIntervalAlert) {
            TextField("Number of rows", text: $intervalInput).keyboardType(.numberPad)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let newInterval = Int(intervalInput), newInterval > 0 {
                    project.rowsPerRepeat = newInterval
                    if project.currentRepeatRow > newInterval { project.currentRepeatRow = newInterval }
                    syncLiveActivity()
                }
            }
        }
    }

    // Main counter controls
    var counterCard: some View {
        VStack(spacing: 20) {
            // Toggle between row and repeat counting
            Picker("Mode", selection: $selectedMode) {
                ForEach(CounterMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
            }.pickerStyle(.segmented).padding(.horizontal, 5)
            Divider().padding(.horizontal, 10)
            HStack {
                // Increment and decrement controls
                HStack(spacing: 15) {
                    Button(action: decrement) {
                        Image(systemName: "minus").font(.system(size: 24, weight: .bold)).foregroundColor(.primary)
                            .frame(width: 55, height: 55).background(secondaryColor).clipShape(Circle())
                    }
                    .disabled(selectedMode == .rows ? project.totalRows == 0 : (project.currentRepeatRow == 0 && project.completedRepeats == 0))
                    Button(action: increment) {
                        Image(systemName: "plus").font(.system(size: 32, weight: .bold)).foregroundColor(.white)
                            .frame(width: 75, height: 75).background(LinearGradient(colors: [primaryColor, primaryColor.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(Circle()).shadow(color: primaryColor.opacity(0.4), radius: 8, x: 0, y: 5)
                    }
                }
                Spacer()
                ZStack(alignment: .trailing) {
                    if selectedMode == .rows { rowModeDisplay } else { repeatModeDisplay }
                }.animation(.spring(), value: selectedMode)
            }

            // Repeat progress indicator
            if selectedMode == .repeats && project.rowsPerRepeat > 0 { visualizerView }
            Divider().padding(.horizontal, 10)
            HStack {
                // Time since last update and reset action
                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill").foregroundColor(primaryColor)
                        Text("Since last:")
                        Text(timeString(currentDate: context.date))
                    }.font(.caption).fontWeight(.medium).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { showResetAlert = true }) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                        .frame(width: 36, height: 36).background(Color.red.opacity(0.9)).clipShape(Circle())
                        .shadow(color: Color.red.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
        }.padding(25).background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(24).shadow(color: Color.black.opacity(0.06), radius: 15, x: 0, y: 5).padding(.horizontal).padding(.top, 20)
    }
    
    // Editable project notes
    var notesCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "note.text").foregroundColor(primaryColor)
                Text("NOTES").font(.caption).fontWeight(.bold).foregroundColor(.secondary).kerning(1)
                Spacer()
                if isNotesFocused { Button("Done") { isNotesFocused = false }.font(.caption).fontWeight(.bold).foregroundColor(.blue) }
            }
            ZStack(alignment: .topLeading) {
                if project.notes.isEmpty && !isNotesFocused { Text("Tap to add instructions...").foregroundColor(.gray.opacity(0.6)).padding(.top, 8).padding(.leading, 5) }
                TextEditor(text: $project.notes).frame(minHeight: 120).scrollContentBackground(.hidden).focused($isNotesFocused)
            }
        }.padding(25).background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(24).shadow(color: Color.black.opacity(0.06), radius: 15, x: 0, y: 5).padding(.horizontal)
    }
    
    // Project history chart
    var statsCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "chart.bar.xaxis").foregroundColor(primaryColor)
                Text("HISTORY").font(.caption).fontWeight(.bold).foregroundColor(.secondary).kerning(1)
                Spacer()
                Picker("Range", selection: $statsRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in Text(range.rawValue).tag(range) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
            }
            let data = getChartData(for: statsRange)
            Chart {
                ForEach(data, id: \.date) { item in
                    BarMark(x: .value("Time", item.date, unit: statsRange == .year ? .month : .day), y: .value("Rows", item.count))
                        .foregroundStyle(primaryColor.gradient).cornerRadius(4)
                }
                if let selectedDate = rawSelectedDate {
                    if let item = findClosestData(to: selectedDate, in: data) {
                        RuleMark(x: .value("Selected", item.date, unit: statsRange == .year ? .month : .day))
                            .foregroundStyle(Color.gray.opacity(0.3))
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .fit)) {
                                VStack(spacing: 2) {
                                    Text("\(item.count) rows").font(.caption).fontWeight(.bold).foregroundColor(.primary)
                                    Text(item.fullDate).font(.caption2).foregroundColor(.secondary)
                                }.padding(8).background(Color(UIColor.systemBackground)).cornerRadius(8).shadow(radius: 4)
                            }
                    }
                }
            }
            .chartXSelection(value: $rawSelectedDate)
            .frame(height: 200)
            .chartXAxis {
                switch statsRange {
                case .week: AxisMarks(values: .stride(by: .day)) { value in AxisGridLine(); AxisTick(); if let date = value.as(Date.self) { AxisValueLabel { Text(formatAxisDate(date)) } } }
                case .month: AxisMarks(values: .automatic) { value in AxisGridLine(); AxisTick(); if let date = value.as(Date.self) { AxisValueLabel { Text(formatAxisDate(date)) } } }
                case .year: AxisMarks(values: .stride(by: .month)) { value in AxisGridLine(); AxisTick(); if let date = value.as(Date.self) { AxisValueLabel { Text(formatAxisDate(date)) } } }
                }
            }
        }.padding(25).background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(24).shadow(color: Color.black.opacity(0.06), radius: 15, x: 0, y: 5).padding(.horizontal)
    }

    // Total row readout
    var rowModeDisplay: some View {
        VStack(alignment: .trailing, spacing: -5) {
            Text("TOTAL ROWS").font(.caption).fontWeight(.bold).foregroundColor(.secondary).kerning(1)
            Text("\(project.totalRows)").font(.system(size: 80, weight: .bold, design: .rounded)).foregroundColor(primaryColor)
                .contentTransition(.numericText(value: Double(project.totalRows))).lineLimit(1).minimumScaleFactor(0.5)
        }
    }
    
    // Repeat progress readout
    var repeatModeDisplay: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Button(action: { intervalInput = String(project.rowsPerRepeat); showIntervalAlert = true }) {
                HStack(spacing: 4) { Text("Rows per Repeat: \(project.rowsPerRepeat)") }.font(.caption).foregroundColor(primaryColor).padding(.vertical, 4).padding(.horizontal, 8).background(primaryColor.opacity(0.1)).cornerRadius(8)
            }.padding(.bottom, 5)
            Text("\(project.completedRepeats)").font(.system(size: 60, weight: .bold, design: .rounded)).foregroundColor(primaryColor).contentTransition(.numericText(value: Double(project.completedRepeats)))
            Text("FULL REPEATS").font(.system(size: 10, weight: .bold)).foregroundColor(primaryColor.opacity(0.8))
        }
    }
    
    // Visual repeat tracker
    var visualizerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PATTERN PROGRESS").font(.caption).fontWeight(.bold).foregroundColor(.secondary).kerning(1)
                Spacer()
                Text("\(project.currentRepeatRow) / \(project.rowsPerRepeat)").font(.caption).monospacedDigit().foregroundColor(.secondary)
            }
            let maxVisualBlocks = 50
            let totalBlocks = min(project.rowsPerRepeat, maxVisualBlocks)
            let filledBlocks = (project.rowsPerRepeat <= maxVisualBlocks) ? project.currentRepeatRow : Int((Double(project.currentRepeatRow) / Double(project.rowsPerRepeat)) * Double(maxVisualBlocks))
            HStack(spacing: 2) {
                ForEach(1...totalBlocks, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 2).fill(step <= filledBlocks ? primaryColor : secondaryColor).frame(height: 24).frame(maxWidth: .infinity).animation(.easeInOut(duration: 0.2), value: project.currentRepeatRow)
                }
            }
        }.padding(.vertical, 5)
    }

    // Advance the active counter mode
    func increment() {
        triggerHaptic(style: .medium)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            ProjectCounterMutation.apply(action: .increment, mode: liveCounterMode, to: &project)
        }
        syncLiveActivity()
    }

    // Reverse the active counter mode
    func decrement() {
        triggerHaptic(style: .light)
        withAnimation {
            ProjectCounterMutation.apply(action: .decrement, mode: liveCounterMode, to: &project)
        }
        syncLiveActivity()
    }

    // Reset the selected counter mode
    func resetCurrentMode() {
        let generator = UINotificationFeedbackGenerator(); generator.notificationOccurred(.success); project.lastUpdated = Date()
        withAnimation { if selectedMode == .rows { project.totalRows = 0 } else { project.currentRepeatRow = 0; project.completedRepeats = 0 } }
        syncLiveActivity()
    }

    // Format elapsed time since the last update
    func timeString(currentDate: Date) -> String {
        let diff = currentDate.timeIntervalSince(project.lastUpdated)
        let seconds = Int(diff)
        if seconds < 60 { return "\(seconds) second\(seconds == 1 ? "" : "s")" }
        else if seconds < 3600 { let m = seconds/60; return "\(m) minute\(m == 1 ? "" : "s")" }
        else if seconds < 86400 { let h = seconds/3600; return "\(h) hour\(h == 1 ? "" : "s")" }
        else { let d = seconds/86400; return "\(d) day\(d == 1 ? "" : "s")" }
    }

    // Trigger counter haptics
    func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style); generator.impactOccurred()
    }

    // Convert the local picker mode into the shared live activity mode
    var liveCounterMode: ProjectCounterMode {
        selectedMode == .rows ? .rows : .repeats
    }

    // Push updated project values into the live activity
    func syncLiveActivity() {
        Task {
            await ProjectCounterLiveActivityManager.update(for: project, mode: liveCounterMode)
        }
    }
    
    // Chart point model
    struct ChartData { let date: Date; let count: Int; let fullDate: String }
    
    // Build chart data for the selected range
    func getChartData(for range: TimeRange) -> [ChartData] {
        var data: [ChartData] = []
        let calendar = Calendar.current
        switch range {
        case .week:
            for i in (0..<7).reversed() { if let date = calendar.date(byAdding: .day, value: -i, to: Date()) { let key = KnittingProject.dateKey(for: date); let fullFmt = DateFormatter(); fullFmt.dateStyle = .medium; data.append(ChartData(date: date, count: project.history[key] ?? 0, fullDate: fullFmt.string(from: date))) } }
        case .month:
            for i in (0..<30).reversed() { if let date = calendar.date(byAdding: .day, value: -i, to: Date()) { let key = KnittingProject.dateKey(for: date); let fullFmt = DateFormatter(); fullFmt.dateStyle = .medium; data.append(ChartData(date: date, count: project.history[key] ?? 0, fullDate: fullFmt.string(from: date))) } }
        case .year:
            for i in (0..<12).reversed() { if let date = calendar.date(byAdding: .month, value: -i, to: Date()) { let monthFormatter = DateFormatter(); monthFormatter.dateFormat = "yyyy-MM"; let monthKey = monthFormatter.string(from: date); let total = project.history.filter { $0.key.starts(with: monthKey) }.reduce(0) { $0 + $1.value }; let fullFmt = DateFormatter(); fullFmt.dateFormat = "MMMM yyyy"; data.append(ChartData(date: date, count: total, fullDate: fullFmt.string(from: date))) } }
        }
        return data
    }

    // Match a tapped date to the nearest bar
    func findClosestData(to date: Date, in data: [ChartData]) -> ChartData? { return data.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) }

    // Format x-axis labels by range
    func formatAxisDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch statsRange { case .week: formatter.dateFormat = "EEE"; case .month: formatter.dateFormat = "d"; case .year: formatter.dateFormat = "MMM" }
        return formatter.string(from: date)
    }
}

// Pattern tab with import and drawing tools
struct PatternTabView: View {
    @Binding var project: KnittingProject
    let primaryColor: Color
    
    // Pattern import state
    @State private var isImportingPDF = false
    @State private var showPDFSourceOptions = false
    
    // Supported drawing modes
    enum DrawingTool: Int { case cursor = 0, highlight = 1, pen = 2, eraser = 3 }
    @State private var currentTool: DrawingTool = .cursor
    @State private var selectedColor: Color = .yellow
    
    // Available annotation colors
    let highlightColors: [Color] = [.yellow, .green, .cyan, .pink, .orange]
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            
            if let pdfURL = getPDFURL() {
                VStack(spacing: 0) {
                    // Annotation toolbar
                    HStack(spacing: 12) {
                        Button(action: { currentTool = .cursor }) {
                            toolbarImage("hand.draw", isSelected: currentTool == .cursor)
                        }
                        
                        Button(action: { currentTool = .pen }) {
                            toolbarImage("pencil", isSelected: currentTool == .pen)
                        }
                        
                        Button(action: { currentTool = .highlight }) {
                            toolbarImage("highlighter", isSelected: currentTool == .highlight)
                        }
                        
                        Button(action: { currentTool = .eraser }) {
                            toolbarImage("eraser.line.dashed", isSelected: currentTool == .eraser)
                        }
                        
                        if currentTool == .highlight || currentTool == .pen {
                            HStack(spacing: 10) {
                                Divider().frame(height: 20)
                                ForEach(highlightColors, id: \.self) { color in
                                    Circle()
                                        .fill(color)
                                        .frame(width: 24, height: 24)
                                        .overlay(Circle().stroke(Color.primary, lineWidth: selectedColor == color ? 2 : 0))
                                        .onTapGesture { selectedColor = color }
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                        
                        Spacer()
                        
                        Menu {
                            Button("Replace Pattern") { showPDFSourceOptions = true }
                            Button("Remove Pattern", role: .destructive, action: deletePDF)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundColor(primaryColor)
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .animation(.easeInOut(duration: 0.2), value: currentTool)
                    
                    // Interactive PDF viewer
                    PDFCustomDrawView(
                        url: pdfURL,
                        currentTool: $currentTool,
                        selectedColor: $selectedColor
                    )
                    .ignoresSafeArea(edges: .bottom)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "doc.viewfinder").font(.system(size: 60)).foregroundColor(.secondary)
                    Text("No Pattern Loaded").font(.title2).fontWeight(.bold)
                    Text("Import a PDF to view and highlight your pattern right next to your counters.")
                        .multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal, 40)
                    Button(action: { showPDFSourceOptions = true }) {
                        Text("Add Pattern").font(.headline).foregroundColor(.white).padding().frame(width: 200).background(primaryColor).cornerRadius(12)
                    }
                }
            }
        }
        .confirmationDialog("Add Pattern", isPresented: $showPDFSourceOptions) {
            // Pattern source actions
            Button("Import from Files") { isImportingPDF = true }
            Button("Generate Sample PDF (Debug)") { generateSamplePDF() }
            Button("Cancel", role: .cancel) { }
        }
        .fileImporter(
            isPresented: $isImportingPDF, allowedContentTypes: [.pdf], allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls): if let sourceUrl = urls.first { savePDF(from: sourceUrl) }
            case .failure(let error): print("Error importing: \(error.localizedDescription)")
            }
        }
    }
    
    // Style a toolbar button for the current tool
    func toolbarImage(_ systemName: String, isSelected: Bool) -> some View {
        Image(systemName: systemName).font(.title3).padding(8)
            .background(isSelected ? primaryColor.opacity(0.2) : Color.clear)
            .foregroundColor(isSelected ? primaryColor : .secondary).cornerRadius(8)
    }
    
    // Resolve the saved PDF location
    func getPDFURL() -> URL? {
        guard let fileName = project.pdfFileName else { return nil }
        let fileManager = FileManager.default
        let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileUrl = docsURL.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: fileUrl.path) { return fileUrl }
        return nil
    }
    
    // Copy an imported PDF into app storage
    func savePDF(from sourceUrl: URL) {
        guard sourceUrl.startAccessingSecurityScopedResource() else { return }
        defer { sourceUrl.stopAccessingSecurityScopedResource() }
        do {
            let fileManager = FileManager.default
            let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileName = "\(project.id.uuidString).pdf"
            let destinationURL = docsURL.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: destinationURL.path) { try fileManager.removeItem(at: destinationURL) }
            try fileManager.copyItem(at: sourceUrl, to: destinationURL)
            project.pdfFileName = fileName
        } catch { print("Failed to save: \(error.localizedDescription)") }
    }
    
    // Remove the saved PDF from disk
    func deletePDF() {
        guard let fileName = project.pdfFileName else { return }
        let fileManager = FileManager.default
        let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docsURL.appendingPathComponent(fileName)
        do {
            if fileManager.fileExists(atPath: fileURL.path) { try fileManager.removeItem(at: fileURL) }
            project.pdfFileName = nil
        } catch { print("Error deleting: \(error)") }
    }
    
    // Generate a sample pattern for testing
    func generateSamplePDF() {
        let format = UIGraphicsPDFRendererFormat()
        let metaData = [kCGPDFContextCreator: "Knitting App", kCGPDFContextAuthor: "Simulator"]
        format.documentInfo = metaData as [String: Any]
        let pageRect = CGRect(x: 0, y: 0, width: 8.5 * 72.0, height: 11 * 72.0)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let data = renderer.pdfData { (context) in
            context.beginPage()
            let title = "Sample Pattern"
            title.draw(at: CGPoint(x: 50, y: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 30, weight: .bold)])
            let body = "Row 1: Knit across.\nRow 2: Purl across.\nRow 3: *Knit 2, Purl 2* repeat to end.\nRow 4: *Purl 2, Knit 2* repeat to end.\n\nUse the pen to write notes, and the highlighter to track rows!"
            body.draw(in: CGRect(x: 50, y: 120, width: 500, height: 500), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "\(project.id.uuidString).pdf"
        let destinationURL = docsURL.appendingPathComponent(fileName)
        do {
            try data.write(to: destinationURL)
            project.pdfFileName = fileName
        } catch { print("Error generating: \(error)") }
    }
}

// PDFView bridge with live drawing support
struct PDFCustomDrawView: UIViewRepresentable {
    let url: URL
    @Binding var currentTool: PatternTabView.DrawingTool
    @Binding var selectedColor: Color

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIView(context: Context) -> PDFView {
        // Configure the PDF view and gestures
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = .systemGroupedBackground
        
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        pdfView.addGestureRecognizer(panGesture)
        
        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        // Sync tool state into UIKit
        context.coordinator.currentTool = currentTool
        context.coordinator.selectedColor = selectedColor
        
        let isDrawing = (currentTool != .cursor)
        
        if let scrollView = pdfView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
            scrollView.isScrollEnabled = !isDrawing
            scrollView.bounces = true
            scrollView.alwaysBounceVertical = true
        }
    }
    
    class Coordinator: NSObject {
        let fileURL: URL
        weak var pdfView: PDFView?
        weak var activePage: PDFPage?
        
        // Active drawing state
        var currentTool: PatternTabView.DrawingTool = .cursor
        var selectedColor: Color = .yellow
        
        // Track live and saved stroke paths
        var viewPath: UIBezierPath?
        var pagePath: UIBezierPath?
        var liveShapeLayer: CAShapeLayer?
        
        init(url: URL) {
            self.fileURL = url
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let pdfView = pdfView, currentTool != .cursor else { return }
            
            let location = gesture.location(in: pdfView)
            guard let page = pdfView.page(for: location, nearest: true) else { return }
            let pagePoint = pdfView.convert(location, to: page)

            // Erase matching ink annotations
            if currentTool == .eraser {
                if gesture.state == .began || gesture.state == .changed {
                    let hitTestRadius: CGFloat = 15.0
                    
                    for annotation in page.annotations.reversed() {
                        if annotation.type == PDFAnnotationSubtype.ink.rawValue || annotation.type == "Ink" {
                            if let paths = annotation.paths {
                                var hit = false
                                for path in paths {
                                    let strokedPath = path.cgPath.copy(strokingWithWidth: hitTestRadius * 2, lineCap: .round, lineJoin: .round, miterLimit: 0)
                                    if strokedPath.contains(pagePoint) {
                                        hit = true
                                        break
                                    }
                                }
                                if hit {
                                    page.removeAnnotation(annotation)
                                    pdfView.document?.write(to: fileURL)
                                    break
                                }
                            }
                        }
                    }
                }
                return
            }
            
            // Draw pen and highlighter strokes
            switch gesture.state {
            case .began:
                beginStroke(at: location, pagePoint: pagePoint, on: page, in: pdfView)
                
            case .changed:
                if activePage !== page {
                    finalizeStroke(in: pdfView)
                    beginStroke(at: location, pagePoint: pagePoint, on: page, in: pdfView)
                } else {
                    // Update the live stroke preview
                    viewPath?.addLine(to: location)
                    pagePath?.addLine(to: pagePoint)
                    liveShapeLayer?.path = viewPath?.cgPath
                }
                
            case .ended, .cancelled:
                finalizeStroke(in: pdfView)
                
            default:
                break
            }
        }

        // Start a new stroke on the current page
        private func beginStroke(at location: CGPoint, pagePoint: CGPoint, on page: PDFPage, in pdfView: PDFView) {
            activePage = page

            viewPath = UIBezierPath()
            viewPath?.move(to: location)

            pagePath = UIBezierPath()
            pagePath?.move(to: pagePoint)

            liveShapeLayer?.removeFromSuperlayer()
            liveShapeLayer = CAShapeLayer()
            liveShapeLayer?.frame = pdfView.bounds
            liveShapeLayer?.fillColor = UIColor.clear.cgColor

            let isHighlight = (currentTool == .highlight)
            liveShapeLayer?.strokeColor = UIColor(selectedColor).withAlphaComponent(isHighlight ? 0.4 : 1.0).cgColor
            liveShapeLayer?.lineWidth = isHighlight ? 25.0 : 4.0
            liveShapeLayer?.lineCap = .round
            liveShapeLayer?.lineJoin = .round

            if let liveShapeLayer {
                pdfView.layer.addSublayer(liveShapeLayer)
            }
        }

        // Commit the active stroke to its original page
        private func finalizeStroke(in pdfView: PDFView) {
            defer {
                liveShapeLayer?.removeFromSuperlayer()
                liveShapeLayer = nil
                viewPath = nil
                pagePath = nil
                activePage = nil
            }

            guard let activePage, let path = pagePath else { return }

            let bounds = activePage.bounds(for: pdfView.displayBox)
            let annotation: PDFAnnotation

            if currentTool == .highlight {
                annotation = TrueHighlighterAnnotation(bounds: bounds, color: UIColor(selectedColor))
            } else {
                annotation = OpaquePenAnnotation(bounds: bounds, color: UIColor(selectedColor))
            }

            annotation.add(path)
            activePage.addAnnotation(annotation)
            pdfView.document?.write(to: fileURL)
        }
    }
}

// Highlighter annotation that darkens the page beneath it
class TrueHighlighterAnnotation: PDFAnnotation {
    init(bounds: CGRect, color: UIColor) {
        super.init(bounds: bounds, forType: PDFAnnotationSubtype.ink, withProperties: nil)
        self.color = color.withAlphaComponent(0.4)
        
        let border = PDFBorder()
        border.lineWidth = 25.0
        self.border = border
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        UIGraphicsPushContext(context)
        context.saveGState()
        context.setBlendMode(.multiply)
        
        if let paths = self.paths {
            context.setStrokeColor(self.color.cgColor)
            context.setLineWidth(25.0)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            for path in paths {
                context.addPath(path.cgPath)
                context.strokePath()
            }
        }
        
        context.restoreGState()
        UIGraphicsPopContext()
    }
}

// Pen annotation for solid freehand notes
class OpaquePenAnnotation: PDFAnnotation {
    init(bounds: CGRect, color: UIColor) {
        super.init(bounds: bounds, forType: PDFAnnotationSubtype.ink, withProperties: nil)
        self.color = color.withAlphaComponent(1.0)
        
        let border = PDFBorder()
        border.lineWidth = 4.0
        self.border = border
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        UIGraphicsPushContext(context)
        context.saveGState()
        context.setBlendMode(.normal)
        
        if let paths = self.paths {
            context.setStrokeColor(self.color.cgColor)
            context.setLineWidth(4.0)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            for path in paths {
                context.addPath(path.cgPath)
                context.strokePath()
            }
        }
        
        context.restoreGState()
        UIGraphicsPopContext()
    }
}

// Preview the project workspace
#Preview {
    NavigationStack {
        RowCounterView(project: .constant(KnittingProject(title: "My Scarf")))
    }
}
