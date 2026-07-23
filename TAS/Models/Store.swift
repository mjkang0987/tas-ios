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
    var pointSettings: PointSettings? = nil
}

/// 매장 영업시간(전체 공통 오픈/마감) — storeSettings.businessHours.
struct BusinessHours: Codable, Hashable {
    var start: String   // "HH:mm"
    var end: String     // "HH:mm"
}

/// 적립금 설정 — storeSettings.pointSettings.
struct PointSettings: Codable, Hashable {
    var enableServiceRate: Bool = false   // 결제 시 적립률 적립 사용
    var enableRecharge: Bool = false      // 충전(선불) 사용
    var serviceRate: Int = 0              // 적립률(%)
    var rechargeRules: [RechargeRule] = []
}

/// 충전 규칙 — {baseAmount 충전 시 bonusAmount 추가 적립}.
struct RechargeRule: Codable, Hashable {
    var baseAmount: Int
    var bonusAmount: Int
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
