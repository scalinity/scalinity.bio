import Foundation

struct DataImportService {
    func importProfile(from url: URL) throws -> OmicsProfile {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "json":
            return try importJSON(url: url)
        case "csv":
            return try importCSV(url: url)
        default:
            throw InputValidationError.unsupportedFileType(ext)
        }
    }

    // MARK: - JSON

    private func importJSON(url: URL) throws -> OmicsProfile {
        let data = try Data(contentsOf: url)
        let obj = try JSONSerialization.jsonObject(with: data)

        guard let top = obj as? [String: Any] else {
            throw InputValidationError.parseFailed("Top-level JSON must be an object.")
        }

        let dict: [String: Any]
        if let nested = top["profile"] as? [String: Any] {
            dict = nested
        } else {
            dict = top
        }

        return try parseDictionary(dict)
    }

    // MARK: - CSV

    private func importCSV(url: URL) throws -> OmicsProfile {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard lines.count >= 2 else {
            throw InputValidationError.parseFailed("CSV must have a header row and at least one data row.")
        }

        let header = parseCSVLine(lines[0])
        let values = parseCSVLine(lines[1])
        guard header.count == values.count else {
            throw InputValidationError.parseFailed("CSV header and first row column counts do not match.")
        }

        var dict: [String: Any] = [:]
        for (k, v) in zip(header, values) {
            dict[k] = v
        }
        return try parseDictionary(dict)
    }

    /// Minimal CSV line parser with support for quoted fields.
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

    // MARK: - Dictionary → OmicsProfile

    private func parseDictionary(_ dict: [String: Any]) throws -> OmicsProfile {
        func string(_ key: String, aliases: [String] = []) -> String? {
            if let v = dict[key] { return "\(v)".trimmingCharacters(in: .whitespacesAndNewlines) }
            for a in aliases {
                if let v = dict[a] { return "\(v)".trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            return nil
        }

        func double(_ key: String, aliases: [String] = []) -> Double? {
            if let v = dict[key] { return parseDouble(v) }
            for a in aliases {
                if let v = dict[a] { return parseDouble(v) }
            }
            return nil
        }

        let age = double("chronological_age", aliases: ["age"])
        guard let age else { throw InputValidationError.missingRequiredField("chronological_age") }
        guard age >= 0, age <= 120 else { throw InputValidationError.invalidValue(field: "chronological_age", message: "must be between 0 and 120") }

        let sexRaw = string("sex")?.lowercased()
        guard let sexRaw else { throw InputValidationError.missingRequiredField("sex") }
        guard let sex = Sex(rawValue: sexRaw) else {
            throw InputValidationError.invalidValue(field: "sex", message: "must be one of: female, male")
        }

        let ethnicity = string("ethnicity")
        guard let ethnicity, !ethnicity.isEmpty else { throw InputValidationError.missingRequiredField("ethnicity") }

        let bmi = double("bmi")
        if let bmi, (bmi < 10 || bmi > 80) {
            throw InputValidationError.invalidValue(field: "bmi", message: "must be between 10 and 80")
        }

        let diet = double("diet_score")
        let exercise = double("exercise_score")
        let sleep = double("sleep_score")
        for (k, v) in [("diet_score", diet), ("exercise_score", exercise), ("sleep_score", sleep)] {
            if let v, (v < 1 || v > 10) {
                throw InputValidationError.invalidValue(field: k, message: "must be between 1 and 10")
            }
        }

        let diabetesVal = dict["comorbidity_diabetes"]
        let diabetes: Bool = {
            if let b = diabetesVal as? Bool { return b }
            if let d = parseDouble(diabetesVal) { return d >= 0.5 }
            if let s = diabetesVal as? String, !s.isEmpty { return (Double(s) ?? 0.0) >= 0.5 }
            return false
        }()

        // Treat all other numeric-ish fields as biomarker values.
        var biomarkers: [String: Double] = [:]
        for (k, v) in dict {
            let key = k.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty { continue }

            if ["chronological_age", "age", "sex", "ethnicity", "bmi", "diet_score", "exercise_score", "sleep_score", "comorbidity_diabetes"].contains(key) {
                continue
            }
            if let d = parseDouble(v) {
                biomarkers[key] = d
            }
        }

        return OmicsProfile(
            chronologicalAge: age,
            sex: sex,
            ethnicity: ethnicity,
            bmi: bmi,
            dietScore: diet,
            exerciseScore: exercise,
            sleepScore: sleep,
            comorbidityDiabetes: diabetes,
            biomarkers: biomarkers
        )
    }

    private func parseDouble(_ any: Any?) -> Double? {
        switch any {
        case let d as Double:
            return d
        case let i as Int:
            return Double(i)
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            return Double(t)
        default:
            return nil
        }
    }
}



