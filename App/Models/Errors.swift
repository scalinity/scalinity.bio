import Foundation

enum InputValidationError: Error, LocalizedError, Equatable {
    case missingRequiredField(String)
    case invalidValue(field: String, message: String)
    case unsupportedFileType(String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidValue(let field, let message):
            return "Invalid value for \(field): \(message)"
        case .unsupportedFileType(let ext):
            return "Unsupported file type: \(ext)"
        case .parseFailed(let message):
            return "Failed to parse input: \(message)"
        }
    }
}


