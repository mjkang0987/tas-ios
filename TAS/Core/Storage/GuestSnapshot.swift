import Foundation

/// 게스트(오프라인) 로컬 DB 스냅샷 — 웹 `lib/local-db.ts`의 `LocalDbSnapshot` 미러링.
///
/// 로그인 시 `/api/migrate-local` payload로 그대로 넘길 수 있도록 필드명을 웹과 맞춘다.
/// (storeSettings 상세는 매장설정 쓰기 단계에서 추가 예정 — migrate payload엔 불필요.)
struct GuestSnapshot: Codable {
    var customers: [Customer] = []
    var reservations: [Reservation] = []
    var history: [ReservationHistoryEntry] = []
    var services: [ServiceItem] = []
    var categoryBaseColors: [String: String] = [:]
    var assignees: [Assignee] = []
    var onboarded: Bool = false
    var storeName: String?
    var shopType: String?
    var usePointSystem: Bool?
    var useMembershipSystem: Bool?
    var useCouponSystem: Bool?
    var useOnlineBooking: Bool?
    /// 동의한 약관 버전(웹 `guestTermsVersion`). 현재 버전과 같아야 진입 허용.
    var termsAgreedVersion: String?
    // 영업 스케줄(웹 storeSettings)
    var businessHours: BusinessHours?
    var closedDates: [String] = []
    var closedWeekdays: [Int] = []
    var pointSettings: PointSettings?
    var notices: [StoreNotice] = []
    var couponProducts: [CouponProduct] = []
    var membershipProducts: [MembershipProduct] = []

    /// 웹 `hasGuestData()` — 온보딩 완료했거나 실제 데이터가 하나라도 있으면 true.
    var hasData: Bool {
        onboarded
            || !customers.isEmpty
            || !reservations.isEmpty
            || !assignees.isEmpty
            || !services.isEmpty
    }
}
