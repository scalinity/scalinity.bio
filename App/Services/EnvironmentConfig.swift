import CryptoKit
import Foundation

@MainActor
final class EnvironmentConfig: ObservableObject {
    enum SecretKey: String, CaseIterable, Identifiable {
        case openRouterApiKey = "OPENROUTER_API_KEY"
        case entrezApiKey = "ENTREZ_API_KEY"
        case databaseEncryptionKey = "DATABASE_ENCRYPTION_KEY"

        var id: String { rawValue }
    }

    private let keychainServiceName = "bio.scalinity.secrets"

    @Published private(set) var secrets: [SecretKey: String] = [:]

    init() {
        reload()
    }

    func reload() {
        var next: [SecretKey: String] = [:]
        for key in SecretKey.allCases {
            if let env = ProcessInfo.processInfo.environment[key.rawValue], !env.isEmpty {
                next[key] = env
                continue
            }
            do {
                if let kc = try KeychainService.getString(account: key.rawValue, service: keychainServiceName), !kc.isEmpty {
                    next[key] = kc
                }
            } catch {
                // Ignore keychain failures; app can still run with env vars.
            }
        }
        secrets = next
    }

    func setSecret(_ value: String, for key: SecretKey) throws {
        try KeychainService.setString(value, account: key.rawValue, service: keychainServiceName)
        reload()
    }

    func secret(_ key: SecretKey) -> String? {
        secrets[key]
    }

    /// Returns a 32-byte key suitable for AES-GCM.
    func databaseKeyMaterial() throws -> Data {
        guard let raw = secret(.databaseEncryptionKey), !raw.isEmpty else {
            throw InputValidationError.missingRequiredField(SecretKey.databaseEncryptionKey.rawValue)
        }

        if let data = Data(hexString: raw), data.count >= 32 {
            return data.prefix(32)
        }
        if let data = Data(base64Encoded: raw), data.count >= 32 {
            return data.prefix(32)
        }

        // Derive from string via SHA-256
        let digest = SHA256.hash(data: Data(raw.utf8))
        return Data(digest)
    }
}

private extension Data {
    init?(hexString: String) {
        let s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count % 2 == 0 else { return nil }

        var out = Data(capacity: s.count / 2)
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            let byteString = s[idx..<next]
            guard let b = UInt8(byteString, radix: 16) else { return nil }
            out.append(b)
            idx = next
        }
        self = out
    }
}


