import Foundation

enum Intervention: String, CaseIterable, Identifiable {
    case intermittentFasting16_8 = "Intermittent fasting (16:8)"
    case hiit3xWeek = "HIIT (3x/week)"
    case yoga150minWeek = "Yoga (150 min/week)"
    case optimizeSleep = "Sleep optimization"

    var id: String { rawValue }
}

struct WhatIfSimulator {
    /// Apply coarse intervention heuristics to a profile to estimate directionally-correct changes.
    ///
    /// This does *not* claim clinical accuracy; it is a what-if visualization layer on top of the trained model.
    func applying(_ intervention: Intervention, to profile: OmicsProfile) -> OmicsProfile {
        var p = profile
        var b = p.biomarkers

        func scale(_ key: String, by factor: Double) {
            guard let v = b[key] else { return }
            b[key] = v * factor
        }
        func add(_ key: String, _ delta: Double) {
            guard let v = b[key] else { return }
            b[key] = v + delta
        }

        switch intervention {
        case .intermittentFasting16_8:
            scale("metab_glucose_mg_dL", by: 0.97)
            scale("metab_insulin_uIU_mL", by: 0.90)
            scale("metab_triglycerides_mg_dL", by: 0.92)
            add("metab_beta_hydroxybutyrate_mmol_L", 0.05)
        case .hiit3xWeek:
            scale("metab_insulin_uIU_mL", by: 0.92)
            scale("crp_mg_L", by: 0.93)
            add("metab_hdl_mg_dL", 2.0)
        case .yoga150minWeek:
            scale("il6_pg_mL", by: 0.95)
            scale("crp_mg_L", by: 0.95)
            scale("metab_cortisol_ug_dL", by: 0.95)
        case .optimizeSleep:
            scale("metab_cortisol_ug_dL", by: 0.90)
            add("metab_melatonin_pg_mL", 3.0)
            add("telomere_length_kb", 0.05)
        }

        p.biomarkers = b
        return p
    }
}



