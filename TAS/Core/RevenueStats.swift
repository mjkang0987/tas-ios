import Foundation

/// 매출 집계 — 웹 `client/utils/revenue.ts` 이식(순수 로직만).
///
/// 화면(`RevenueView`)에 두면 드릴다운 목록과 KPI가 서로 다른 기준을 쓰게 되기 쉬워
/// 판정·집계는 전부 여기에 모은다. `PointMath`·`CustomerStats`와 같은 자리다.
enum RevenueStats {

    /// 매출 대상 판정 기준 — 웹 `RevenueFilterMode`.
    enum FilterMode: String, CaseIterable {
        /// 예약완료된 건만 — 웹 `isCompletedReservationTarget`.
        case completed = "예약완료매출"
        /// 취소·노쇼·신청을 뺀 모든 건 — 웹 `isBookedReservationTarget`.
        case booked = "예약매출"
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
            // 할인·적립금·회원권은 받은 돈이 아니다 — 결제완료 합계에서 뺀다(웹 getPaidBreakdown)
            return entries.filter { $0.amount > 0 && !nonRevenueMethods.contains($0.method) }.map { ($0.method, $0.amount) }
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
    /// 28~29일은 `28/30`이 0이라 최소 1달로 올린다 — 웹도 v0.64.10부터 `Math.max(floor(days/30), 1)`로 같다.
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

    // MARK: - 매출 금액 (웹 `resolveRevenue`)

    /// 매출로 치지 않는 결제수단 — 웹 `NON_REVENUE_PAYMENT_METHODS`: 깎아 준 돈(할인)·이미 받은 돈(적립금·회원권).
    static let nonRevenueMethods: Set<PaymentMethod> = [.discount, .points, .membership]

    /// 서비스 금액 — 예약가, 없으면 서비스별 카탈로그 가격의 합(웹 `resolvePrice` → `sumPrice(parseServiceString)`).
    static func price(_ r: Reservation, priceByName: [String: Int]) -> Int {
        r.price ?? ServiceColor.parseServiceString(r.service, knownNames: Set(priceByName.keys))
            .reduce(0) { $0 + (priceByName[$1] ?? 0) }
    }

    /// 예약 매출 — 서비스 금액에서 할인·적립금·회원권으로 낸 만큼 뺀 값, 0 아래로 안 간다(웹 `getReservationRevenue`).
    static func revenue(_ r: Reservation, price: Int) -> Int {
        let deducted = (r.paymentEntries ?? [])
            .filter { $0.amount > 0 && nonRevenueMethods.contains($0.method) }
            .reduce(0) { $0 + $1.amount }
        return max(price - deducted, 0)
    }

    // MARK: - 매장 판매(충전) — 웹 `features/sales` `buildStoreSales`

    /// 예약이 아닌 매출 한 건 — 지금은 적립금 충전뿐(회원권 판매는 서버 전용이라 앱에 데이터가 없다).
    struct StoreSale: Identifiable, Equatable {
        let id: String
        let date: String            // KST "YYYY-MM-DD"
        let amount: Int             // 받은 돈(보너스 제외)
        let method: PaymentMethod?
        let customerId: Int
    }

    /// 고객 적립금 이력의 충전(받은 돈이 있는 것)만 매출로 — 받은 금액이 없는 옛 충전은 뺀다. 날짜는 매장 기준(KST).
    static func storeSales(_ customers: [Customer]) -> [StoreSale] {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return customers.flatMap { customer in
            (customer.pointHistories ?? []).compactMap { h -> StoreSale? in
                guard h.type == .recharge, let paid = h.paidAmount, paid > 0,
                      let at = withFrac.date(from: h.createdAt) ?? plain.date(from: h.createdAt) else { return nil }
                return StoreSale(id: h.id, date: KST.dayKey.string(from: at), amount: paid,
                                 method: h.paymentMethod, customerId: customer.id)
            }
        }
    }

    // MARK: - 기간 (웹 `revenueChartUtils` clampRevenueRange·handleMoveRange)

    /// 최대 기간 — 넘으면 끝은 두고 시작을 당긴다.
    static let maxRangeDays = 365

    enum QuickRange: String, CaseIterable {
        case today = "오늘", week = "7일", month = "30일"
        var days: Int { switch self { case .today: 0; case .week: 7; case .month: 30 } }
    }

    /// 빠른 선택 — 오늘·7일(오늘-7 ~ 오늘)·30일(오늘-30 ~ 오늘). 웹과 같이 7일은 8칸이다.
    static func quickRange(_ q: QuickRange, today: Date) -> (Date, Date) {
        (KST.calendar.date(byAdding: .day, value: -q.days, to: today) ?? today, today)
    }

    /// 지금 기간이 빠른 선택 중 하나와 똑같으면 그것(칩을 켠다).
    static func quickRangeOf(_ start: Date, _ end: Date, today: Date) -> QuickRange? {
        QuickRange.allCases.first { q in
            let r = quickRange(q, today: today)
            return KST.calendar.isDate(r.0, inSameDayAs: start) && KST.calendar.isDate(r.1, inSameDayAs: end)
        }
    }

    static func days(from a: Date, to b: Date) -> Int {
        KST.calendar.dateComponents([.day], from: KST.calendar.startOfDay(for: a), to: KST.calendar.startOfDay(for: b)).day ?? 0
    }

    /// 365일 넘으면 끝을 두고 시작을 당긴다(시작이 끝보다 늦게 골라져 있으면 끝 쪽을).
    static func clampRange(_ start: Date, _ end: Date) -> (Date, Date) {
        let (from, to) = start <= end ? (start, end) : (end, start)
        guard days(from: from, to: to) > maxRangeDays,
              let clamped = KST.calendar.date(byAdding: .day, value: -maxRangeDays, to: to) else { return (start, end) }
        return start <= end ? (clamped, end) : (start, clamped)
    }

    /// 앞뒤 이동 — 오늘이면 하루씩, 7일·30일이면 그만큼, 직접 고른 기간이면 그 길이만큼. 앞으로는 오늘을 넘지 않는다.
    static func moveRange(_ start: Date, _ end: Date, forward: Bool, today: Date) -> (Date, Date) {
        let cal = KST.calendar
        let (from, to) = start <= end ? (start, end) : (end, start)
        let quick = quickRangeOf(start, end, today: today)
        let span = days(from: from, to: to)
        if quick == .today {
            let next = min(cal.date(byAdding: .day, value: forward ? 1 : -1, to: to) ?? to, today)
            return (next, next)
        }
        let shift = quick.map(\.days) ?? max(span, 1)
        if !forward {
            return (cal.date(byAdding: .day, value: -shift, to: from) ?? from, cal.date(byAdding: .day, value: -shift, to: to) ?? to)
        }
        let newEnd = min(cal.date(byAdding: .day, value: shift, to: to) ?? to, today)
        return (cal.date(byAdding: .day, value: -span, to: newEnd) ?? newEnd, newEnd)
    }
}
