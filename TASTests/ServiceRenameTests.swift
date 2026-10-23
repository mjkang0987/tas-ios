import XCTest
@testable import TAS

/// 서비스 이름·가격 변경을 앞으로의 예약에 반영 — 웹 `buildServiceCatalogReservationUpdates`.
final class ServiceRenameTests: XCTestCase {
    private let today = "2026-10-23"
    private let prev = [ServiceItem(name: "커트", durationMinutes: 30, category: "커트", price: 20000),
                        ServiceItem(name: "염색", durationMinutes: 60, category: "염색", price: 50000)]

    private func res(_ id: Int, date: String = "2026-10-24", service: String = "커트", price: Int? = 20000,
                     start: String = "10:00", end: String = "10:30", status: ReservationStatus? = .active) -> Reservation {
        var r = Reservation(id: id, date: date, startTime: start, endTime: end, service: service, customerId: 1)
        r.price = price
        r.status = status
        return r
    }

    func testRenameAndRepriceFutureUnpaidOnly() {
        let next = [ServiceItem(name: "남성커트", durationMinutes: 40, category: "커트", price: 25000), prev[1]]
        var paid = res(3)
        paid.paymentCompleted = true
        paid.paymentMethod = .card
        let updates = ServiceRename.reservationUpdates(
            [res(1), res(2, date: "2026-10-22"), paid, res(4, status: .cancelled), res(5, service: "염색", price: 50000, end: "11:00")],
            originalName: "커트", updatedName: "남성커트", prevCatalog: prev, nextCatalog: next, today: today)
        XCTAssertEqual(updates.map(\.prev.id), [1])     // 지난·결제·취소·다른 서비스는 그대로
        XCTAssertEqual(updates.first?.updated.service, "남성커트")
        XCTAssertEqual(updates.first?.updated.price, 25000)
        XCTAssertEqual(updates.first?.updated.endTime, "10:40")
    }

    func testKeepsManualPriceAndDurationInCombo() {
        let next = [ServiceItem(name: "커트", durationMinutes: 45, category: "커트", price: 30000), prev[1]]
        // 커트+염색 — 가격을 손댔다(60,000 ≠ 70,000), 시간은 카탈로그 그대로(90분)
        let r = res(1, service: "커트+염색", price: 60000, end: "11:30")
        let u = ServiceRename.reservationUpdates([r], originalName: "커트", updatedName: "커트",
                                                 prevCatalog: prev, nextCatalog: next, today: today).first
        XCTAssertEqual(u?.updated.price, 60000)          // 손댄 가격은 유지
        XCTAssertEqual(u?.updated.endTime, "11:45")      // 시간은 새 합계(45+60)
        XCTAssertEqual(u?.updated.service, "커트+염색")
    }

    func testNoChangeMeansNoUpdate() {
        XCTAssertTrue(ServiceRename.reservationUpdates([res(1)], originalName: "커트", updatedName: "커트",
                                                       prevCatalog: prev, nextCatalog: prev, today: today).isEmpty)
    }

    func testEndTimeWrapsPastMidnight() {
        XCTAssertEqual(ServiceRename.endTime("23:30", plus: 45), "00:15")
    }
}
