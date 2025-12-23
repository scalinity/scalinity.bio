import Foundation

struct RegimenPlan: Codable, Hashable {
    let createdAt: Date
    let durationWeeks: Int
    let components: [RegimenComponent]
    let citations: [String] // e.g., ["PMID: 12345"]
}

struct RegimenComponent: Codable, Hashable, Identifiable {
    let id: UUID
    let category: String // Nutrition, Supplements, Exercise, Sleep, Monitoring
    let title: String
    let details: String
    let checkpointWeekInterval: Int

    init(id: UUID = UUID(), category: String, title: String, details: String, checkpointWeekInterval: Int = 1) {
        self.id = id
        self.category = category
        self.title = title
        self.details = details
        self.checkpointWeekInterval = checkpointWeekInterval
    }
}


