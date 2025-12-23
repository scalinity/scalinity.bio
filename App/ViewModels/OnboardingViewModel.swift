import Foundation
import SwiftUI

struct OnboardingDraft: Codable, Hashable {
    var chronologicalAge: Double = 50
    var sex: Sex = .female
    var ethnicity: String = "European"
    var bmi: Double? = 25
    var dietScore: Double = 6
    var exerciseScore: Double = 6
    var sleepScore: Double = 6
    var comorbidityDiabetes: Bool = false

    // Optional key biomarkers (all optional)
    var homocysteine: Double?
    var fastingGlucose: Double?
    var fastingInsulin: Double?
    var crp: Double?
    var il6: Double?
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var stepIndex: Int = 0
    @Published var draft: OnboardingDraft {
        didSet { persistDraft() }
    }

    private let draftStorageKey = "scalinity_onboarding_draft_json"

    init() {
        let stored = UserDefaults.standard.string(forKey: draftStorageKey) ?? ""
        if let data = stored.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(OnboardingDraft.self, from: data) {
            self.draft = decoded
        } else {
            self.draft = OnboardingDraft()
        }
    }

    func reset() {
        draft = OnboardingDraft()
        stepIndex = 0
    }

    func toProfile() -> OmicsProfile {
        var biomarkers: [String: Double] = [:]
        if let v = draft.homocysteine { biomarkers["metab_homocysteine_umol_L"] = v }
        if let v = draft.fastingGlucose { biomarkers["metab_glucose_mg_dL"] = v }
        if let v = draft.fastingInsulin { biomarkers["metab_insulin_uIU_mL"] = v }
        if let v = draft.crp { biomarkers["crp_mg_L"] = v }
        if let v = draft.il6 { biomarkers["il6_pg_mL"] = v }

        return OmicsProfile(
            chronologicalAge: draft.chronologicalAge,
            sex: draft.sex,
            ethnicity: draft.ethnicity,
            bmi: draft.bmi,
            dietScore: draft.dietScore,
            exerciseScore: draft.exerciseScore,
            sleepScore: draft.sleepScore,
            comorbidityDiabetes: draft.comorbidityDiabetes,
            biomarkers: biomarkers
        )
    }

    private func persistDraft() {
        guard let data = try? JSONEncoder().encode(draft),
              let json = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(json, forKey: draftStorageKey)
    }
}


