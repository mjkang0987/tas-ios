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
    /// 공개 예약 규칙 — 응답 최상위(storeSettings와 분리). 온라인예약 설정 화면에서 편집.
    var bookingSettings: BookingSettings? = nil

    // GET /api/store는 `name` 대신 `storeName`을 주고 `id`는 주지 않는다(웹 스키마).
    // 실제 매장 id는 JWT claims에서 가져오므로, 디코딩 시 id는 없어도 되게 한다.
    enum CodingKeys: String, CodingKey {
        case id
        case name = "storeName"
        case shopType, onboarded
        case usePointSystem, useMembershipSystem, useCouponSystem, useOnlineBooking
        case bookingSlug, categoryBaseColors
        case businessHours, closedDates, closedWeekdays, pointSettings, bookingSettings
    }
}

extension Store {
    /// 커스텀 디코더 — `storeName→name` 매핑, `id`/`name` 누락 허용.
    /// (extension에 두어 memberwise init·`GuestStore.syntheticStore`는 그대로 유지)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "매장"
        shopType = try c.decodeIfPresent(String.self, forKey: .shopType)
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded)
        usePointSystem = try c.decodeIfPresent(Bool.self, forKey: .usePointSystem)
        useMembershipSystem = try c.decodeIfPresent(Bool.self, forKey: .useMembershipSystem)
        useCouponSystem = try c.decodeIfPresent(Bool.self, forKey: .useCouponSystem)
        useOnlineBooking = try c.decodeIfPresent(Bool.self, forKey: .useOnlineBooking)
        bookingSlug = try c.decodeIfPresent(String.self, forKey: .bookingSlug)
        categoryBaseColors = try c.decodeIfPresent([String: String].self, forKey: .categoryBaseColors)
        businessHours = try c.decodeIfPresent(BusinessHours.self, forKey: .businessHours)
        closedDates = try c.decodeIfPresent([String].self, forKey: .closedDates)
        closedWeekdays = try c.decodeIfPresent([Int].self, forKey: .closedWeekdays)
        pointSettings = try c.decodeIfPresent(PointSettings.self, forKey: .pointSettings)
        bookingSettings = try c.decodeIfPresent(BookingSettings.self, forKey: .bookingSettings)
    }
}

/// 캘린더 휴무 표시 구분 — 웹 `getStoreClosedKind`(client/features/store-settings/model.ts) 이식.
/// 임시 휴업일(오너가 찍은 특정 날짜)과 정기 휴무(매주 요일)는 문구·색이 달라 종류까지 구분한다.
enum StoreClosedKind: Hashable {
    case date      // 임시 휴업일
    case weekday   // 정기 휴무

    /// 문구 — 웹과 같은 말을 쓴다. 화면 표시는 글자가 아니라 **틴트 + 테두리**이고,
    /// 이 문구는 VoiceOver·툴팁 등 접근성 경로에 쓴다(색만으로는 아무것도 전달되지 않는다).
    var label: String { self == .date ? "휴업일" : "정기휴무" }
}

extension Store {
    /// 해당 날짜가 휴무인지, 어떤 휴무인지. 둘 다 해당하면 **임시 휴업일이 이긴다**
    /// (오너가 직접 찍은 날이 정기 휴무보다 구체적인 의사표시 — 웹과 같은 규칙).
    func closedKind(on dateKey: String) -> StoreClosedKind? {
        if closedDates?.contains(dateKey) == true { return .date }
        guard let closedWeekdays, !closedWeekdays.isEmpty,
              let date = KST.dayKey.date(from: dateKey) else { return nil }

        // Calendar.weekday 는 1=일 … 7=토, 앱·웹 공통 dayIndex 는 0=월 … 6=일.
        let dayIndex = (KST.calendar.component(.weekday, from: date) + 5) % 7
        return closedWeekdays.contains(dayIndex) ? .weekday : nil
    }
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
