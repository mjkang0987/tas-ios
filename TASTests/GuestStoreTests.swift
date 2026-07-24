import XCTest
@testable import TAS

/// 게스트(오프라인) 로컬 스냅샷 CRUD·병합 테스트.
/// 싱글턴 GuestStore.shared를 각 테스트 시작 시 reset()으로 초기화해 격리한다.
final class GuestStoreTests: XCTestCase {

    private var store: GuestStore { GuestStore.shared }

    override func setUp() {
        super.setUp()
        store.reset()
    }

    override func tearDown() {
        store.reset()
        super.tearDown()
    }

    private func reservation(_ id: Int, customerId: Int = 1, assigneeId: Int? = nil,
                             status: ReservationStatus? = .active) -> Reservation {
        Reservation(id: id, date: "2026-07-24", startTime: "10:00", endTime: "11:00",
                    service: "컷", customerId: customerId, assigneeId: assigneeId, status: status)
    }

    private func assignee(_ id: Int, name: String) -> Assignee {
        Assignee(id: id, name: name, nameI18n: nil, schedule: [], status: .active,
                 phone: nil, note: nil, color: nil)
    }

    // MARK: - 예약 CRUD

    func testCreateReservation() {
        store.createReservation(reservation(1))
        XCTAssertEqual(store.snapshot.reservations.map(\.id), [1])
    }

    func testUpdateReservationRecordsHistory() {
        store.createReservation(reservation(1))
        var updated = reservation(1)
        updated.service = "펌"
        store.updateReservation(prev: reservation(1), updated: updated)
        XCTAssertEqual(store.snapshot.reservations.first?.service, "펌")
        XCTAssertEqual(store.snapshot.history.count, 1)
        XCTAssertEqual(store.snapshot.history.first?.reservationId, 1)
    }

    func testSetReservationStatusRecordsHistory() {
        store.createReservation(reservation(1))
        let result = store.setReservationStatus(id: 1, status: .cancelled)
        XCTAssertEqual(result?.status, .cancelled)
        XCTAssertEqual(store.snapshot.reservations.first?.status, .cancelled)
        XCTAssertEqual(store.snapshot.history.count, 1)
    }

    func testDeleteReservation() {
        store.createReservation(reservation(1))
        store.createReservation(reservation(2))
        store.deleteReservation(id: 1)
        XCTAssertEqual(store.snapshot.reservations.map(\.id), [2])
    }

    func testNextIds() {
        store.createReservation(reservation(1))
        store.createReservation(reservation(5))
        XCTAssertEqual(store.nextReservationId, 6)
        _ = store.upsertCustomer(Customer(id: 3, name: "가", tel: "010"))
        XCTAssertEqual(store.nextCustomerId, 4)
    }

    // MARK: - 고객 CRUD·병합

    func testUpsertCustomerInsertThenUpdate() {
        _ = store.upsertCustomer(Customer(id: 1, name: "가", tel: "01011112222"))
        XCTAssertEqual(store.snapshot.customers.count, 1)
        _ = store.upsertCustomer(Customer(id: 1, name: "가나", tel: "01011112222"))
        XCTAssertEqual(store.snapshot.customers.count, 1)
        XCTAssertEqual(store.snapshot.customers.first?.name, "가나")
    }

    func testMergeCustomers() {
        let target = Customer(id: 1, name: "타겟", tel: "01000000001", points: 100,
                              firstVisitDate: "2026-07-10",
                              memoTags: [CustomerMemoTag(text: "VIP", color: "#f00")])
        let source = Customer(id: 2, name: "소스", tel: "01000000002", points: 50,
                              firstVisitDate: "2026-07-05",
                              memoTags: [CustomerMemoTag(text: "VIP", color: "#f00"),
                                         CustomerMemoTag(text: "단골", color: "#0f0")])
        _ = store.upsertCustomer(target)
        _ = store.upsertCustomer(source)
        store.createReservation(reservation(1, customerId: 2))

        XCTAssertTrue(store.mergeCustomers(sourceId: 2, targetId: 1))

        XCTAssertEqual(store.snapshot.customers.map(\.id), [1])          // source 제거
        let merged = store.snapshot.customers.first
        XCTAssertEqual(merged?.points, 150)                              // 적립금 합산
        XCTAssertEqual(merged?.firstVisitDate, "2026-07-05")            // 이른 날짜
        XCTAssertEqual(Set((merged?.memoTags ?? []).map(\.text)), ["VIP", "단골"])  // 중복 제외 병합
        XCTAssertEqual(store.snapshot.reservations.first?.customerId, 1) // 예약 이전
    }

    func testMergeCustomersSameIdNoop() {
        _ = store.upsertCustomer(Customer(id: 1, name: "가", tel: "010"))
        XCTAssertFalse(store.mergeCustomers(sourceId: 1, targetId: 1))
    }

    // MARK: - 담당자

    func testMergeAssignees() {
        _ = store.saveAssignees([assignee(1, name: "A"), assignee(2, name: "B")])
        store.createReservation(reservation(1, assigneeId: 1))
        XCTAssertTrue(store.mergeAssignees(sourceId: 1, targetId: 2))
        XCTAssertEqual(store.snapshot.assignees.map(\.id), [2])
        XCTAssertEqual(store.snapshot.reservations.first?.assigneeId, 2)
    }

    func testDeleteAssigneeDetachesReservations() {
        _ = store.saveAssignees([assignee(1, name: "A"), assignee(2, name: "B")])
        store.createReservation(reservation(1, assigneeId: 1))
        store.deleteAssignee(id: 1)
        XCTAssertEqual(store.snapshot.assignees.map(\.id), [2])
        XCTAssertNil(store.snapshot.reservations.first?.assigneeId)   // 예약은 보존, 담당자만 분리
    }
}
