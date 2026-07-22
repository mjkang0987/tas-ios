import Foundation
import Security

/// 모바일 access 토큰을 Keychain에 안전 보관한다.
/// clipnote의 Supabase Keychain 보관 역할에 대응(여기선 자체 Bearer 토큰).
struct KeychainTokenStore {
    static let shared = KeychainTokenStore()

    private let service = "kr.co.takeaseat.app"
    private let account = "mobile-access-token"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    var token: String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        // 기존 항목 제거 후 삽입(업서트).
        SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
