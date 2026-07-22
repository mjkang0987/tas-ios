import Foundation

/// 매장 — GET /api/store (server/api/store.ts) 및 세션의 매장 컨텍스트.
/// 웹 스키마(Store 모델)의 앱에서 필요한 필드만 추립니다.
struct Store: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var shopType: String?
    var onboarded: Bool?
    var usePointSystem: Bool?
    var useMembershipSystem: Bool?
    var useCouponSystem: Bool?
    var useOnlineBooking: Bool?
    var bookingSlug: String?
    var categoryBaseColors: [String: String]?
}

/// 로그인 세션 사용자 — server/auth/api-session.ts `ApiSession`
struct SessionUser: Codable, Hashable {
    var id: String
    var storeId: String
    var role: AppRole
    var name: String?
    var email: String?
    var nickname: String?
}
