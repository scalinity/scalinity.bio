import Foundation

struct BiologicalAgeResult: Codable, Hashable {
    let profileId: UUID
    let generatedAt: Date

    let chronologicalAge: Double
    let predictedBiologicalAge: Double

    /// \(0–100\) scale where higher means biologically older relative to the reference cohort.
    let baScore: Double

    /// `predictedBiologicalAge - chronologicalAge`
    let deltaYears: Double

    let drivers: [AgingDriver]
    let summary: String
}



