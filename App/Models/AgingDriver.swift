import Foundation

struct AgingDriver: Codable, Hashable, Identifiable {
    var id: String { key }

    /// Stable key (e.g., "inflammation", "metabolic")
    let key: String
    let title: String
    let percentContribution: Double
    let summary: String
    let relatedFeatures: [String]
}



