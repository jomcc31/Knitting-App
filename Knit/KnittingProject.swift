import Foundation

// Project data persisted across the app
struct KnittingProject: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    
    // Counter state
    var totalRows: Int = 0
    var currentRepeatRow: Int = 0
    var completedRepeats: Int = 0
    var rowsPerRepeat: Int = 10
    
    // Project content and history
    var notes: String = ""
    var history: [String: Int] = [:]
    
    // Stored pattern metadata
    var pdfFileName: String? = nil
    var pageDrawings: [Int: Data] = [:]
    
    // Timestamps for sorting and stats
    var dateCreated: Date = Date()
    var lastUpdated: Date = Date()
    
    // Build a stable history key for daily totals
    nonisolated static func dateKey(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
