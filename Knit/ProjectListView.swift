import SwiftUI
import Charts

// Project hub with creation, navigation, and app-wide stats
struct ProjectListView: View {
    // Stored project list
    @State private var projects: [KnittingProject] = []
    
    // View presentation state
    @AppStorage("appTheme") private var selectedTheme: AppTheme = .teal
    @State private var isShowingSettings = false
    @State private var isShowingGlobalStats = false
    @State private var isShowingNewProjectAlert = false
    @State private var newProjectName = ""
    @State private var isShowingRenameAlert = false
    @State private var projectToRenameID: UUID?
    @State private var renameText = ""
    @State private var isShowingDeleteAlert = false
    @State private var projectToDeleteID: UUID?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                // Empty and populated project states
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                if projects.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "basket").font(.system(size: 60)).foregroundColor(.gray)
                        Text("No Projects Yet").font(.headline).foregroundColor(.secondary)
                        Text("Tap + to start knitting").font(.subheadline).foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach($projects) { $project in
                            ZStack {
                                NavigationLink(destination: RowCounterView(project: $project)) { EmptyView() }.opacity(0)
                                ProjectCardView(project: project, onRename: { prepareRename(project: project) }, onDelete: { prepareDelete(project: project) })
                            }
                            .listRowSeparator(.hidden).listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                // App actions
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { isShowingSettings = true }) { Image(systemName: "gearshape").foregroundColor(selectedTheme.color) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { isShowingGlobalStats = true }) { Image(systemName: "chart.bar.xaxis").foregroundColor(selectedTheme.color) }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { isShowingNewProjectAlert = true }) { Image(systemName: "plus").fontWeight(.bold).foregroundColor(selectedTheme.color) }
                }
            }
            .sheet(isPresented: $isShowingSettings) { SettingsView() }
            .sheet(isPresented: $isShowingGlobalStats) { GlobalStatsView(projects: projects, themeColor: selectedTheme.color) }
            .alert("New Project", isPresented: $isShowingNewProjectAlert) {
                TextField("Project Name", text: $newProjectName)
                Button("Cancel", role: .cancel) { newProjectName = "" }
                Button("Create") { addNewProject() }
            }
            .alert("Rename Project", isPresented: $isShowingRenameAlert) {
                TextField("New Name", text: $renameText)
                Button("Cancel", role: .cancel) { projectToRenameID = nil; renameText = "" }
                Button("Save") { saveRename() }
            }
            .alert("Delete Project?", isPresented: $isShowingDeleteAlert) {
                Button("Cancel", role: .cancel) { projectToDeleteID = nil }
                Button("Delete", role: .destructive) { confirmDelete() }
            } message: { Text("This action cannot be undone.") }
        }
        .tint(selectedTheme.color)
        
        // Keep projects synced with local storage
        .onAppear {
            loadProjects()
        }
        .onChange(of: projects) { _ in
            saveProjects()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            loadProjects()
        }
    }
    
    // Persist the current project list
    func saveProjects() {
        ProjectStore.saveProjects(projects)
    }
    
    // Restore saved projects or seed starter data
    func loadProjects() {
        if let decodedProjects = ProjectStore.loadProjects() {
            projects = decodedProjects
        } else {
            projects = [
                KnittingProject(title: "My First Scarf"),
                KnittingProject(title: "Winter Hat")
            ]
            saveProjects()
        }
    }

    // Create a new project
    func addNewProject() {
        guard !newProjectName.isEmpty else { return }
        let newProject = KnittingProject(title: newProjectName)
        withAnimation { projects.append(newProject) }
        newProjectName = ""
    }

    // Prepare rename state
    func prepareRename(project: KnittingProject) { projectToRenameID = project.id; renameText = project.title; isShowingRenameAlert = true }

    // Apply the current rename
    func saveRename() {
        guard let id = projectToRenameID else { return }
        if let index = projects.firstIndex(where: { $0.id == id }) { projects[index].title = renameText }
        projectToRenameID = nil; renameText = ""
    }

    // Prepare delete confirmation
    func prepareDelete(project: KnittingProject) { projectToDeleteID = project.id; isShowingDeleteAlert = true }

    // Remove the selected project
    func confirmDelete() {
        guard let id = projectToDeleteID else { return }
        withAnimation { projects.removeAll(where: { $0.id == id }) }
        projectToDeleteID = nil
    }
}

// Global stats across every project
struct GlobalStatsView: View {
    let projects: [KnittingProject]
    let themeColor: Color
    @Environment(\.dismiss) var dismiss
    
    // Chart and lookup state
    @State private var selectedRange: TimeRange = .week
    @State private var specificDate: Date = Date()
    @State private var rawSelectedDate: Date?
    
    // Supported chart windows
    enum TimeRange: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Range selector
                    Picker("Time Range", selection: $selectedRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in Text(range.rawValue).tag(range) }
                    }.pickerStyle(.segmented).padding(.horizontal)
                    
                    HStack(spacing: 15) {
                        // Top-level totals
                        statCard(title: "Total Projects", value: "\(projects.count)")
                        
                        // Sum all recorded row history
                        let allTimeRows = projects.reduce(0) { projectSum, project in
                            projectSum + project.history.values.reduce(0, +)
                        }
                        statCard(title: "Total Rows (All Time)", value: "\(allTimeRows)")
                    }.padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        // Activity chart
                        Text("\(selectedRange.rawValue.uppercased()) ACTIVITY").font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                        let data = getChartData()
                        
                        Chart {
                            ForEach(data, id: \.date) { item in
                                BarMark(
                                    x: .value("Time", item.date, unit: selectedRange == .year ? .month : .day),
                                    y: .value("Rows", item.count)
                                )
                                .foregroundStyle(themeColor.gradient)
                                .cornerRadius(4)
                            }
                            
                            if let selectedDate = rawSelectedDate {
                                if let item = findClosestData(to: selectedDate, in: data) {
                                    RuleMark(x: .value("Selected", item.date, unit: selectedRange == .year ? .month : .day))
                                        .foregroundStyle(Color.gray.opacity(0.3))
                                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .fit)) {
                                            VStack(spacing: 2) {
                                                Text("\(item.count) rows").font(.caption).fontWeight(.bold).foregroundColor(.primary)
                                                Text(item.fullDate).font(.caption2).foregroundColor(.secondary)
                                            }
                                            .padding(8).background(Color(UIColor.systemBackground)).cornerRadius(8).shadow(radius: 4)
                                        }
                                }
                            }
                        }
                        .chartXSelection(value: $rawSelectedDate)
                        .frame(height: 250)
                        .chartXAxis {
                            switch selectedRange {
                            case .week:
                                AxisMarks(values: .stride(by: .day)) { value in
                                    AxisGridLine()
                                    AxisTick()
                                    if let date = value.as(Date.self) {
                                        AxisValueLabel { Text(formatAxisDate(date)) }
                                    }
                                }
                            case .month:
                                AxisMarks(values: .automatic) { value in
                                    AxisGridLine()
                                    AxisTick()
                                    if let date = value.as(Date.self) {
                                        AxisValueLabel { Text(formatAxisDate(date)) }
                                    }
                                }
                            case .year:
                                AxisMarks(values: .stride(by: .month)) { value in
                                    AxisGridLine()
                                    AxisTick()
                                    if let date = value.as(Date.self) {
                                        AxisValueLabel { Text(formatAxisDate(date)) }
                                    }
                                }
                            }
                        }
                    }
                    .padding().background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(16).padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        // Single-day lookup
                        Text("SPECIFIC DAY LOOKUP").font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                        HStack {
                            DatePicker("Select Date", selection: $specificDate, displayedComponents: .date).labelsHidden()
                            Spacer()
                            let rowsOnDay = getRowsForDate(specificDate)
                            VStack(alignment: .trailing) {
                                Text("\(rowsOnDay)").font(.title2).fontWeight(.bold).foregroundColor(themeColor)
                                    .contentTransition(.numericText(value: Double(rowsOnDay))).animation(.default, value: rowsOnDay)
                                Text("rows").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }.padding().background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(16).padding(.horizontal)
                }.padding(.vertical)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Global Statistics").toolbar { Button("Done") { dismiss() } }
        }
    }
    
    // Reusable stat card
    func statCard(title: String, value: String) -> some View {
        VStack { Text(title).font(.caption).foregroundColor(.secondary); Text(value).font(.title2).fontWeight(.bold).foregroundColor(themeColor) }
            .frame(maxWidth: .infinity).padding().background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(12)
    }
    
    // Chart point model
    struct ChartData { let date: Date; let count: Int; let fullDate: String }

    // Get total rows for a specific date
    func getRowsForDate(_ date: Date) -> Int {
        let key = KnittingProject.dateKey(for: date)
        var total = 0
        for p in projects { total += p.history[key] ?? 0 }
        return total
    }

    // Build chart data for the active range
    func getChartData() -> [ChartData] {
        var data: [ChartData] = []
        let calendar = Calendar.current
        var globalHistory: [String: Int] = [:]
        for project in projects {
            for (dateKey, count) in project.history { globalHistory[dateKey, default: 0] += count }
        }
        switch selectedRange {
        case .week:
            for i in (0..<7).reversed() {
                if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                    let key = KnittingProject.dateKey(for: date)
                    let fullFmt = DateFormatter(); fullFmt.dateStyle = .medium
                    data.append(ChartData(date: date, count: globalHistory[key] ?? 0, fullDate: fullFmt.string(from: date)))
                }
            }
        case .month:
            for i in (0..<30).reversed() {
                if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                    let key = KnittingProject.dateKey(for: date)
                    let fullFmt = DateFormatter(); fullFmt.dateStyle = .medium
                    data.append(ChartData(date: date, count: globalHistory[key] ?? 0, fullDate: fullFmt.string(from: date)))
                }
            }
        case .year:
            for i in (0..<12).reversed() {
                if let date = calendar.date(byAdding: .month, value: -i, to: Date()) {
                    let monthFormatter = DateFormatter(); monthFormatter.dateFormat = "yyyy-MM"
                    let monthKey = monthFormatter.string(from: date)
                    let total = globalHistory.filter { $0.key.starts(with: monthKey) }.reduce(0) { $0 + $1.value }
                    let fullFmt = DateFormatter(); fullFmt.dateFormat = "MMMM yyyy"
                    data.append(ChartData(date: date, count: total, fullDate: fullFmt.string(from: date)))
                }
            }
        }
        return data
    }
    
    // Match a tapped date to the nearest bar
    func findClosestData(to date: Date, in data: [ChartData]) -> ChartData? {
        return data.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }
    
    // Format x-axis labels by range
    func formatAxisDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch selectedRange {
        case .week: formatter.dateFormat = "EEE"
        case .month: formatter.dateFormat = "d"
        case .year: formatter.dateFormat = "MMM"
        }
        return formatter.string(from: date)
    }
}

// Project summary card shown in the list
struct ProjectCardView: View {
    let project: KnittingProject
    var onRename: () -> Void; var onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(project.title).font(.headline).fontDesign(.rounded).foregroundColor(.primary)
                Text("Row: \(project.totalRows)").font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            Menu {
                Button(action: onRename) { Label("Rename", systemImage: "pencil") }
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            } label: { Image(systemName: "ellipsis.circle").font(.title2).foregroundColor(.gray).padding(8) }
            .buttonStyle(BorderlessButtonStyle())
        }.padding().background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(16).shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// Preview the project list
#Preview { ProjectListView() }
