import ActivityKit
import AppIntents

// Button modes used by the live activity
enum WidgetCounterModeIntent: String, AppEnum {
    case rows
    case repeats

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Counter Mode")
    static var caseDisplayRepresentations: [WidgetCounterModeIntent: DisplayRepresentation] = [
        .rows: DisplayRepresentation(title: "Rows"),
        .repeats: DisplayRepresentation(title: "Repeats"),
    ]

    var mode: WidgetProjectCounterMode {
        switch self {
        case .rows: return .rows
        case .repeats: return .repeats
        }
    }
}

// Button actions used by the live activity
enum WidgetCounterActionIntent: String, AppEnum {
    case increment
    case decrement

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Counter Action")
    static var caseDisplayRepresentations: [WidgetCounterActionIntent: DisplayRepresentation] = [
        .increment: DisplayRepresentation(title: "Increment"),
        .decrement: DisplayRepresentation(title: "Decrement"),
    ]

    var action: WidgetProjectCounterAction {
        switch self {
        case .increment: return .increment
        case .decrement: return .decrement
        }
    }
}

// Shared live activity attributes mirrored inside the extension
struct ProjectCounterActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var mode: WidgetProjectCounterMode
        var totalRows: Int
        var currentRepeatRow: Int
        var completedRepeats: Int
        var rowsPerRepeat: Int
        var lastUpdated: Date
    }

    var projectID: String
    var projectTitle: String
}

// Adjust the active counter directly from the lock screen
struct AdjustProjectCounterIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Adjust Project Counter"
    static var openAppWhenRun = false

    @Parameter(title: "Project ID") var projectID: String
    @Parameter(title: "Mode") var mode: WidgetCounterModeIntent
    @Parameter(title: "Action") var action: WidgetCounterActionIntent

    init() {}

    init(projectID: String, mode: WidgetCounterModeIntent, action: WidgetCounterActionIntent) {
        self.projectID = projectID
        self.mode = mode
        self.action = action
    }

    func perform() async throws -> some IntentResult {
        guard var project = WidgetProjectStore.project(withID: projectID) else { return .result() }

        WidgetProjectCounterMutation.apply(action: action.action, mode: mode.mode, to: &project)
        await WidgetProjectLiveActivitySync.update(project: project, mode: mode.mode)
        let savedProject = project
        Task.detached(priority: .userInitiated) {
            WidgetProjectStore.saveProject(savedProject)
        }
        return .result()
    }
}

// Switch the live activity between row and repeat modes
struct SetProjectCounterModeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Set Project Counter Mode"
    static var openAppWhenRun = false

    @Parameter(title: "Project ID") var projectID: String
    @Parameter(title: "Mode") var mode: WidgetCounterModeIntent

    init() {}

    init(projectID: String, mode: WidgetCounterModeIntent) {
        self.projectID = projectID
        self.mode = mode
    }

    func perform() async throws -> some IntentResult {
        guard let project = WidgetProjectStore.project(withID: projectID) else { return .result() }

        await WidgetProjectLiveActivitySync.update(project: project, mode: mode.mode)
        return .result()
    }
}

// Update active live activities after each intent
enum WidgetProjectLiveActivitySync {
    static func update(project: WidgetKnittingProject, mode: WidgetProjectCounterMode) async {
        for activity in Activity<ProjectCounterActivityAttributes>.activities where activity.attributes.projectID == project.id.uuidString {
            let content = ActivityContent(
                state: ProjectCounterActivityAttributes.ContentState(
                    mode: mode,
                    totalRows: project.totalRows,
                    currentRepeatRow: project.currentRepeatRow,
                    completedRepeats: project.completedRepeats,
                    rowsPerRepeat: project.rowsPerRepeat,
                    lastUpdated: project.lastUpdated
                ),
                staleDate: nil
            )

            await activity.update(content, alertConfiguration: nil, timestamp: .now)
            WidgetProjectStore.setLiveActivityActive(true, for: project.id.uuidString)
        }
    }
}
