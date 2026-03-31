import Foundation

// Shared project persistence for the app and lock screen surface
enum ProjectStore {
    nonisolated static let appGroupID = "group.com.example.Knit.shared"
    nonisolated static let projectsKey = "saved_projects_data"
    nonisolated static let liveActivityProjectIDsKey = "live_activity_project_ids"

    nonisolated private static var suiteDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    nonisolated private static var primaryDefaults: UserDefaults {
        suiteDefaults ?? .standard
    }

    // Load and migrate saved projects into the shared container
    nonisolated static func loadProjects() -> [KnittingProject]? {
        migrateLegacyProjectsIfNeeded()

        guard let data = primaryDefaults.data(forKey: projectsKey),
              let projects = try? JSONDecoder().decode([KnittingProject].self, from: data) else {
            return nil
        }

        return projects
    }

    // Save the full project list for both the app and extension
    nonisolated static func saveProjects(_ projects: [KnittingProject]) {
        guard let encodedData = try? JSONEncoder().encode(projects) else { return }

        primaryDefaults.set(encodedData, forKey: projectsKey)
        UserDefaults.standard.set(encodedData, forKey: projectsKey)
    }

    // Save a single updated project back into storage
    nonisolated static func saveProject(_ project: KnittingProject) {
        var projects = loadProjects() ?? []

        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }

        saveProjects(projects)
    }

    // Fetch a project by identifier
    nonisolated static func project(withID id: UUID) -> KnittingProject? {
        loadProjects()?.first(where: { $0.id == id })
    }

    // Track which projects currently have a running lock screen counter
    nonisolated static func setLiveActivityActive(_ isActive: Bool, for projectID: UUID) {
        var ids = Set(primaryDefaults.stringArray(forKey: liveActivityProjectIDsKey) ?? [])

        if isActive {
            ids.insert(projectID.uuidString)
        } else {
            ids.remove(projectID.uuidString)
        }

        let values = Array(ids)
        primaryDefaults.set(values, forKey: liveActivityProjectIDsKey)
        UserDefaults.standard.set(values, forKey: liveActivityProjectIDsKey)
    }

    // Read the cached live activity state for a project
    nonisolated static func isLiveActivityActive(for projectID: UUID) -> Bool {
        let ids = primaryDefaults.stringArray(forKey: liveActivityProjectIDsKey) ?? []
        return ids.contains(projectID.uuidString)
    }

    // Move existing app-only data into the shared container
    nonisolated private static func migrateLegacyProjectsIfNeeded() {
        guard let suiteDefaults else { return }
        guard suiteDefaults.data(forKey: projectsKey) == nil,
              let legacyData = UserDefaults.standard.data(forKey: projectsKey) else { return }

        suiteDefaults.set(legacyData, forKey: projectsKey)
    }
}
