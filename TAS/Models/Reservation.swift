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
