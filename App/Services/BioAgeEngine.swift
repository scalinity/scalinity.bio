import Foundation

final class BioAgeEngine {
    private let preprocessor: PreprocessingService
    private let model: BioAgeModelService
    private let drivers: AgingDriversService

    init(
        preprocessor: PreprocessingService,
        model: BioAgeModelService,
        drivers: AgingDriversService = AgingDriversService()
    ) {
        self.preprocessor = preprocessor
        self.model = model
        self.drivers = drivers
    }

    func evaluate(profile: OmicsProfile) async throws -> BiologicalAgeResult {
        let input = try await preprocessor.makeModelInput(profile: profile)
        let featureVector = try await preprocessor.makeFeatureVector(profile: profile)

        let predicted = try model.predictBiologicalAge(modelInput: input)
        let delta = predicted - profile.chronologicalAge

        let baScore = Self.baScore(deltaYears: delta)

        // Derive driver contributions from standardized features.
        let stats = try FeatureStats.loadFromBundle()
        let driverList = drivers.computeDrivers(featureOrder: stats.featureOrder, featureVector: featureVector)

        let summary: String = {
            if delta <= -1.0 {
                return String(format: "Estimated biological age is %.1f years (%.1f years younger than chronological).", predicted, abs(delta))
            } else if delta >= 1.0 {
                return String(format: "Estimated biological age is %.1f years (%.1f years older than chronological).", predicted, delta)
            } else {
                return String(format: "Estimated biological age is %.1f years (approximately aligned with chronological).", predicted)
            }
        }()

        return BiologicalAgeResult(
            profileId: profile.id,
            generatedAt: Date(),
            chronologicalAge: profile.chronologicalAge,
            predictedBiologicalAge: predicted,
            baScore: baScore,
            deltaYears: delta,
            drivers: driverList,
            summary: summary
        )
    }

    static func baScore(deltaYears: Double) -> Double {
        // Map delta to 0–100 using a logistic curve centered at 0.
        // delta=0 -> 50; delta ~ +8 -> ~88; delta ~ -8 -> ~12
        let x = deltaYears / 4.0
        let score = 100.0 * (1.0 / (1.0 + exp(-x)))
        return max(0.0, min(100.0, score))
    }
}


