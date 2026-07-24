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
                     service: String = "컷") -> Reservation {
        Reservation(id: id, date: date, startTime: "10:00", endTime: "11:00",
                    service: service, customerId: 1, status: status, price: price)
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
        XCTAssertEqual(m.summary.total, 15000)
        XCTAssertEqual(m.summary.count, 2)
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
        XCTAssertEqual(m.summary.total, 13000)   // active(10000) + completed(3000)
        XCTAssertEqual(m.summary.count, 2)
    }

    func testPriceFallsBackToCatalog() {
        let m = makeVM(
            [res(1, date: "2026-07-01", price: nil, status: .completed, service: "컷")],
            prices: ["컷": 12000])
        m.selectedDate = day("2026-07-10")
        m.mode = .completed
        XCTAssertEqual(m.summary.total, 12000)
    }

    func testOtherMonthExcluded() {
        let m = makeVM([
            res(1, date: "2026-07-01", price: 10000, status: .completed),
            res(2, date: "2026-06-30", price: 99999, status: .completed),   // 다른 달
        ])
        m.selectedDate = day("2026-07-15")
        m.period = .month
        m.mode = .completed
        XCTAssertEqual(m.summary.total, 10000)
        XCTAssertEqual(m.summary.count, 1)
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
}
