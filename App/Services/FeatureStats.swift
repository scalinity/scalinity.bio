import Foundation

struct FeatureStats: Codable {
    struct Bounds: Codable {
        let p01: Double
        let p99: Double
    }

    let numericColumns: [String]
    let categorical: [String: [String]]
    let winsorP01P99: [String: Bounds]
    let mean: [String: Double]
    let std: [String: Double]
    let featureOrder: [String]

    enum CodingKeys: String, CodingKey {
        case numericColumns = "numeric_columns"
        case categorical
        case winsorP01P99 = "winsor_p01_p99"
        case mean
        case std
        case featureOrder = "feature_order"
    }

    static func loadFromBundle() throws -> FeatureStats {
        guard let url = Bundle.module.url(forResource: "FeatureStats", withExtension: "json") else {
            throw InputValidationError.parseFailed("Missing bundled resource: Resources/FeatureStats.json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FeatureStats.self, from: data)
    }
}


