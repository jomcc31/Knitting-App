import AppIntents

// Shared mode options for live activity controls in the app target
enum WidgetCounterModeIntent: String, AppEnum {
    case rows
    case repeats

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Counter Mode")
    static var caseDisplayRepresentations: [WidgetCounterModeIntent: DisplayRepresentation] = [
        .rows: DisplayRepresentation(title: "Rows"),
        .repeats: DisplayRepresentation(title: "Repeats"),
    ]

    var mode: ProjectCounterMode {
        switch self {
        case .rows: return .rows
        case .repeats: return .repeats
        }
    }
}

// Shared action options for live activity controls in the app target
enum WidgetCounterActionIntent: String, AppEnum {
    case increment
    case decrement

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Counter Action")
    static var caseDisplayRepresentations: [WidgetCounterActionIntent: DisplayRepresentation] = [
        .increment: DisplayRepresentation(title: "Increment"),
        .decrement: DisplayRepresentation(title: "Decrement"),
    ]

    var action: ProjectCounterAction {
        switch self {
        case .increment: return .increment
        case .decrement: return .decrement
        }
    }
}

// Adjust the active counter directly from the live activity in the app process
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
        guard let id = UUID(uuidString: projectID),
              var project = ProjectStore.project(withID: id) else {
            return .result()
        }

        ProjectCounterMutation.apply(action: action.action, mode: mode.mode, to: &project)
        await ProjectCounterLiveActivityManager.update(for: project, mode: mode.mode)
        let savedProject = project
        Task.detached(priority: .userInitiated) {
            ProjectStore.saveProject(savedProject)
        }
        return .result()
    }
}

// Switch between row and repeat modes directly from the live activity
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
        guard let id = UUID(uuidString: projectID),
              let project = ProjectStore.project(withID: id) else {
            return .result()
        }

        await ProjectCounterLiveActivityManager.update(for: project, mode: mode.mode)
        return .result()
    }
}
