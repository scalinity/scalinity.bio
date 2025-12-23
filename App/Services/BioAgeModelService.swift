import CoreML
import Foundation

final class BioAgeModelService {
    private let model: MLModel
    private let outputKey: String

    init(modelName: String = "BioAgeRegressor", outputKey: String = "biological_age") throws {
        self.outputKey = outputKey

        // Workaround for Xcode Analyze: avoid bundling a `.mlmodel` resource (it can trigger codegen language detection).
        // We bundle `*.mlmodeldata` instead and compile it at runtime.
        if let mlmodelDataURL = Bundle.module.url(forResource: modelName, withExtension: "mlmodeldata", subdirectory: "Models")
            ?? Bundle.module.url(forResource: modelName, withExtension: "mlmodeldata") {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mlmodel")
            try FileManager.default.copyItem(at: mlmodelDataURL, to: tmp)
            let compiledURL = try MLModel.compileModel(at: tmp)
            self.model = try MLModel(contentsOf: compiledURL)
            return
        }

        // Back-compat: if a `.mlmodel` exists, compile on first run.
        if let mlmodelURL = Bundle.module.url(forResource: modelName, withExtension: "mlmodel", subdirectory: "Models")
            ?? Bundle.module.url(forResource: modelName, withExtension: "mlmodel") {
            let compiledURL = try MLModel.compileModel(at: mlmodelURL)
            self.model = try MLModel(contentsOf: compiledURL)
            return
        }

        throw InputValidationError.parseFailed("Missing bundled CoreML model: \(modelName).mlmodeldata")
    }

    func predictBiologicalAge(modelInput: [String: Double]) throws -> Double {
        let dict: [String: MLFeatureValue] = modelInput.mapValues { MLFeatureValue(double: $0) }
        let provider = try MLDictionaryFeatureProvider(dictionary: dict)
        let out = try model.prediction(from: provider)

        guard let value = out.featureValue(for: outputKey)?.doubleValue else {
            throw InputValidationError.parseFailed("CoreML output is missing expected key: \(outputKey)")
        }
        return value
    }
}


