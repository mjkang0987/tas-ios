import Foundation

/// 모바일 access 토큰(JWT) payload를 읽는다. 서명 검증은 서버 몫이고,
/// 앱은 표시용 클레임(userId/storeId/role)만 디코드해 세션 컨텍스트를 만든다.
enum MobileToken {
    struct Claims {
        let userId: String
        let storeId: String
        let role: AppRole
    }

    static func decode(_ token: String) -> Claims? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }

        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userId = object["userId"] as? String,
              let storeId = object["storeId"] as? String,
              let roleRaw = object["role"] as? String,
              let role = AppRole(rawValue: roleRaw) else { return nil }

        return Claims(userId: userId, storeId: storeId, role: role)
    }
}
