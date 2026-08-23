import XCTest
@testable import TAS

/// 고객 집계 — 웹 `address.tsx` `customerStats` · `getEffectiveStatus` 이식본 검증.
///
/// 핵심은 **상태 없는 지난 예약을 '완료'로 친다**는 규칙이다. 웹은 예약을 끝내도 status를
/// 바꾸지 않는 경우가 많아, 이 규칙이 빠지면 지난 예약이 전부 '예약'으로 남아 숫자가 어긋난다.
final class CustomerStatsTests: XCTestCase {

    private let today = "2026-08-23"

    private func reservation(
        _ id: Int,
        _ date: String,
        _ start: String = "10:00",
        service: String = "남성커트",
        status: ReservationStatus? = nil
    ) -> Reservation {
        Reservation(id: id, date: date, startTime: start, endTime: "11:00",
                    service: service, customerId: 1, status: status)
    }

    // MARK: - 유효 상태 판정

    func testPastReservationWithoutStatusCountsAsCompleted() {
        let r = reservation(1, "2026-08-22")
        XCTAssertEqual(CustomerStats.effectiveStatus(r, today: today), .completed)
    }

    func testTodayAndFutureCountAsBooked() {
        XCTAssertEqual(CustomerStats.effectiveStatus(reservation(1, today), today: today), .booked)
        XCTAssertEqual(CustomerStats.effectiveStatus(reservation(2, "2026-08-24"), today: today), .booked)
    }

    /// 취소·노쇼는 날짜와 무관하게 자기 상태를 유지한다(웹 판정 순서).
    func testCancelledAndNoshowWinOverDate() {
        let cancelled = reservation(1, "2026-08-01", status: .cancelled)
        let noshow = reservation(2, "2026-12-31", status: .noshow)
        XCTAssertEqual(CustomerStats.effectiveStatus(cancelled, today: today), .cancelled)
        XCTAssertEqual(CustomerStats.effectiveStatus(noshow, today: today), .noshow)
    }

    func testExplicitCompletedStaysCompletedEvenInFuture() {
        let r = reservation(1, "2026-12-31", status: .completed)
        XCTAssertEqual(CustomerStats.effectiveStatus(r, today: today), .completed)
    }

    // MARK: - 집계

    func testSummaryCountsEachBucket() {
        let summary = CustomerStats.summarize([
            reservation(1, "2026-08-24"),                       // 예약
            reservation(2, today),                              // 예약
            reservation(3, "2026-08-01"),                       // 완료(지남)
            reservation(4, "2026-12-01", status: .completed),   // 완료(명시)
            reservation(5, "2026-08-02", status: .cancelled),   // 취소
            reservation(6, "2026-08-03", status: .noshow),      // 노쇼
        ], today: today)

        XCTAssertEqual(summary.booked, 2)
        XCTAssertEqual(summary.completed, 2)
        XCTAssertEqual(summary.cancelled, 1)
        XCTAssertEqual(summary.noshow, 1)
        XCTAssertEqual(summary.total, 6)
    }

    func testEmptyReservationsGiveZeroesAndNoRecentService() {
        let summary = CustomerStats.summarize([], today: today)
        XCTAssertEqual(summary, .empty)
        XCTAssertNil(summary.recentService)
    }

    // MARK: - 최근 시술

    func testRecentServiceIsLatestByDateThenStartTime() {
        let summary = CustomerStats.summarize([
            reservation(1, "2026-08-20", "09:00", service: "일반펌"),
            reservation(2, "2026-08-22", "09:00", service: "뿌리염색"),
            reservation(3, "2026-08-22", "15:00", service: "여성커트"),   // 같은 날 더 늦음
        ], today: today)
        XCTAssertEqual(summary.recentService, "여성커트")
    }

    /// 취소·노쇼는 '최근 시술'에 잡히면 안 된다 — 실제로 받지 않은 시술이다.
    func testRecentServiceIgnoresCancelledAndNoshow() {
        let summary = CustomerStats.summarize([
            reservation(1, "2026-08-20", service: "일반펌"),
            reservation(2, "2026-08-22", service: "탈색", status: .cancelled),
            reservation(3, "2026-08-21", service: "매직", status: .noshow),
        ], today: today)
        XCTAssertEqual(summary.recentService, "일반펌")
    }

    func testRecentServiceIsNilWhenOnlyCancelled() {
        let summary = CustomerStats.summarize([
            reservation(1, "2026-08-22", service: "탈색", status: .cancelled),
        ], today: today)
        XCTAssertNil(summary.recentService)
    }

    func testBlankServiceIsTreatedAsNoRecentService() {
        let summary = CustomerStats.summarize([reservation(1, "2026-08-22", service: "")], today: today)
        XCTAssertNil(summary.recentService)
    }

    // MARK: - 표시 순서

    /// 웹은 요약 행(예약/취소/완료/노쇼)과 상세 그룹(예약/완료/취소/노쇼) 순서가 **다르다**.
    /// 하나로 합치고 싶어지는 자리라 테스트로 못박아둔다.
    func testSummaryOrderDiffersFromGroupOrder() {
        XCTAssertEqual(CustomerStats.EffectiveStatus.summaryOrder,
                       [.booked, .cancelled, .completed, .noshow])
        XCTAssertEqual(CustomerStats.EffectiveStatus.allCases,
                       [.booked, .completed, .cancelled, .noshow])
        XCTAssertNotEqual(CustomerStats.EffectiveStatus.summaryOrder,
                          CustomerStats.EffectiveStatus.allCases)
    }

    /// 순서만 다를 뿐 빠진 상태가 있으면 안 된다.
    func testSummaryOrderCoversEveryStatus() {
        XCTAssertEqual(Set(CustomerStats.EffectiveStatus.summaryOrder),
                       Set(CustomerStats.EffectiveStatus.allCases))
        XCTAssertEqual(CustomerStats.EffectiveStatus.summaryOrder.count,
                       CustomerStats.EffectiveStatus.allCases.count)
    }

    // MARK: - 그룹

    func testGroupsSkipEmptyBucketsAndKeepWebOrder() {
        let groups = CustomerStats.groups([
            reservation(1, "2026-08-24"),                   // 예약
            reservation(2, "2026-08-01"),                   // 완료
            reservation(3, "2026-08-02", status: .noshow),  // 노쇼 — 취소는 없음
        ], today: today)

        XCTAssertEqual(groups.map(\.status), [.booked, .completed, .noshow])
        XCTAssertEqual(groups.map(\.id), groups.map(\.status))
    }

    func testGroupItemsAreFutureFirst() {
        let groups = CustomerStats.groups([
            reservation(1, "2026-08-01", "09:00"),
            reservation(2, "2026-08-03", "09:00"),
            reservation(3, "2026-08-03", "15:00"),
        ], today: today)

        let completed = groups.first { $0.status == .completed }
        XCTAssertEqual(completed?.items.map(\.id), [3, 2, 1])
    }

    func testByCustomerSummarisesEachCustomerSeparately() {
        let byCustomer = CustomerStats.byCustomer([
            1: [reservation(1, "2026-08-24")],
            2: [reservation(2, "2026-08-01"), reservation(3, "2026-08-02", status: .cancelled)],
        ], today: today)

        XCTAssertEqual(byCustomer[1]?.booked, 1)
        XCTAssertEqual(byCustomer[2]?.completed, 1)
        XCTAssertEqual(byCustomer[2]?.cancelled, 1)
    }
}
