import XCTest
@testable import TAS

/// 예약 폼 — 고른 고객이 이름 변경 처리로 풀리지 않는지.
final class ReservationCreateRulesTests: XCTestCase {
    private let customers = [
        Customer(id: 3, name: "김민지", tel: "01012345678", points: 0, pointHistories: []),
        Customer(id: 5, name: "박하은", tel: "01012347900", points: 0, pointHistories: []),
    ]

    func testKeepsWhenNameBecomesSelectedCustomersName() {
        // 추천에서 고르거나 변경 화면을 채우면 이름이 그 고객 이름으로 바뀐다
        XCTAssertTrue(ReservationCreateView.keepsSelectedCustomer(id: 3, name: "김민지", in: customers))
    }

    func testReleasesWhenUserRetypesName() {
        XCTAssertFalse(ReservationCreateView.keepsSelectedCustomer(id: 3, name: "김민", in: customers))
        XCTAssertFalse(ReservationCreateView.keepsSelectedCustomer(id: 3, name: "박하은", in: customers))
    }

    func testNewCustomerIsNeverKept() {
        XCTAssertFalse(ReservationCreateView.keepsSelectedCustomer(id: 0, name: "김민지", in: customers))
        XCTAssertFalse(ReservationCreateView.keepsSelectedCustomer(id: 9, name: "", in: customers))
    }
}
