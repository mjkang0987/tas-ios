import XCTest
@testable import TAS

/// 매출 집계·추세 버킷 테스트 — RevenueViewModel의 순수 계산 로직.
/// state를 직접 주입해 네트워크 없이 검증한다.
@MainActor
final class RevenueViewModelTests: XCTestCase {

    private func makeVM(_ reservations: [Reservation], prices: [String: Int] = [:]) -> RevenueViewModel {
        let m = RevenueViewModel()
        m.state = .loaded(RevenueViewModel.Data(
            reservations: reservations,
            assigneesById: [:],
            servicePriceByName: prices
        ))
        return m
    }

    private func res(_ id: Int, date: String, price: Int?, status: ReservationStatus?,
                     service: String = "컷", customerId: Int = 1, assigneeId: Int? = nil,
                     paymentCompleted: Bool? = nil, paymentMethod: PaymentMethod? = nil) -> Reservation {
        Reservation(id: id, date: date, startTime: "10:00", endTime: "11:00",
                    service: service, customerId: customerId, assigneeId: assigneeId,
                    status: status, price: price,
                    paymentCompleted: paymentCompleted, paymentMethod: paymentMethod)
    }

    /// "YYYY-MM-DD" → KST Date.
    private func day(_ key: String) -> Date { KST.dayKey.date(from: key) ?? Date() }

    func testCompletedModeSummary() {
        let m = makeVM([
            res(1, date: "2026-07-01", price: 10000, status: .completed),
            res(2, date: "2026-07-02", price: 20000, status: .active),    // 완료 아님 → 제외
            res(3, date: "2026-07-03", price: 5000, status: .completed),
        ])
        m.selectedDate = day("2026-07-15")
        m.period = .month
        m.mode = .completed
        XCTAssertEqual(m.metrics.total, 15000)
        XCTAssertEqual(m.metrics.count, 2)
    }

    func testBookedModeExcludesCancelledNoshowRequested() {
        let m = makeVM([
            res(1, date: "2026-07-01", price: 10000, status: .active),
            res(2, date: "2026-07-02", price: 20000, status: .cancelled),
            res(3, date: "2026-07-03", price: 5000, status: .noshow),
            res(4, date: "2026-07-04", price: 7000, status: .requested),
            res(5, date: "2026-07-05", price: 3000, status: .completed),
        ])
        m.selectedDate = day("2026-07-15")
        m.mode = .booked
        XCTAssertEqual(m.metrics.total, 13000)   // active(10000) + completed(3000)
        XCTAssertEqual(m.metrics.count, 2)
    }

    func testPriceFallsBackToCatalog() {
        let m = makeVM(
            [res(1, date: "2026-07-01", price: nil, status: .completed, service: "컷")],
            prices: ["컷": 12000])
        m.selectedDate = day("2026-07-10")
        m.mode = .completed
        XCTAssertEqual(m.metrics.total, 12000)
    }

    func testOtherMonthExcluded() {
        let m = makeVM([
            res(1, date: "2026-07-01", price: 10000, status: .completed),
            res(2, date: "2026-06-30", price: 99999, status: .completed),   // 다른 달
        ])
        m.selectedDate = day("2026-07-15")
        m.period = .month
        m.mode = .completed
        XCTAssertEqual(m.metrics.total, 10000)
        XCTAssertEqual(m.metrics.count, 1)
    }

    func testMonthlyTrendBuckets() {
        let m = makeVM([
            res(1, date: "2026-07-01", price: 1000, status: .completed),
            res(2, date: "2026-07-01", price: 2000, status: .completed),
            res(3, date: "2026-07-15", price: 5000, status: .completed),
        ])
        m.selectedDate = day("2026-07-20")
        m.period = .month
        m.mode = .completed
        let trend = m.trend
        XCTAssertEqual(trend.count, 31)   // 2026년 7월 = 31일
        XCTAssertEqual(trend.first { $0.index == 1 }?.total, 3000)
        XCTAssertEqual(trend.first { $0.index == 15 }?.total, 5000)
        XCTAssertEqual(trend.first { $0.index == 2 }?.total, 0)
    }

    func testYearlyTrendBuckets() {
        let m = makeVM([
            res(1, date: "2026-07-01", price: 1000, status: .completed),
            res(2, date: "2026-03-10", price: 2000, status: .completed),
            res(3, date: "2026-07-20", price: 4000, status: .completed),
        ])
        m.selectedDate = day("2026-07-20")
        m.period = .year
        m.mode = .completed
        let trend = m.trend
        XCTAssertEqual(trend.count, 12)
        XCTAssertEqual(trend.first { $0.index == 7 }?.total, 5000)
        XCTAssertEqual(trend.first { $0.index == 3 }?.total, 2000)
        XCTAssertEqual(trend.first { $0.index == 1 }?.total, 0)
    }

    // MARK: - KPI (웹 RevenueKpiGrid 5칸)

    func testNewAndReturningCustomers() {
        let m = makeVM([
            // 고객 1 — 기간 이전 방문 이력이 있어 재방문
            res(1, date: "2026-06-11", price: 1000, status: .completed, customerId: 1),
            res(2, date: "2026-07-02", price: 1000, status: .completed, customerId: 1),
            // 고객 2 — 이번 달이 첫 방문 → 신규
            res(3, date: "2026-07-05", price: 1000, status: .completed, customerId: 2),
        ])
        m.selectedDate = day("2026-07-15")
        m.period = .month
        m.mode = .completed

        let metrics = m.metrics
        XCTAssertEqual(metrics.newCustomers.map(\.customerId), [2])
        XCTAssertEqual(metrics.returningCustomers.map(\.customerId), [1])
        XCTAssertEqual(metrics.returningCustomers.first?.prevVisitDate, "2026-06-11")
    }

    func testPaidMetricsUseCompletedPaymentsOnly() {
        let m = makeVM([
            res(1, date: "2026-07-01", price: 10000, status: .completed,
                paymentCompleted: true, paymentMethod: .card),
            res(2, date: "2026-07-02", price: 20000, status: .completed),   // 미결제
        ])
        m.selectedDate = day("2026-07-15")
        m.mode = .completed

        let metrics = m.metrics
        XCTAssertEqual(metrics.total, 30000)          // 매출은 둘 다
        XCTAssertEqual(metrics.paidTotal, 10000)      // 결제완료는 하나만
        XCTAssertEqual(metrics.paidReservations.map(\.id), [1])
    }

    // MARK: - 드릴다운 (탭하면 뜨는 목록)

    func testSalesLayerListsPeriodReservations() {
        let m = makeVM([
            res(1, date: "2026-07-03", price: 10000, status: .completed),
            res(2, date: "2026-07-01", price: 5000, status: .completed),
            res(3, date: "2026-08-01", price: 9000, status: .completed),    // 다른 달
        ])
        m.selectedDate = day("2026-07-15")
        m.mode = .completed

        let layer = m.metricLayer(.sales)
        XCTAssertEqual(layer.title, "총 매출 상세")
        XCTAssertEqual(layer.summary, "2건 · \(formatWon(15000))")
        guard case .reservations(let items) = layer.content else {
            return XCTFail("총 매출은 예약 목록이어야 한다")
        }
        XCTAssertEqual(items.map(\.id), [2, 1])   // 날짜 오름차순
    }

    func testNewCustomerLayerIsCustomerList() {
        let m = makeVM([res(1, date: "2026-07-03", price: 10000, status: .completed, customerId: 9)])
        m.selectedDate = day("2026-07-15")
        m.mode = .completed

        let layer = m.metricLayer(.new)
        XCTAssertEqual(layer.summary, "1명")
        XCTAssertNotNil(layer.subtitle)
        guard case .customers(let visits) = layer.content else {
            return XCTFail("신규 고객은 고객 목록이어야 한다")
        }
        XCTAssertEqual(visits.map(\.customerId), [9])
    }

    func testTrendLayerOpensThatDayOnly() {
        let m = makeVM([
            res(1, date: "2026-07-03", price: 10000, status: .completed),
            res(2, date: "2026-07-04", price: 5000, status: .completed),
        ])
        m.selectedDate = day("2026-07-15")
        m.period = .month
        m.mode = .completed

        XCTAssertEqual(m.trendKey(index: 3), RevenueViewModel.DetailKey.trend(3))
        let layer = m.layer(for: .trend(3))
        XCTAssertEqual(layer.title, "2026-07-03 매출 상세")
        guard case .reservations(let items) = layer.content else {
            return XCTFail("추세 막대는 예약 목록이어야 한다")
        }
        XCTAssertEqual(items.map(\.id), [1])

        // 매출 없는 날은 열 것이 없다.
        XCTAssertNil(m.trendKey(index: 10))
        // 달 범위를 벗어난 인덱스도 마찬가지(차트 탭 좌표가 튀는 경우).
        XCTAssertNil(m.trendKey(index: 32))
    }

    /// 목록은 키에서 **매번 다시** 만들어져야 한다 — 상세에서 예약을 취소하면
    /// 드릴다운 목록에서도 사라져야 하기 때문이다(탭 시점 스냅샷이면 남는다).
    func testLayerIsRecomputedFromKey() {
        let m = makeVM([
            res(1, date: "2026-07-03", price: 10000, status: .completed),
            res(2, date: "2026-07-04", price: 5000, status: .completed),
        ])
        m.selectedDate = day("2026-07-15")
        m.mode = .completed

        guard case .reservations(let before) = m.layer(for: .metric(.sales)).content else {
            return XCTFail("총 매출은 예약 목록이어야 한다")
        }
        XCTAssertEqual(before.map(\.id), [1, 2])

        // 상세에서 취소한 상황을 흉내낸다.
        var reservations = m.state.value!.reservations
        reservations[0].status = .cancelled
        m.state = .loaded(RevenueViewModel.Data(
            reservations: reservations, assigneesById: [:], servicePriceByName: [:]))

        guard case .reservations(let after) = m.layer(for: .metric(.sales)).content else {
            return XCTFail("총 매출은 예약 목록이어야 한다")
        }
        XCTAssertEqual(after.map(\.id), [2])
    }

    func testAssigneeLayerFiltersByAssignee() {
        let m = makeVM([
            res(1, date: "2026-07-03", price: 10000, status: .completed, assigneeId: 5),
            res(2, date: "2026-07-04", price: 5000, status: .completed, assigneeId: 6),
            res(3, date: "2026-07-05", price: 3000, status: .completed, assigneeId: nil),
        ])
        m.selectedDate = day("2026-07-15")
        m.mode = .completed

        guard case .reservations(let mine) = m.assigneeLayer(assigneeId: 5).content else {
            return XCTFail("담당자별은 예약 목록이어야 한다")
        }
        XCTAssertEqual(mine.map(\.id), [1])

        // 미지정(담당자 없음)도 자기 몫만 모은다.
        let unassigned = m.assigneeLayer(assigneeId: nil)
        XCTAssertEqual(unassigned.title, "미지정 매출 상세")
        guard case .reservations(let unassignedItems) = unassigned.content else {
            return XCTFail("담당자별은 예약 목록이어야 한다")
        }
        XCTAssertEqual(unassignedItems.map(\.id), [3])
    }
}
