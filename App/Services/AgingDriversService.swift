import Foundation

struct AgingDriversService {
    private struct FeatureScore {
        let name: String
        let value: Double
        let absValue: Double
    }

    func computeDrivers(featureOrder: [String], featureVector: [Double]) -> [AgingDriver] {
        guard featureOrder.count == featureVector.count else { return [] }

        var bucket: [String: [FeatureScore]] = [:]
        bucket.reserveCapacity(12)

        for (name, value) in zip(featureOrder, featureVector) {
            if name.hasPrefix("sex_") || name.hasPrefix("ethnicity_") { continue }
            if !value.isFinite { continue }

            let key = driverKey(for: name)
            bucket[key, default: []].append(FeatureScore(name: name, value: value, absValue: abs(value)))
        }

        // Aggregate contribution by sum(|z|) within category.
        var totals: [(String, Double)] = []
        totals.reserveCapacity(bucket.count)
        for (k, feats) in bucket {
            totals.append((k, feats.reduce(0.0) { $0 + $1.absValue }))
        }
        totals.sort { $0.1 > $1.1 }

        let totalSum = max(totals.reduce(0.0) { $0 + $1.1 }, 1e-9)
        let top = totals.prefix(5)

        return top.map { (k, s) in
            let pct = (s / totalSum) * 100.0
            let title = driverTitle(for: k)

            let features = (bucket[k] ?? []).sorted { $0.absValue > $1.absValue }
            let topFeatures = features.prefix(2)
            let featureNames = topFeatures.map(\.name)

            let summary = topFeatures.isEmpty
                ? "This category contributed meaningfully to your biological age estimate."
                : "Top signals: " + topFeatures.map { describeFeature($0) }.joined(separator: "; ")

            return AgingDriver(
                key: k,
                title: title,
                percentContribution: pct,
                summary: summary,
                relatedFeatures: featureNames
            )
        }
    }

    // MARK: - Heuristics

    private func driverKey(for feature: String) -> String {
        let f = feature.lowercased()

        if f.hasPrefix("snp_") { return "genomic" }
        if f.hasPrefix("epigenetic_age") { return "epigenetic" }
        if f == "telomere_length_kb" { return "telomere" }
        if f.hasPrefix("expr_") {
            if f.contains("il6") || f.contains("tnf") || f.contains("il1b") || f.contains("nfkb") || f.contains("crp") {
                return "inflammation"
            }
            return "transcriptomic"
        }

        if f.contains("crp") || f.contains("il6") || f.contains("tnf") || f.contains("mcp1") || f.contains("mmp9") {
            return "inflammation"
        }
        if f.contains("glucose") || f.contains("insulin") || f.contains("hba1c") || f.contains("triglycerides") || f.contains("cholesterol") || f == "bmi" {
            return "metabolic"
        }
        if f.contains("nad_plus") || f.contains("coq10") || f.contains("citrate") || f.contains("succinate") || f.contains("malate") || f.contains("fumarate") || f.contains("gdf15") {
            return "mitochondrial"
        }

        return "other"
    }

    private func driverTitle(for key: String) -> String {
        switch key {
        case "inflammation": return "Inflammation"
        case "metabolic": return "Metabolic health"
        case "genomic": return "Genomic risk"
        case "epigenetic": return "Epigenetic drift"
        case "mitochondrial": return "Mitochondrial function"
        case "telomere": return "Telomere maintenance"
        case "transcriptomic": return "Gene expression shifts"
        default: return "Other signals"
        }
    }

    private func describeFeature(_ f: FeatureScore) -> String {
        let dir: String
        if f.value >= 1.0 {
            dir = "elevated"
        } else if f.value <= -1.0 {
            dir = "low"
        } else {
            dir = "shifted"
        }
        return "\(f.name) (\(dir))"
    }
}


