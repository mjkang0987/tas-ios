import XCTest
@testable import TAS

/// 매출 집계 순수 로직 — 웹 `client/utils/revenue.ts` 이식분 검증.
final class RevenueStatsTests: XCTestCase {

    private func res(
        _ id: Int,
        date: String,
        customerId: Int = 1,
        price: Int? = 10000,
        status: ReservationStatus? = .completed,
        startTime: String = "10:00",
        paymentCompleted: Bool? = nil,
        paymentMethod: PaymentMethod? = nil,
        paymentEntries: [PaymentEntry]? = nil
    ) -> Reservation {
        Reservation(
            id: id, date: date, startTime: startTime, endTime: "11:00",
            service: "컷", customerId: customerId, status: status, price: price,
            paymentCompleted: paymentCompleted, paymentMethod: paymentMethod,
            paymentEntries: paymentEntries
        )
    }

    // MARK: - 대상 판정

    func testCompletedModeTakesOnlyCompleted() {
        XCTAssertTrue(RevenueStats.isTarget(res(1, date: "2026-07-01", status: .completed), mode: .completed))
        XCTAssertFalse(RevenueStats.isTarget(res(2, date: "2026-07-01", status: .active), mode: .completed))
        XCTAssertFalse(RevenueStats.isTarget(res(3, date: "2026-07-01", status: nil), mode: .completed))
    }

    func testBookedModeDropsCancelledNoshowRequested() {
        XCTAssertTrue(RevenueStats.isTarget(res(1, date: "2026-07-01", status: .active), mode: .booked))
        XCTAssertTrue(RevenueStats.isTarget(res(2, date: "2026-07-01", status: .completed), mode: .booked))
        XCTAssertTrue(RevenueStats.isTarget(res(3, date: "2026-07-01", status: nil), mode: .booked))
        XCTAssertFalse(RevenueStats.isTarget(res(4, date: "2026-07-01", status: .cancelled), mode: .booked))
        XCTAssertFalse(RevenueStats.isTarget(res(5, date: "2026-07-01", status: .noshow), mode: .booked))
        XCTAssertFalse(RevenueStats.isTarget(res(6, date: "2026-07-01", status: .requested), mode: .booked))
    }

    // MARK: - 결제완료

    func testPaidTargetNeedsNonZeroEntryOrCompletedFlag() {
        // 결제 항목이 있으면 0원짜리만으로는 결제완료가 아니다.
        XCTAssertFalse(RevenueStats.isPaidTarget(res(1, date: "2026-07-01",
            paymentEntries: [PaymentEntry(method: .card, amount: 0)])))
        XCTAssertTrue(RevenueStats.isPaidTarget(res(2, date: "2026-07-01",
            paymentEntries: [PaymentEntry(method: .card, amount: 5000)])))
        XCTAssertTrue(RevenueStats.isPaidTarget(res(3, date: "2026-07-01", paymentCompleted: true)))
        XCTAssertFalse(RevenueStats.isPaidTarget(res(4, date: "2026-07-01")))
        // 취소·노쇼는 결제 표시가 남아 있어도 제외.
        XCTAssertFalse(RevenueStats.isPaidTarget(res(5, date: "2026-07-01",
            status: .cancelled, paymentCompleted: true)))
    }

    func testPaymentAmountsFallsBackToReservationPrice() {
        // 결제 항목이 없고 paymentCompleted면 예약 금액 전액을 그 수단으로 친다.
        let fallback = RevenueStats.paymentAmounts(
            res(1, date: "2026-07-01", paymentCompleted: true, paymentMethod: .cash),
            amount: 12000
        )
        XCTAssertEqual(fallback.count, 1)
        XCTAssertEqual(fallback.first?.method, .cash)
        XCTAssertEqual(fallback.first?.amount, 12000)

        // 결제수단이 없으면 폴백하지 않는다(웹과 동일).
        XCTAssertTrue(RevenueStats.paymentAmounts(
            res(2, date: "2026-07-01", paymentCompleted: true), amount: 12000).isEmpty)

        // 항목이 있으면 0원짜리는 빼고 항목 금액만 쓴다(예약 금액이 아니다).
        let entries = RevenueStats.paymentAmounts(
            res(3, date: "2026-07-01", paymentEntries: [
                PaymentEntry(method: .card, amount: 7000),
                PaymentEntry(method: .points, amount: 0),
            ]),
            amount: 99999
        )
        XCTAssertEqual(entries.map(\.amount), [7000])
    }

    func testPaidTotalSumsEntryAmounts() {
        let reservations = [
            res(1, date: "2026-07-01", paymentEntries: [
                PaymentEntry(method: .card, amount: 6000),
                PaymentEntry(method: .points, amount: 4000),
            ]),
            res(2, date: "2026-07-02", price: 3000, paymentCompleted: true, paymentMethod: .cash),
            res(3, date: "2026-07-03"),   // 미결제 → 0
        ]
        // 적립금 4,000 은 받은 돈이 아니라 빠진다(웹 getPaidBreakdown 의 isRevenuePaymentMethod) — 카드 6,000 + 현금 3,000
        XCTAssertEqual(RevenueStats.paidTotal(reservations) { $0.price ?? 0 }, 9000)
    }

    // MARK: - 신규 / 재방문

    func testCustomerVisitsSplitsByFirstVisitAcrossAllReservations() {
        // 고객 1: 기간 이전에 방문 이력 있음 → 재방문
        // 고객 2: 기간 안이 첫 방문 → 신규
        let all = [
            res(1, date: "2026-06-10", customerId: 1),
            res(2, date: "2026-07-05", customerId: 1),
            res(3, date: "2026-07-08", customerId: 2),
        ]
        let period = all.filter { $0.date.hasPrefix("2026-07") }
        let visits = RevenueStats.customerVisits(periodTargets: period, allTargets: all)

        XCTAssertEqual(visits.new.map(\.customerId), [2])
        XCTAssertEqual(visits.new.first?.visitDate, "2026-07-08")
        XCTAssertNil(visits.new.first?.prevVisitDate)

        XCTAssertEqual(visits.returning.map(\.customerId), [1])
        XCTAssertEqual(visits.returning.first?.visitDate, "2026-07-05")
        XCTAssertEqual(visits.returning.first?.prevVisitDate, "2026-06-10")
    }

    func testCustomerCountedOnceOnFirstVisitInPeriod() {
        let all = [
            res(1, date: "2026-07-20", customerId: 1, startTime: "09:00"),
            res(2, date: "2026-07-03", customerId: 1, startTime: "15:00"),
            res(3, date: "2026-07-03", customerId: 1, startTime: "09:00"),
        ]
        let visits = RevenueStats.customerVisits(periodTargets: all, allTargets: all)

        // 기간 안 첫 예약 한 건만 집계에 들어간다(정렬은 날짜 → 시작시간).
        XCTAssertEqual(visits.new.count, 1)
        XCTAssertEqual(visits.new.first?.visitDate, "2026-07-03")
        XCTAssertTrue(visits.returning.isEmpty)
    }

    func testPreviousVisitIsLatestBeforeThatVisit() {
        let all = [
            res(1, date: "2026-01-02", customerId: 7),
            res(2, date: "2026-05-20", customerId: 7),
            res(3, date: "2026-07-01", customerId: 7),
        ]
        let period = all.filter { $0.date.hasPrefix("2026-07") }
        let visits = RevenueStats.customerVisits(periodTargets: period, allTargets: all)

        XCTAssertEqual(visits.returning.first?.prevVisitDate, "2026-05-20")
    }

    // MARK: - 방문 간격 라벨

    func testVisitGapLabelBuckets() {
        XCTAssertEqual(RevenueStats.visitGapLabel(from: "2026-07-01", to: "2026-07-04"), "3일전")
        XCTAssertEqual(RevenueStats.visitGapLabel(from: "2026-07-01", to: "2026-07-08"), "1주전")   // 7일
        XCTAssertEqual(RevenueStats.visitGapLabel(from: "2026-07-01", to: "2026-07-25"), "3주전")   // 24일
        // 28일은 28/30이 0이라 최소 1달 — 웹(v0.64.10~)과 같다.
        XCTAssertEqual(RevenueStats.visitGapLabel(from: "2026-07-01", to: "2026-07-29"), "1달전")
        XCTAssertEqual(RevenueStats.visitGapLabel(from: "2026-01-01", to: "2026-07-01"), "6달전")   // 181일 → 181/30
        XCTAssertEqual(RevenueStats.visitGapLabel(from: "2024-07-01", to: "2026-07-01"), "2년전")
    }

    /// 서머타임 없는 KST라도 날짜 문자열이 깨지면 라벨을 만들지 않는다.
    func testVisitGapLabelIsNilForBadDate() {
        XCTAssertNil(RevenueStats.visitGapLabel(from: "2026-07", to: "2026-07-08"))
    }

    /// 예약 시간순 규칙은 `Reservation.precedes` 한 곳에서만 나온다
    /// (`RevenueStats.sortedChronologically`와 `CustomerStats.sortedFutureFirst`가 함께 쓴다).
    func testPrecedesComparesDateThenStartTime() {
        let early = res(1, date: "2026-07-01", startTime: "09:00")
        let sameDayLater = res(2, date: "2026-07-01", startTime: "15:00")
        let nextDay = res(3, date: "2026-07-02", startTime: "08:00")

        XCTAssertTrue(early.precedes(sameDayLater))
        XCTAssertFalse(sameDayLater.precedes(early))
        XCTAssertTrue(sameDayLater.precedes(nextDay))
        XCTAssertFalse(early.precedes(early))   // 같은 건은 앞서지 않는다

        // 두 방향 헬퍼가 같은 규칙을 쓴다.
        XCTAssertEqual(RevenueStats.sortedChronologically([nextDay, early, sameDayLater]).map(\.id), [1, 2, 3])
        XCTAssertEqual(CustomerStats.sortedFutureFirst([early, nextDay, sameDayLater]).map(\.id), [3, 2, 1])
    }

    func testSortedChronologicallyOrdersByDateThenStartTime() {
        let sorted = RevenueStats.sortedChronologically([
            res(1, date: "2026-07-02", startTime: "09:00"),
            res(2, date: "2026-07-01", startTime: "15:00"),
            res(3, date: "2026-07-01", startTime: "09:00"),
        ])
        XCTAssertEqual(sorted.map(\.id), [3, 2, 1])
    }

    // MARK: - 매출 금액·충전·기간 (웹 resolveRevenue · buildStoreSales · clampRevenueRange)

    func testRevenueSubtractsDiscountPointsAndMembershipButNotCash() {
        var r = res(1, date: "2026-10-13", price: 80000)
        r.paymentEntries = [PaymentEntry(method: .card, amount: 60000), PaymentEntry(method: .discount, amount: 10000),
                            PaymentEntry(method: .points, amount: 5000), PaymentEntry(method: .membership, amount: 5000)]
        XCTAssertEqual(RevenueStats.revenue(r, price: 80000), 60000)
        // 깎은 게 금액보다 커도 0 아래로 안 간다
        r.paymentEntries = [PaymentEntry(method: .discount, amount: 90000)]
        XCTAssertEqual(RevenueStats.revenue(r, price: 80000), 0)
    }

    func testPaidTotalSkipsNonRevenueMethods() {
        var r = res(1, date: "2026-10-13", price: 80000)
        r.paymentEntries = [PaymentEntry(method: .card, amount: 70000), PaymentEntry(method: .discount, amount: 10000)]
        XCTAssertEqual(RevenueStats.paidTotal([r]) { _ in 70000 }, 70000)
    }

    func testPriceFallsBackToSumOfServicePrices() {
        let r = res(1, date: "2026-10-13", price: nil)
        var multi = r
        multi.service = "커트 + 염색"
        XCTAssertEqual(RevenueStats.price(multi, priceByName: ["커트": 20000, "염색": 50000]), 70000)
        XCTAssertEqual(RevenueStats.price(res(2, date: "2026-10-13", price: 15000), priceByName: ["커트": 20000]), 15000)
    }

    func testStoreSalesKeepsRechargesWithPaidAmountInKST() {
        let entries = [
            // UTC 16:00 = KST 다음날 01:00 — 매장 날짜로 친다
            PointHistoryEntry(id: "a", type: .recharge, delta: 55000, balance: 55000, description: "", createdAt: "2026-10-19T16:00:00.000Z",
                              relatedReservationId: nil, paidAmount: 50000, paymentMethod: .card),
            PointHistoryEntry(id: "b", type: .recharge, delta: 10000, balance: 65000, description: "", createdAt: "2026-10-20T01:00:00Z",
                              relatedReservationId: nil),                       // 받은 금액 없는 옛 충전 — 뺀다
            PointHistoryEntry(id: "c", type: .manualAdd, delta: 1000, balance: 66000, description: "", createdAt: "2026-10-20T01:00:00Z",
                              relatedReservationId: nil, paidAmount: 1000),     // 충전 아님 — 뺀다
        ]
        let sales = RevenueStats.storeSales([Customer(id: 7, name: "가", tel: "010", pointHistories: entries)])
        XCTAssertEqual(sales.map(\.id), ["a"])
        XCTAssertEqual(sales.first?.date, "2026-10-20")
        XCTAssertEqual(sales.first?.amount, 50000)
        XCTAssertEqual(sales.first?.customerId, 7)
    }

    private func day(_ s: String) -> Date { KST.dayKey.date(from: s)! }
    private func key(_ d: Date) -> String { KST.dayKey.string(from: d) }

    func testQuickRangesAndDetection() {
        let today = day("2026-10-23")
        let week = RevenueStats.quickRange(.week, today: today)
        XCTAssertEqual(key(week.0), "2026-10-16")
        XCTAssertEqual(RevenueStats.quickRangeOf(week.0, week.1, today: today), .week)
        XCTAssertNil(RevenueStats.quickRangeOf(day("2026-10-01"), today, today: today))
    }

    func testClampKeepsEndAndPullsStartTo365Days() {
        let (s, e) = RevenueStats.clampRange(day("2024-01-01"), day("2026-10-23"))
        XCTAssertEqual(key(e), "2026-10-23")
        XCTAssertEqual(RevenueStats.days(from: s, to: e), 365)
    }

    func testMoveRangeNeverPassesToday() {
        let today = day("2026-10-23")
        // 30일 기간을 앞으로 — 오늘에서 멈추고 길이는 그대로
        let (s, e) = RevenueStats.moveRange(day("2026-09-01"), day("2026-10-01"), forward: true, today: today)
        XCTAssertEqual(key(e), "2026-10-23")
        XCTAssertEqual(key(s), "2026-09-23")
        // 오늘 하루는 하루씩, 앞으로는 오늘을 넘지 않는다
        let back = RevenueStats.moveRange(today, today, forward: false, today: today)
        XCTAssertEqual(key(back.0), "2026-10-22")
        let stay = RevenueStats.moveRange(today, today, forward: true, today: today)
        XCTAssertEqual(key(stay.1), "2026-10-23")
    }
}
