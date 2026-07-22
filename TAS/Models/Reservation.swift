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
    var assigneeId: Int?
    var status: ReservationStatus?
    var price: Int?
    var memo: String?
    var paymentCompleted: Bool?
    var paymentMethod: PaymentMethod?
    var paymentEntries: [PaymentEntry]?
    var pointEarned: Int?
    var naverBookingId: String?
    var naverBookingUrl: String?
    var naverDeposit: Int?
    var channel: ReservationChannel?

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
