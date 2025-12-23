import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var currentProfile: OmicsProfile?
    @Published var latestResult: BiologicalAgeResult?
    @Published var isComputing: Bool = false
    @Published var lastError: String?

    let environmentConfig = EnvironmentConfig()
    private let importService = DataImportService()

    private let preprocessor: PreprocessingService?
    private let modelService: BioAgeModelService?
    private let engine: BioAgeEngine?

    init() {
        do {
            let pre = try PreprocessingService()
            let model = try BioAgeModelService()
            self.preprocessor = pre
            self.modelService = model
            self.engine = BioAgeEngine(preprocessor: pre, model: model)
        } catch {
            self.preprocessor = nil
            self.modelService = nil
            self.engine = nil
            self.lastError = "Initialization failed: \(error.localizedDescription)"
        }
    }

    func importProfile(from url: URL) {
        do {
            let profile = try importService.importProfile(from: url)
            self.currentProfile = profile
            self.latestResult = nil
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func loadDemoProfile() {
        let p = OmicsProfile(
            chronologicalAge: 52,
            sex: .female,
            ethnicity: "European",
            bmi: 26.1,
            dietScore: 6.0,
            exerciseScore: 5.0,
            sleepScore: 6.5,
            comorbidityDiabetes: false,
            biomarkers: [
                "metab_homocysteine_umol_L": 15.0,
                "metab_glucose_mg_dL": 102.0,
                "crp_mg_L": 2.8,
                "il6_pg_mL": 3.5,
            ]
        )
        self.currentProfile = p
        self.latestResult = nil
        self.lastError = nil
    }

    func evaluateCurrentProfile() {
        guard let profile = currentProfile else {
            lastError = "No profile loaded."
            return
        }
        guard let engine else {
            lastError = "BioAge engine not available (missing model/resources)."
            return
        }

        isComputing = true
        lastError = nil

        Task {
            do {
                let result = try await engine.evaluate(profile: profile)
                await MainActor.run {
                    self.latestResult = result
                    self.isComputing = false
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isComputing = false
                }
            }
        }
    }

    func evaluateProfile(_ profile: OmicsProfile) async throws -> BiologicalAgeResult {
        guard let engine else {
            throw InputValidationError.parseFailed("BioAge engine not available (missing model/resources).")
        }
        return try await engine.evaluate(profile: profile)
    }
}


