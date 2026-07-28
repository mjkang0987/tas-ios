import Foundation

/// 공개(고객) 온라인 예약 규칙 — 웹 `store-settings/model.ts` `BookingSettings` 이식.
///
/// `GET /api/store` 응답의 최상위 `bookingSettings`로 오고, 저장은
/// `PATCH /api/store`(`bookingSlug` + `bookingSettings`). 공개 예약 페이지는 웹 전용이라
/// 앱은 **설정만** 담당한다(게스트 모드는 공개 페이지가 없어 로그인 전용).
struct BookingSettings: Codable, Hashable {
    var slotIntervalMin: Int = 30
    var minLeadMinutes: Int = 60
    var maxAdvanceDays: Int = 30
    var allowAssigneeChoice: Bool = true
    /// 고객 문의·개인정보 열람/삭제 요구를 받을 매장 연락처. **온라인예약 사용 시 필수**(서버 검증).
    /// 고객 tel과 달리 정규화하지 않고 입력 원문 그대로 저장한다 — 지역번호(02-1234-5678)·
    /// 대표번호(1588-0000)는 자릿수 규칙이 달라 휴대폰용 3-4-4로 재조립하면 깨진다.
    var contactTel: String?
    var noticeText: String?
    var doneText: String?
    var confirmText: String?
    var cancelText: String?
    /// 공개 노출 서비스명 화이트리스트. nil 또는 빈 배열이면 전체 노출.
    var bookableServiceNames: [String]?

    /// 서버 기본값 — 웹 `DEFAULT_BOOKING_SETTINGS`.
    static let fallback = BookingSettings()

    /// 예약 흐름 4단계 기본 안내문구 — 웹 `DEFAULT_BOOKING_TEXTS`.
    /// placeholder 예시가 아니라 **실제 값**이다(그대로 저장하면 고객에게 그대로 나간다).
    enum DefaultTexts {
        static let notice = "예약 신청 후 매장 확인을 거쳐 확정됩니다. 확정 결과는 예약 조회 페이지에서 확인하실 수 있습니다."
        static let done = "예약 신청이 접수되었습니다. 매장 확인 후 확정되며, 결과는 예약 조회 페이지에서 확인하실 수 있습니다."
        static let confirm = "예약이 확정되었습니다. 예약 시간에 맞춰 방문해 주세요. 변경이나 취소가 필요하시면 이 페이지에서 요청해 주세요."
        static let cancel = "예약이 취소되었습니다. 다시 예약을 원하시면 예약 페이지에서 새로 신청해 주세요."
    }

    /// 예약 시간 간격 선택지 — 웹 `SLOT_OPTIONS`.
    static let slotOptions = [10, 15, 20, 30, 60]

    /// 공개 URL 슬러그 — 웹 `BOOKING_SLUG_PATTERN`
    /// (소문자 영숫자·하이픈 3~32자, 하이픈으로 시작·끝 불가).
    static func isValidSlug(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9](?:[a-z0-9-]{1,30}[a-z0-9])$", options: .regularExpression) != nil
    }

    /// 매장 연락처 형식 — 서버 `store.ts` 검증(`^[0-9+\-()\s]{8,20}$`)과 동일.
    static func isValidContactTel(_ value: String) -> Bool {
        value.range(of: "^[0-9+\\-()\\s]{8,20}$", options: .regularExpression) != nil
    }

    /// 안내문구가 비어 있으면 기본 문구로 채워 보여준다 — 오너가 빈 칸을 마주하지 않게(웹 동일).
    func withDefaultTexts() -> BookingSettings {
        var copy = self
        copy.noticeText = noticeText ?? DefaultTexts.notice
        copy.doneText = doneText ?? DefaultTexts.done
        copy.confirmText = confirmText ?? DefaultTexts.confirm
        copy.cancelText = cancelText ?? DefaultTexts.cancel
        return copy
    }

    /// 누락 필드는 서버 기본값으로 — 마이그레이션 전 응답도 허용.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slotIntervalMin = try c.decodeIfPresent(Int.self, forKey: .slotIntervalMin) ?? 30
        minLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .minLeadMinutes) ?? 60
        maxAdvanceDays = try c.decodeIfPresent(Int.self, forKey: .maxAdvanceDays) ?? 30
        allowAssigneeChoice = try c.decodeIfPresent(Bool.self, forKey: .allowAssigneeChoice) ?? true
        contactTel = try c.decodeIfPresent(String.self, forKey: .contactTel)
        noticeText = try c.decodeIfPresent(String.self, forKey: .noticeText)
        doneText = try c.decodeIfPresent(String.self, forKey: .doneText)
        confirmText = try c.decodeIfPresent(String.self, forKey: .confirmText)
        cancelText = try c.decodeIfPresent(String.self, forKey: .cancelText)
        bookableServiceNames = try c.decodeIfPresent([String].self, forKey: .bookableServiceNames)
    }

    init() {}
}
