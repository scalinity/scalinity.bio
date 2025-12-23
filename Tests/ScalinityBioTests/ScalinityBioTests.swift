import XCTest
@testable import ScalinityBio

final class ScalinityBioTests: XCTestCase {
    func testDataImportCSV() throws {
        let csv = "chronological_age,sex,ethnicity,bmi\n52,female,European,26.1\n"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)

        let profile = try DataImportService().importProfile(from: url)
        XCTAssertEqual(Int(profile.chronologicalAge), 52)
        XCTAssertEqual(profile.sex, .female)
        XCTAssertEqual(profile.ethnicity, "European")
        XCTAssertEqual(profile.bmi ?? 0, 26.1, accuracy: 0.001)
    }

    func testBAScoreMapping() {
        XCTAssertEqual(BioAgeEngine.baScore(deltaYears: 0), 50.0, accuracy: 0.001)
        XCTAssertTrue(BioAgeEngine.baScore(deltaYears: 10) > 50.0)
        XCTAssertTrue(BioAgeEngine.baScore(deltaYears: -10) < 50.0)
    }

    func testPreprocessingVectorLengthAndFinite() async throws {
        let pre = try PreprocessingService()
        let stats = try FeatureStats.loadFromBundle()

        let profile = OmicsProfile(
            chronologicalAge: 52,
            sex: .female,
            ethnicity: "European",
            bmi: 26.1,
            dietScore: 6,
            exerciseScore: 5,
            sleepScore: 6,
            comorbidityDiabetes: false,
            biomarkers: [
                "metab_glucose_mg_dL": 102.0,
                "crp_mg_L": 2.8,
            ]
        )

        let vec = try await pre.makeFeatureVector(profile: profile)
        XCTAssertEqual(vec.count, stats.featureOrder.count)
        XCTAssertFalse(vec.contains(where: { $0.isNaN || !$0.isFinite }))
    }

    func testEncryptedSQLiteRoundTrip() async throws {
        let key = Data(repeating: 7, count: 32)
        let store = try EncryptedSQLiteStore(keyMaterial: key)

        let payload = Data("hello".utf8)
        try await store.put(type: "test", id: "id1", payload: payload)
        let out = try await store.get(type: "test", id: "id1")

        XCTAssertEqual(out, payload)
    }

    func testBioAgePredictionIsReasonable() async throws {
        let pre = try PreprocessingService()
        let model = try BioAgeModelService()
        let engine = BioAgeEngine(preprocessor: pre, model: model)

        let profile = OmicsProfile(
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

        let result = try await engine.evaluate(profile: profile)
        XCTAssertTrue(result.predictedBiologicalAge.isFinite)
        XCTAssertTrue(result.predictedBiologicalAge > 20 && result.predictedBiologicalAge < 100)
        XCTAssertTrue(abs(result.deltaYears) < 30)
    }
}


