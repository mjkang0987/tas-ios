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

    // MARK: - 취소·삭제 적립금 환원 (웹 refundPointsOnCancel)

    private func paidReservation(_ id: Int) -> Reservation {
        var r = reservation(id)
        r.paymentCompleted = true
        r.paymentEntries = [PaymentEntry(method: .card, amount: 20000), PaymentEntry(method: .points, amount: 3000)]
        r.pointEarned = 1000
        return r
    }

    func testCancelPaidReservationRefundsPointsAndClearsPayment() {
        store.upsertCustomer(Customer(id: 1, name: "가온", tel: "", points: 5000))
        store.createReservation(paidReservation(1))
        store.setReservationStatus(id: 1, status: .cancelled)
        let r = store.snapshot.reservations.first
        XCTAssertNil(r?.paymentEntries)
        XCTAssertEqual(r?.paymentCompleted, false)
        XCTAssertEqual(r?.pointEarned, 0)
        let c = store.snapshot.customers.first
        XCTAssertEqual(c?.points, 7000) // 사용 3000 반환 − 적립 1000 회수
        XCTAssertEqual(c?.pointHistories?.first?.type, .paymentAdjust)
        XCTAssertEqual(c?.pointHistories?.first?.delta, 2000)
        XCTAssertEqual(c?.pointHistories?.first?.relatedReservationId, 1)
        // 예약전환 뒤 다시 취소해도 또 돌려주지 않는다(결제를 비웠다)
        store.setReservationStatus(id: 1, status: .active)
        store.setReservationStatus(id: 1, status: .cancelled)
        XCTAssertEqual(store.snapshot.customers.first?.points, 7000)
    }

    func testDeleteAfterCancelDoesNotRefundTwice() {
        store.upsertCustomer(Customer(id: 1, name: "가온", tel: "", points: 5000))
        store.createReservation(paidReservation(1))
        store.setReservationStatus(id: 1, status: .cancelled)
        store.deleteReservation(id: 1)
        XCTAssertEqual(store.snapshot.customers.first?.points, 7000)
        XCTAssertEqual(store.snapshot.customers.first?.pointHistories?.count, 1)
    }

    func testNoshowKeepsPaymentAndPoints() {
        store.upsertCustomer(Customer(id: 1, name: "가온", tel: "", points: 5000))
        store.createReservation(paidReservation(1))
        store.setReservationStatus(id: 1, status: .noshow)
        XCTAssertEqual(store.snapshot.reservations.first?.paymentEntries?.count, 2)
        XCTAssertEqual(store.snapshot.customers.first?.points, 5000)
    }

    func testDeletePaidReservationClawsBackEarnedPoints() {
        store.upsertCustomer(Customer(id: 1, name: "가온", tel: "", points: 500))
        var r = paidReservation(1)
        r.paymentEntries = [PaymentEntry(method: .card, amount: 20000)]
        store.createReservation(r)
        store.deleteReservation(id: 1)
        // 적립 1000 회수 — 잔액은 0 아래로 안 내려가고 이력 잔액은 그대로(웹과 같다)
        XCTAssertEqual(store.snapshot.customers.first?.points, 0)
        XCTAssertEqual(store.snapshot.customers.first?.pointHistories?.first?.balance, -500)
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
