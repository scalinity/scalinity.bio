import SwiftUI

struct RegimenView: View {
    @EnvironmentObject private var app: AppViewModel
    @State private var whatIfDeltaByIntervention: [Intervention: Double] = [:]
    @State private var isRunningWhatIf: Bool = false
    @State private var isGeneratingPlan: Bool = false
    @State private var generatedPlan: RegimenPlan?
    @State private var generationError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Regimen")
                    .font(.largeTitle.weight(.semibold))

                if let profile = app.currentProfile, let baseline = app.latestResult {
                    generationCard(profile: profile, baseline: baseline)
                    whatIfCard(profile: profile, baseline: baseline)
                    planCard()
                } else {
                    Text("Run a biological age calculation first, then this screen will generate and adjust your plan weekly.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }

    private func whatIfCard(profile: OmicsProfile, baseline: BiologicalAgeResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("What-if scenarios")
                    .font(.headline)
                Spacer()
                if isRunningWhatIf {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            Text("Simulate interventions and re-run the model to project biological-age changes.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Intervention.allCases) { intervention in
                    Button {
                        runWhatIf(profile: profile, baseline: baseline, intervention: intervention)
                    } label: {
                        HStack {
                            Text(intervention.rawValue)
                            Spacer()
                            if let d = whatIfDeltaByIntervention[intervention] {
                                Text(String(format: "%+.1f years", d))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(d < 0 ? Color.green : Color.red)
                            } else {
                                Text("Run")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func planCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(generatedPlan == nil ? "3–6 month plan (preview)" : "Generated plan")
                .font(.headline)
            if generatedPlan == nil {
                Text("This becomes fully personalized with evidence-backed citations once RAG + OpenRouter is configured.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                if let plan = generatedPlan {
                    ForEach(plan.components) { c in
                        planRow(title: c.category + ": " + c.title, detail: c.details)
                    }
                    if !plan.citations.isEmpty {
                        Text("Citations: \(plan.citations.joined(separator: ", "))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    planRow(title: "Nutrition", detail: "Intermittent fasting 16:8 on 4–5 days/week; prioritize protein and fiber.")
                    planRow(title: "Supplements", detail: "Methylfolate 400 mcg/day if homocysteine is elevated; vitamin D to target 30–50 ng/mL.")
                    planRow(title: "Exercise", detail: "2× strength + 1× HIIT + 1× zone-2 per week, adjusted to baseline fitness.")
                    planRow(title: "Sleep", detail: "Consistent wake time; 60 min wind-down; light exposure in first hour.")
                    planRow(title: "Monitoring", detail: "Weekly check-in prompts; adjust if glucose/CRP trend unfavorably.")
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func planRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func runWhatIf(profile: OmicsProfile, baseline: BiologicalAgeResult, intervention: Intervention) {
        isRunningWhatIf = true
        Task {
            do {
                let sim = WhatIfSimulator()
                let modified = sim.applying(intervention, to: profile)
                let result = try await app.evaluateProfile(modified)
                let delta = result.predictedBiologicalAge - baseline.predictedBiologicalAge
                await MainActor.run {
                    whatIfDeltaByIntervention[intervention] = delta
                    isRunningWhatIf = false
                }
            } catch {
                await MainActor.run {
                    app.lastError = error.localizedDescription
                    isRunningWhatIf = false
                }
            }
        }
    }

    private func generationCard(profile: OmicsProfile, baseline: BiologicalAgeResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Generate regimen (RAG + OpenRouter)")
                    .font(.headline)
                Spacer()
                if isGeneratingPlan {
                    ProgressView()
                        .scaleEffect(0.85)
                }
            }
            Text("Uses PubMed abstracts as retrieval context and asks the LLM to cite PMIDs inline.")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Generate plan") { generateRegimen(profile: profile, baseline: baseline) }
                    .disabled(isGeneratingPlan)
                if generatedPlan != nil {
                    Button("Regenerate") {
                        generatedPlan = nil
                        generateRegimen(profile: profile, baseline: baseline)
                    }
                    .disabled(isGeneratingPlan)
                }
                Spacer()
            }

            if let err = generationError {
                Text(err)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func generateRegimen(profile: OmicsProfile, baseline: BiologicalAgeResult) {
        generationError = nil

        // Pull secrets on the main thread before kicking off async work.
        let openRouterKey = app.environmentConfig.secret(.openRouterApiKey) ?? ""
        let entrezKey = app.environmentConfig.secret(.entrezApiKey) ?? ""

        let dbKeyData: Data
        do {
            dbKeyData = try app.environmentConfig.databaseKeyMaterial()
        } catch {
            generationError = "Set DATABASE_ENCRYPTION_KEY in Settings (or env) to enable encrypted caching."
            return
        }

        isGeneratingPlan = true

        Task {
            do {
                let store = try EncryptedSQLiteStore(keyMaterial: dbKeyData)
                let rag = PubMedRAGService(apiKeyProvider: { entrezKey }, store: store)

                // Simple driver-informed query
                let q = "aging intervention " + baseline.drivers.prefix(3).map { $0.title }.joined(separator: " ")
                let citations = try await rag.retrieve(query: q, topK: 5)

                let client = OpenRouterClient(apiKeyProvider: { openRouterKey })
                let plan = try await client.generateRegimen(profile: profile, result: baseline, citations: citations)

                let payload = try JSONEncoder().encode(plan)
                try await store.put(type: "regimen", id: "profile:\(profile.id.uuidString)", payload: payload)

                await MainActor.run {
                    self.generatedPlan = plan
                    self.isGeneratingPlan = false
                }
            } catch {
                await MainActor.run {
                    self.generationError = error.localizedDescription
                    self.isGeneratingPlan = false
                }
            }
        }
    }
}


