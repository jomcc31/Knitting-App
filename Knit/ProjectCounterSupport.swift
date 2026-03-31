import Foundation

// Shared counter modes used by the app and live activity
enum ProjectCounterMode: String, Codable, Hashable {
    case rows
    case repeats
}

// Shared counter actions used by the app and live activity
enum ProjectCounterAction: String, Codable, Hashable {
    case increment
    case decrement
}

// Centralize counter mutation rules in one place
enum ProjectCounterMutation {
    nonisolated static func apply(
        action: ProjectCounterAction,
        mode: ProjectCounterMode,
        to project: inout KnittingProject,
        now: Date = Date()
    ) {
        project.lastUpdated = now
        let historyKey = KnittingProject.dateKey(for: now)

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
