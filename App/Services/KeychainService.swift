import Foundation
import Security

enum KeychainService {
    static func setString(_ value: String, account: String, service: String) throws {
        try setData(Data(value.utf8), account: account, service: service)
    }

    static func getString(account: String, service: String) throws -> String? {
        guard let data = try getData(account: account, service: service) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setData(_ data: Data, account: String, service: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
            kSecAttrService: service,
        ]

        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData] = data
        insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "KeychainService", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain write failed (\(status))."])
        }
    }

    static func getData(account: String, service: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw NSError(domain: "KeychainService", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain read failed (\(status))."])
        }
        return item as? Data
    }
}


