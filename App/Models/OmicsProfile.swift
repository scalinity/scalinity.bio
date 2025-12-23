import Foundation

struct OmicsProfile: Codable, Identifiable, Hashable {
    var id: UUID
    var createdAt: Date

    // Required demographics
    var chronologicalAge: Double
    var sex: Sex
    var ethnicity: String

    // Optional lifestyle / anthropometrics
    var bmi: Double?
    var dietScore: Double?
    var exerciseScore: Double?
    var sleepScore: Double?

    // Comorbidities
    var comorbidityDiabetes: Bool

    /// Additional numeric values keyed by feature/column name (e.g., `protein_GDF15`, `expr_TP53`, `snp_rs00001`).
    var biomarkers: [String: Double]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        chronologicalAge: Double,
        sex: Sex,
        ethnicity: String,
        bmi: Double? = nil,
        dietScore: Double? = nil,
        exerciseScore: Double? = nil,
        sleepScore: Double? = nil,
        comorbidityDiabetes: Bool = false,
        biomarkers: [String: Double] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.chronologicalAge = chronologicalAge
        self.sex = sex
        self.ethnicity = ethnicity
        self.bmi = bmi
        self.dietScore = dietScore
        self.exerciseScore = exerciseScore
        self.sleepScore = sleepScore
        self.comorbidityDiabetes = comorbidityDiabetes
        self.biomarkers = biomarkers
    }

    /// Returns a raw numeric value for a model feature name, or `nil` if missing.
    func value(for feature: String) -> Double? {
        switch feature {
        case "chronological_age":
            return chronologicalAge
        case "bmi":
            return bmi
        case "diet_score":
            return dietScore
        case "exercise_score":
            return exerciseScore
        case "sleep_score":
            return sleepScore
        case "comorbidity_diabetes":
            return comorbidityDiabetes ? 1.0 : 0.0
        default:
            return biomarkers[feature]
        }
    }
}


