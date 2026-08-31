import Foundation

/// 결제 항목 — reservations/model.ts `PaymentEntry`
struct PaymentEntry: Codable, Hashable {
    var method: PaymentMethod
    var amount: Int
}

/// 예약 — reservations/model.ts `Reservation`
/// `id`/`customerId`/`assigneeId` are the frontend legacyId integers used across the `/api/*` surface.
struct Reservation: Codable, Identifiable, Hashable {
    var id: Int
    var date: String            // "YYYY-MM-DD" (KST)
    var startTime: String       // "HH:mm"
    var endTime: String         // "HH:mm"
    var service: String
    var customerId: Int
    var assigneeId: Int? = nil
    var status: ReservationStatus? = nil
    var price: Int? = nil
    var memo: String? = nil
    var paymentCompleted: Bool? = nil
    var paymentMethod: PaymentMethod? = nil
    var paymentEntries: [PaymentEntry]? = nil
    var pointEarned: Int? = nil
    var naverBookingId: String? = nil
    var naverBookingUrl: String? = nil
    var naverDeposit: Int? = nil
    var channel: ReservationChannel? = nil

    /// hasCompletedPayment(reservation) — reservations/model.ts
    var hasCompletedPayment: Bool {
        if let entries = paymentEntries, !entries.isEmpty { return true }
        return paymentCompleted == true
    }

    var isOnline: Bool { channel == .online }

    /// 뱃지 표시 상태 — 웹 `getReservationState`(ReservationInfoCard)와 동일 규칙.
    /// 결제 완료면 '결제완료', 아니면 '예약'으로 파생한다.
    var displayState: ReservationDisplayState {
        switch status {
        case .cancelled: return .cancelled
        case .noshow: return .noshow
        case .requested: return .requested
        default: return hasCompletedPayment ? .paid : .booked
        }
    }
}

extension Reservation {
    /// 이 예약이 `other`보다 **과거**인가 — 날짜, 같으면 시작시간.
    /// 예약을 시간순으로 놓는 규칙은 여기 한 곳만 둔다. 정렬(`sorted`)과 최신 건 찾기(`max`)가
    /// 서로 다른 기준을 쓰면 화면마다 순서가 달라진다.
    func precedes(_ other: Reservation) -> Bool {
        (date, startTime) < (other.date, other.startTime)
    }
}

/// 예약 카드/리스트 뱃지 상태 — 웹 `RESERVATION_STATUS_BADGE_STYLES` 매핑에 대응.
enum ReservationDisplayState {
    case booked, paid, cancelled, noshow, requested

    var label: String {
        switch self {
        case .booked: return "예약"
        case .paid: return "결제완료"
        case .cancelled: return "취소"
        case .noshow: return "노쇼"
        case .requested: return "신청"
        }
    }
}

/// 예약 변경 이력 — reservations/model.ts `ReservationHistoryEntry`
struct ReservationHistoryEntry: Codable, Hashable {
    var reservationId: Int
    var before: Reservation
    var after: Reservation
    var timestamp: String
}

/// GET /api/reservations response envelope.
struct ReservationsResponse: Codable {
    var reservations: [Reservation]
    var history: [ReservationHistoryEntry]?
}
