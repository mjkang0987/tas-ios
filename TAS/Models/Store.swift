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
    // 영업 스케줄 — GET /api/store (server/db/mappers.ts dbStoreToFrontend)
    var businessHours: BusinessHours? = nil
    var closedDates: [String]? = nil          // "YYYY-MM-DD" 특정 휴무일
    var closedWeekdays: [Int]? = nil          // 0=월…6=일 정기 휴무 요일
}

/// 매장 영업시간(전체 공통 오픈/마감) — storeSettings.businessHours.
struct BusinessHours: Codable, Hashable {
    var start: String   // "HH:mm"
    var end: String     // "HH:mm"
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
