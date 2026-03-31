import Foundation
import WidgetKit

// Project model mirrored for the widget extension
struct WidgetKnittingProject: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var totalRows: Int = 0
    var currentRepeatRow: Int = 0
    var completedRepeats: Int = 0
    var rowsPerRepeat: Int = 10
    var notes: String = ""
    var history: [String: Int] = [:]
    var pdfFileName: String? = nil
    var pageDrawings: [Int: Data] = [:]
    var dateCreated: Date = Date()
    var lastUpdated: Date = Date()

    nonisolated static func dateKey(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// Mirror the app's counter modes inside the extension
enum WidgetProjectCounterMode: String, Codable, Hashable {
    case rows
    case repeats
}

// Mirror the app's counter actions inside the extension
enum WidgetProjectCounterAction: String, Codable, Hashable {
    case increment
    case decrement
}

// Read and write shared project data from the app group
enum WidgetProjectStore {
    nonisolated static let appGroupID = "group.com.example.Knit.shared"
    nonisolated static let projectsKey = "saved_projects_data"
    nonisolated static let liveActivityProjectIDsKey = "live_activity_project_ids"

    nonisolated private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    nonisolated static func project(withID id: String) -> WidgetKnittingProject? {
        guard let data = defaults.data(forKey: projectsKey),
              let projects = try? JSONDecoder().decode([WidgetKnittingProject].self, from: data) else {
            return nil
        }

        return projects.first(where: { $0.id.uuidString == id })
    }

    nonisolated static func saveProject(_ project: WidgetKnittingProject) {
        guard let data = defaults.data(forKey: projectsKey),
              var projects = try? JSONDecoder().decode([WidgetKnittingProject].self, from: data),
              let index = projects.firstIndex(where: { $0.id == project.id }) else {
            return
        }

        projects[index] = project

        guard let encodedData = try? JSONEncoder().encode(projects) else { return }
        defaults.set(encodedData, forKey: projectsKey)
    }

    nonisolated static func setLiveActivityActive(_ isActive: Bool, for projectID: String) {
        var ids = Set(defaults.stringArray(forKey: liveActivityProjectIDsKey) ?? [])

        if isActive {
            ids.insert(projectID)
        } else {
            ids.remove(projectID)
        }

        defaults.set(Array(ids), forKey: liveActivityProjectIDsKey)
    }
}

// Keep the counter rules aligned with the app
enum WidgetProjectCounterMutation {
    nonisolated static func apply(
        action: WidgetProjectCounterAction,
        mode: WidgetProjectCounterMode,
        to project: inout WidgetKnittingProject,
        now: Date = Date()
    ) {
        project.lastUpdated = now
        let historyKey = WidgetKnittingProject.dateKey(for: now)

        switch action {
        case .increment:
            project.history[historyKey, default: 0] += 1

            switch mode {
            case .rows:
                project.totalRows += 1
            case .repeats:
                if project.currentRepeatRow < project.rowsPerRepeat {
                    project.currentRepeatRow += 1
                } else {
                    project.currentRepeatRow = 1
                    project.completedRepeats += 1
                }
            }

        case .decrement:
            if let count = project.history[historyKey], count > 0 {
                project.history[historyKey] = count - 1
            }

            switch mode {
            case .rows:
                if project.totalRows > 0 {
                    project.totalRows -= 1
                }
            case .repeats:
                if project.currentRepeatRow > 0 {
                    project.currentRepeatRow -= 1
                } else if project.completedRepeats > 0 {
                    project.completedRepeats -= 1
                    project.currentRepeatRow = project.rowsPerRepeat
                }
            }
        }
    }
}
