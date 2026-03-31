import ActivityKit
import Foundation

// Fixed and dynamic data shown in the lock screen counter
struct ProjectCounterActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var mode: ProjectCounterMode
        var totalRows: Int
        var currentRepeatRow: Int
        var completedRepeats: Int
        var rowsPerRepeat: Int
        var lastUpdated: Date
    }

    var projectID: String
    var projectTitle: String
}

// Manage the lifecycle of each project's live activity
@MainActor
enum ProjectCounterLiveActivityManager {
    static var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func isActive(for projectID: UUID) -> Bool {
        Activity<ProjectCounterActivityAttributes>.activities.contains {
            $0.attributes.projectID == projectID.uuidString
        }
    }

    static func start(for project: KnittingProject, mode: ProjectCounterMode = .rows) async -> Bool {
        guard areActivitiesEnabled else { return false }

        if isActive(for: project.id) {
            ProjectStore.setLiveActivityActive(true, for: project.id)
            return true
        }

        let attributes = ProjectCounterActivityAttributes(
            projectID: project.id.uuidString,
            projectTitle: project.title
        )

        let content = ActivityContent(
            state: contentState(for: project, mode: mode),
            staleDate: nil
        )

        do {
            _ = try Activity<ProjectCounterActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            ProjectStore.setLiveActivityActive(true, for: project.id)
            return true
        } catch {
            ProjectStore.setLiveActivityActive(false, for: project.id)
            return false
        }
    }

    static func update(for project: KnittingProject, mode: ProjectCounterMode? = nil) async {
        for activity in Activity<ProjectCounterActivityAttributes>.activities where activity.attributes.projectID == project.id.uuidString {
            let resolvedMode = mode ?? activity.content.state.mode
            let content = ActivityContent(
                state: contentState(for: project, mode: resolvedMode),
                staleDate: nil
            )
            await activity.update(content, alertConfiguration: nil, timestamp: .now)
            ProjectStore.setLiveActivityActive(true, for: project.id)
        }
    }

    static func end(for projectID: UUID) async {
        for activity in Activity<ProjectCounterActivityAttributes>.activities where activity.attributes.projectID == projectID.uuidString {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        ProjectStore.setLiveActivityActive(false, for: projectID)
    }

    // Build the content state for the current project snapshot
    static func contentState(for project: KnittingProject, mode: ProjectCounterMode) -> ProjectCounterActivityAttributes.ContentState {
        ProjectCounterActivityAttributes.ContentState(
            mode: mode,
            totalRows: project.totalRows,
            currentRepeatRow: project.currentRepeatRow,
            completedRepeats: project.completedRepeats,
            rowsPerRepeat: project.rowsPerRepeat,
            lastUpdated: project.lastUpdated
        )
    }
}
