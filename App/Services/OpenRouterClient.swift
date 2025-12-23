import Foundation

struct OpenRouterClient {
    enum ClientError: Error, LocalizedError {
        case missingAPIKey
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Missing OPENROUTER_API_KEY."
            case .invalidResponse(let msg):
                return "OpenRouter error: \(msg)"
            }
        }
    }

    private let apiKeyProvider: () -> String?
    private let session: URLSession
    private let model: String

    init(apiKeyProvider: @escaping () -> String?, model: String = "openai/gpt-4o-mini", session: URLSession = .shared) {
        self.apiKeyProvider = apiKeyProvider
        self.model = model
        self.session = session
    }

    func generateRegimen(
        profile: OmicsProfile,
        result: BiologicalAgeResult,
        citations: [PubMedCitation]
    ) async throws -> RegimenPlan {
        guard let key = apiKeyProvider(), !key.isEmpty else {
            throw ClientError.missingAPIKey
        }

        let citationText = citations
            .map { "[PMID: \($0.pmid)]\n\($0.text)" }
            .joined(separator: "\n\n")

        let bmiText = profile.bmi.map { String(format: "%.1f", $0) } ?? "unknown"
        let dietText = profile.dietScore.map { String(format: "%.1f", $0) } ?? "unknown"
        let exerciseText = profile.exerciseScore.map { String(format: "%.1f", $0) } ?? "unknown"
        let sleepText = profile.sleepScore.map { String(format: "%.1f", $0) } ?? "unknown"

        let prompt = """
You are generating a personalized anti-aging regimen. Produce ONLY valid JSON (no prose).

User profile:
- Age: \(Int(profile.chronologicalAge))
- Sex: \(profile.sex.rawValue)
- Ethnicity: \(profile.ethnicity)
- BMI: \(bmiText)
- Lifestyle (1–10): diet=\(dietText), exercise=\(exerciseText), sleep=\(sleepText)
- Diabetes: \(profile.comorbidityDiabetes ? "yes" : "no")

Biological age result:
- Chronological: \(String(format: "%.1f", result.chronologicalAge))
- Predicted biological: \(String(format: "%.1f", result.predictedBiologicalAge))
- Delta (years): \(String(format: "%.1f", result.deltaYears))
- Top drivers: \(result.drivers.map { "\($0.title) (\(Int($0.percentContribution))%)" }.joined(separator: ", "))

Evidence context (use inline citations in the form "PMID: XXXXX"):
\(citationText)

JSON schema (must match exactly):
{
  "duration_weeks": 12,
  "components": [
    {
      "category": "Nutrition|Supplements|Exercise|Sleep|Monitoring",
      "title": "...",
      "details": "...",
      "checkpoint_week_interval": 1,
      "citations": ["PMID: 12345"]
    }
  ],
  "global_citations": ["PMID: 12345"],
  "safety_notes": "..."
}

Rules:
- Provide a 12–24 week plan.
- Include weekly checkpoints.
- Cite PMIDs when making evidence claims. If evidence is weak, say so.
- Do not provide chain-of-thought. Provide concise factor-based rationale in details.
"""

        let body = OpenRouterChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: "You are a careful, evidence-oriented health assistant. Output JSON only."),
                .init(role: "user", content: prompt),
            ],
            temperature: 0.2
        )

        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("scalinity.bio", forHTTPHeaderField: "X-Title")

        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ClientError.invalidResponse("No HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ClientError.invalidResponse(msg)
        }

        let decoded = try JSONDecoder().decode(OpenRouterChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw ClientError.invalidResponse("Missing assistant content.")
        }

        let jsonString = extractJSONObject(from: content) ?? content
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ClientError.invalidResponse("Could not decode assistant JSON.")
        }

        let regimen = try JSONDecoder().decode(LLMRegimenResponse.self, from: jsonData)
        let components = regimen.components.map {
            RegimenComponent(
                category: $0.category,
                title: $0.title,
                details: $0.details,
                checkpointWeekInterval: $0.checkpointWeekInterval
            )
        }

        let citationsOut = (regimen.globalCitations + regimen.components.flatMap(\.citations))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return RegimenPlan(
            createdAt: Date(),
            durationWeeks: regimen.durationWeeks,
            components: components,
            citations: Array(Set(citationsOut))
        )
    }

    private func extractJSONObject(from text: String) -> String? {
        guard let first = text.firstIndex(of: "{"),
              let last = text.lastIndex(of: "}") else { return nil }
        guard first < last else { return nil }
        return String(text[first...last])
    }
}

private struct OpenRouterChatRequest: Codable {
    struct Message: Codable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct OpenRouterChatResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct LLMRegimenResponse: Codable {
    struct Component: Codable {
        let category: String
        let title: String
        let details: String
        let checkpointWeekInterval: Int
        let citations: [String]

        enum CodingKeys: String, CodingKey {
            case category, title, details
            case checkpointWeekInterval = "checkpoint_week_interval"
            case citations
        }
    }

    let durationWeeks: Int
    let components: [Component]
    let globalCitations: [String]
    let safetyNotes: String

    enum CodingKeys: String, CodingKey {
        case durationWeeks = "duration_weeks"
        case components
        case globalCitations = "global_citations"
        case safetyNotes = "safety_notes"
    }
}


