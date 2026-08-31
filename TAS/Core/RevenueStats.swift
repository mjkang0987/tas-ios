import Foundation

/// 매출 집계 — 웹 `client/utils/revenue.ts` 이식(순수 로직만).
///
/// 화면(`RevenueView`)에 두면 드릴다운 목록과 KPI가 서로 다른 기준을 쓰게 되기 쉬워
/// 판정·집계는 전부 여기에 모은다. `PointMath`·`CustomerStats`와 같은 자리다.
enum RevenueStats {

    /// 매출 대상 판정 기준 — 웹 `RevenueFilterMode`.
    enum FilterMode: String, CaseIterable {
        /// 예약완료된 건만 — 웹 `isCompletedReservationTarget`.
        case completed = "완료"
        /// 취소·노쇼·신청을 뺀 모든 건 — 웹 `isBookedReservationTarget`.
        case booked = "예약"
    }

    /// 웹 `isRevenueReservationTarget`.
    static func isTarget(_ reservation: Reservation, mode: FilterMode) -> Bool {
        switch mode {
        case .completed:
            return reservation.status == .completed
        case .booked:
            return reservation.status != .cancelled
                && reservation.status != .noshow
                && reservation.status != .requested
        }
    }

    /// 웹 `isPaidReservationTarget` — 결제완료 KPI의 대상.
    /// 취소·노쇼·신청은 제외하고, 결제 항목이 있으면 0원 초과가 하나라도 있어야 한다.
    static func isPaidTarget(_ reservation: Reservation) -> Bool {
        if reservation.status == .cancelled
            || reservation.status == .noshow
            || reservation.status == .requested { return false }

        if let entries = reservation.paymentEntries, !entries.isEmpty {
            return entries.contains { $0.amount > 0 }
        }
        return reservation.paymentCompleted == true
    }

    /// 웹 `resolvePaymentEntries` — 실제 결제된 금액 목록.
    /// 결제 항목이 없고 `paymentCompleted`면 예약 금액 전액을 그 수단으로 친다.
    static func paymentAmounts(_ reservation: Reservation, amount: Int) -> [(method: PaymentMethod, amount: Int)] {
        if let entries = reservation.paymentEntries, !entries.isEmpty {
            return entries.filter { $0.amount > 0 }.map { ($0.method, $0.amount) }
        }
        if reservation.paymentCompleted == true, let method = reservation.paymentMethod {
            return [(method, amount)]
        }
        return []
    }

    /// 결제완료 합계 — 웹 `RevenueInsights.paidTotal`.
    /// **대상 예약 전체**를 돌며 결제 금액을 더한다(결제 대상만 거른 뒤가 아니다 — 결과는 같다).
    static func paidTotal(_ reservations: [Reservation], amount: (Reservation) -> Int) -> Int {
        reservations.reduce(0) { sum, reservation in
            sum + paymentAmounts(reservation, amount: amount(reservation)).reduce(0) { $0 + $1.amount }
        }
    }

    // MARK: - 신규 / 재방문 고객

    /// 기간 안의 고객 한 명 — 웹 `RevenueMetricModal`의 `CustomerEntry`.
    struct CustomerVisit: Identifiable, Equatable {
        let customerId: Int
        /// 기간 안에서의 첫 방문일.
        let visitDate: String
        /// 재방문일 때 그 직전 방문일(신규면 nil).
        let prevVisitDate: String?
        var id: Int { customerId }
    }

    struct CustomerVisits: Equatable {
        var new: [CustomerVisit] = []
        var returning: [CustomerVisit] = []
    }

    /// 기간 안 고객을 신규/재방문으로 가른다 — 웹 `getRevenueInsights` + 메트릭 모달의 목록 구성.
    ///
    /// **첫 방문일은 기간이 아니라 전체 예약에서 구한다.** 기간 안만 보면 예전 고객이 전부
    /// 신규로 잡힌다. 두 인자 모두 `isTarget`으로 이미 걸러진 목록이어야 한다.
    /// - Parameters:
    ///   - periodTargets: 집계 기간 안의 대상 예약(날짜·시작시간 오름차순일 필요는 없다 — 여기서 정렬한다).
    ///   - allTargets: 기간과 무관한 전체 대상 예약.
    static func customerVisits(periodTargets: [Reservation], allTargets: [Reservation]) -> CustomerVisits {
        var firstVisit: [Int: String] = [:]
        var datesByCustomer: [Int: Set<String>] = [:]
        for reservation in allTargets {
            let current = firstVisit[reservation.customerId]
            if current == nil || reservation.date < current! {
                firstVisit[reservation.customerId] = reservation.date
            }
            datesByCustomer[reservation.customerId, default: []].insert(reservation.date)
        }

        var result = CustomerVisits()
        var seen = Set<Int>()
        for reservation in sortedChronologically(periodTargets) {
            guard !seen.contains(reservation.customerId) else { continue }
            seen.insert(reservation.customerId)

            guard let first = firstVisit[reservation.customerId] else { continue }
            if first == reservation.date {
                result.new.append(CustomerVisit(
                    customerId: reservation.customerId,
                    visitDate: reservation.date,
                    prevVisitDate: nil
                ))
            } else if first < reservation.date {
                let previous = (datesByCustomer[reservation.customerId] ?? [])
                    .filter { $0 < reservation.date }
                    .max()
                result.returning.append(CustomerVisit(
                    customerId: reservation.customerId,
                    visitDate: reservation.date,
                    prevVisitDate: previous
                ))
            }
        }
        return result
    }

    /// 웹 `formatVisitGap` — 이전 방문과의 간격 라벨("12일전"·"3주전"·"5달전"·"2년전").
    /// 경계는 웹 그대로다(7일 미만=일, 28일 미만=주, 365일 미만=달).
    ///
    /// **웹과 한 가지 다르다** — 웹은 28~29일에서 `floor(28/30)`이 0이라 "0달전"을 그린다.
    /// 그 자리만 1로 올린다(365~370일의 "1년전"과 같은 취급).
    static func visitGapLabel(from prevVisitDate: String, to visitDate: String) -> String? {
        guard let prev = KST.dayKey.date(from: prevVisitDate),
              let visit = KST.dayKey.date(from: visitDate) else { return nil }
        let days = Int((visit.timeIntervalSince(prev) / 86_400).rounded())

        if days < 7 { return "\(days)일전" }
        if days < 28 { return "\(days / 7)주전" }
        if days < 365 { return "\(max(1, days / 30))달전" }
        return "\(days / 365)년전"
    }

    /// 날짜·시작시간 오름차순 — 순서 규칙은 `Reservation.precedes` 한 곳에서 온다.
    static func sortedChronologically(_ reservations: [Reservation]) -> [Reservation] {
        reservations.sorted { $0.precedes($1) }
    }
}
