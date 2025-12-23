import Foundation

enum Sex: String, Codable, CaseIterable, Identifiable {
    case female
    case male

    var id: String { rawValue }
}



