import Foundation

actor PreprocessingService {
    private let stats: FeatureStats
    private let numericSet: Set<String>

    private var referenceMatrix: [[Double]]?

    init() throws {
        self.stats = try FeatureStats.loadFromBundle()
        self.numericSet = Set(stats.numericColumns)
    }

    /// Build a fully-imputed feature vector in the exact `feature_order` used for training.
    func makeFeatureVector(profile: OmicsProfile) async throws -> [Double] {
        var vec = buildStandardizedVector(profile: profile)

        let missingIdx = vec.enumerated().compactMap { $0.element.isNaN ? $0.offset : nil }
        if !missingIdx.isEmpty {
            let ref = try await loadReferenceMatrix()
            knnImpute(&vec, missingIndices: missingIdx, reference: ref, k: 5)
        }

        // Final sanity: no NaNs
        if vec.contains(where: { $0.isNaN || !$0.isFinite }) {
            throw InputValidationError.parseFailed("Preprocessing produced invalid numeric values (NaN/Inf).")
        }
        return vec
    }

    /// Convert a feature vector into a `[String: Double]` dictionary keyed by model input feature name.
    func makeModelInput(profile: OmicsProfile) async throws -> [String: Double] {
        let vec = try await makeFeatureVector(profile: profile)
        var dict: [String: Double] = [:]
        dict.reserveCapacity(stats.featureOrder.count)
        for (name, value) in zip(stats.featureOrder, vec) {
            dict[name] = value
        }
        return dict
    }

    // MARK: - Standardization + one-hot

    private func buildStandardizedVector(profile: OmicsProfile) -> [Double] {
        var out: [Double] = []
        out.reserveCapacity(stats.featureOrder.count)

        for feature in stats.featureOrder {
            if numericSet.contains(feature) {
                let raw = profile.value(for: feature)
                out.append(standardizeNumeric(feature: feature, raw: raw))
                continue
            }

            // One-hot categoricals
            if feature.hasPrefix("sex_") {
                let expected = feature.replacingOccurrences(of: "sex_", with: "")
                out.append(profile.sex.rawValue == expected ? 1.0 : 0.0)
                continue
            }
            if feature.hasPrefix("ethnicity_") {
                let expected = feature.replacingOccurrences(of: "ethnicity_", with: "")
                out.append(profile.ethnicity == expected ? 1.0 : 0.0)
                continue
            }

            // Unknown feature name: default to missing to allow KNN fill.
            out.append(.nan)
        }

        return out
    }

    private func standardizeNumeric(feature: String, raw: Double?) -> Double {
        guard let raw else {
            // Standardized mean value is 0 (since we standardize by mean/std).
            return .nan
        }

        let clipped = winsorize(feature: feature, value: raw)
        let mu = stats.mean[feature] ?? 0.0
        let sd = stats.std[feature] ?? 1.0
        if sd == 0 { return clipped - mu }
        return (clipped - mu) / sd
    }

    private func winsorize(feature: String, value: Double) -> Double {
        guard let b = stats.winsorP01P99[feature] else { return value }
        return min(max(value, b.p01), b.p99)
    }

    // MARK: - Reference matrix + KNN

    private func loadReferenceMatrix() async throws -> [[Double]] {
        if let referenceMatrix { return referenceMatrix }

        let url = Bundle.module.url(forResource: "synthetic_cohort", withExtension: "csv")
            ?? Bundle.module.url(forResource: "synthetic_cohort", withExtension: "csv", subdirectory: "Data")
        guard let url else {
            throw InputValidationError.parseFailed("Missing bundled cohort: synthetic_cohort.csv")
        }

        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(whereSeparator: \.isNewline).map { String($0) }
        guard let headerLine = lines.first else {
            throw InputValidationError.parseFailed("Empty cohort CSV.")
        }

        let header = parseCSVLine(headerLine)
        var idx: [String: Int] = [:]
        for (i, c) in header.enumerated() {
            idx[c] = i
        }
        guard let sexCol = idx["sex"], let ethnicityCol = idx["ethnicity"] else {
            throw InputValidationError.parseFailed("Cohort CSV is missing required columns: sex, ethnicity")
        }

        // Precompute numeric standardization for speed
        let featureOrder = stats.featureOrder
        let numericSet = self.numericSet
        let mean = stats.mean
        let std = stats.std
        let winsor = stats.winsorP01P99

        func standardizedNumeric(_ feature: String, _ rawString: String?) -> Double {
            guard let rawString, let raw = Double(rawString), raw.isFinite else {
                // missing -> mean -> standardized 0
                return 0.0
            }
            let bounds = winsor[feature]
            let clipped = bounds.map { min(max(raw, $0.p01), $0.p99) } ?? raw
            let mu = mean[feature] ?? 0.0
            let sd = std[feature] ?? 1.0
            return (clipped - mu) / (sd == 0 ? 1.0 : sd)
        }

        var matrix: [[Double]] = []
        matrix.reserveCapacity(max(0, lines.count - 1))

        for line in lines.dropFirst() {
            let row = parseCSVLine(line)
            if row.count != header.count { continue }

            let sex = row[sexCol]
            let ethnicity = row[ethnicityCol]

            var vec: [Double] = []
            vec.reserveCapacity(featureOrder.count)
            for feature in featureOrder {
                if numericSet.contains(feature) {
                    let raw = idx[feature].flatMap { $0 < row.count ? row[$0] : nil }
                    vec.append(standardizedNumeric(feature, raw))
                } else if feature.hasPrefix("sex_") {
                    let expected = feature.replacingOccurrences(of: "sex_", with: "")
                    vec.append(sex == expected ? 1.0 : 0.0)
                } else if feature.hasPrefix("ethnicity_") {
                    let expected = feature.replacingOccurrences(of: "ethnicity_", with: "")
                    vec.append(ethnicity == expected ? 1.0 : 0.0)
                } else {
                    vec.append(0.0)
                }
            }
            matrix.append(vec)
        }

        referenceMatrix = matrix
        return matrix
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inQuotes = false

        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if ch == "\"" {
                inQuotes.toggle()
                i = line.index(after: i)
                continue
            }
            if ch == "," && !inQuotes {
                out.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                i = line.index(after: i)
                continue
            }
            current.append(ch)
            i = line.index(after: i)
        }
        out.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return out
    }

    private func knnImpute(_ vec: inout [Double], missingIndices: [Int], reference: [[Double]], k: Int) {
        let present = vec.enumerated().compactMap { (i, v) -> Int? in
            if v.isNaN { return nil }
            if v.isFinite { return i }
            return nil
        }

        // If *everything* is missing (unlikely), just fill 0s.
        guard !present.isEmpty else {
            for i in missingIndices { vec[i] = 0.0 }
            return
        }

        // Compute distances to all reference rows
        var dists: [(Double, Int)] = []
        dists.reserveCapacity(reference.count)

        for (idx, r) in reference.enumerated() {
            var sum = 0.0
            for j in present {
                let diff = vec[j] - r[j]
                sum += diff * diff
            }
            let dist = sqrt(sum / Double(present.count))
            dists.append((dist, idx))
        }

        dists.sort { $0.0 < $1.0 }
        let neighbors = dists.prefix(min(k, dists.count))

        let eps = 1e-6
        for mi in missingIndices {
            var num = 0.0
            var den = 0.0
            for (dist, rIdx) in neighbors {
                let w = 1.0 / max(dist, eps)
                num += w * reference[rIdx][mi]
                den += w
            }
            vec[mi] = den > 0 ? (num / den) : 0.0
        }
    }
}


