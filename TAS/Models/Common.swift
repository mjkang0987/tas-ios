import Foundation

// MARK: - Shared enums mirroring the takeaseat (TAS) web domain
// Reference: client/features/*/model.ts in the `tas` service repository.

/// 예약 상태 — reservations/model.ts `ReservationStatus`
enum ReservationStatus: String, Codable, CaseIterable, Hashable {
    case active
    case completed
    case cancelled
    case noshow
    case requested

    var label: String {
        switch self {
        case .active: return "예약"
        case .completed: return "완료"
        case .cancelled: return "취소"
        case .noshow: return "노쇼"
        case .requested: return "요청"
        }
    }
}

/// 예약 경로 — reservations/model.ts `ReservationChannel`
enum ReservationChannel: String, Codable, Hashable {
    case naver = "네이버예약"
    case walkIn = "현장방문"
    case phone = "전화예약"
    case online = "온라인예약"
}

/// 결제 수단 — reservations/model.ts `PaymentMethod`
enum PaymentMethod: String, Codable, Hashable {
    case cash = "현금"
    case cashReceipt = "현금+현금영수증"
    case card = "카드"
    case naverPay = "네이버페이"
    case localCurrency = "지역화폐"
    case localCurrencyReceipt = "지역화폐+현금영수증"
    case giftCard = "상품권"
    case points = "적립금"
    case discount = "할인"
    case naverDeposit = "네이버 예약금"
}

/// 담당자(디자이너) 재직 상태 — assignees/model.ts `AssigneeStatus`
enum AssigneeStatus: String, Codable, Hashable {
    case active = "재직"
    case leave = "휴직"
    case retired = "퇴직"
}

/// 권한 — server/auth/roles.ts (owner > manager > staff)
enum AppRole: String, Codable, Hashable {
    case owner
    case manager
    case staff
}
