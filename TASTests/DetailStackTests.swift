import XCTest
@testable import TAS

/// 상세 쌓기 — 같은 레이어로 돌아가는 판정과 상세 데이터 해석.
final class DetailStackTests: XCTestCase {

    private func reservation(_ id: Int, customerId: Int) -> Reservation {
        Reservation(id: id, date: "2026-10-23", startTime: "10:00", endTime: "11:00", service: "커트", customerId: customerId)
    }

    private func assignee(_ id: Int, _ name: String, _ status: AssigneeStatus? = nil) -> Assignee {
        Assignee(id: id, name: name, schedule: [], status: status)
    }

    func testOpeningParentReturnsInsteadOfStacking() {
        // 고객 → 예약 → 같은 고객: 쌓지 않고 돌아간다
        XCTAssertTrue(DetailRoute.shouldReturn(opening: .customer(3), parent: .customer(3)))
        // 다른 고객·예약이면 쌓는다
        XCTAssertFalse(DetailRoute.shouldReturn(opening: .customer(4), parent: .customer(3)))
        XCTAssertFalse(DetailRoute.shouldReturn(opening: .reservation(3), parent: .customer(3)))
        XCTAssertFalse(DetailRoute.shouldReturn(opening: .customer(3), parent: nil))
    }

    func testDataResolvesCustomerReservationsHistoryAndAssignees() {
        let r1 = reservation(1, customerId: 7)
        let r2 = reservation(2, customerId: 8)
        var r1b = r1
        r1b.startTime = "12:00"
        let data = DetailData(
            reservations: [r1, r2],
            customersById: [7: Customer(id: 7, name: "가온", tel: ""), 9: Customer(id: 9, name: "하윤", tel: "")],
            assigneesById: [1: assignee(1, "원장"), 2: assignee(2, "실장", .retired), 3: assignee(3, "가실장", .leave)],
            services: [],
            serviceColorMap: [:],
            history: [
                ReservationHistoryEntry(reservationId: 1, before: r1, after: r1b, timestamp: "2026-10-22T01:00:00Z"),
                ReservationHistoryEntry(reservationId: 2, before: r2, after: r2, timestamp: "2026-10-22T02:00:00Z"),
                ReservationHistoryEntry(reservationId: 1, before: r1b, after: r1, timestamp: "2026-10-22T03:00:00Z"),
            ]
        )
        XCTAssertEqual(data.reservations(ofCustomer: 7).map(\.id), [1])
        // 그 예약 것만, 최신순
        XCTAssertEqual(data.history(forReservation: 1).map(\.timestamp), ["2026-10-22T03:00:00Z", "2026-10-22T01:00:00Z"])
        // 휴직·퇴직 빼고
        XCTAssertEqual(data.activeAssignees.map(\.name), ["원장"])
        XCTAssertEqual(data.nextReservationId, 3)
        XCTAssertEqual(data.nextCustomerId, 10)
        XCTAssertNil(data.reservation(99))
    }
}
