import XCTest
@testable import TAS

/// 결제 적립/사용에 따른 고객 적립금 잔액·이력 계산 테스트(PointLedger).
final class PointLedgerTests: XCTestCase {

    func testEarnOnly() {
        let (balance, changes) = PointLedger.changes(
            currentBalance: 8000, previousEarned: 0, newEarned: 1500, previousUsed: 0, newUsed: 0)
        XCTAssertEqual(balance, 9500)
        XCTAssertEqual(changes, [.init(type: .paymentEarn, delta: 1500, balanceAfter: 9500, description: "예약 결제 적립")])
    }

    func testUseOnly() {
        let (balance, changes) = PointLedger.changes(
            currentBalance: 8000, previousEarned: 0, newEarned: 0, previousUsed: 0, newUsed: 5000)
        XCTAssertEqual(balance, 3000)
        XCTAssertEqual(changes, [.init(type: .paymentUse, delta: -5000, balanceAfter: 3000, description: "예약 결제 사용")])
    }

    func testUseThenEarnOnNewPayment() {
        // 8000 보유, 5000 포인트 결제 + 15000 결제분 10% 적립(1500).
        let (balance, changes) = PointLedger.changes(
            currentBalance: 8000, previousEarned: 0, newEarned: 1500, previousUsed: 0, newUsed: 5000)
        XCTAssertEqual(balance, 4500)                       // 8000-5000+1500
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes[0], .init(type: .paymentUse, delta: -5000, balanceAfter: 3000, description: "예약 결제 사용"))
        XCTAssertEqual(changes[1], .init(type: .paymentEarn, delta: 1500, balanceAfter: 4500, description: "예약 결제 적립"))
    }

    func testUseCancelledOnEdit() {
        // 이전에 5000 사용 → 수정에서 사용 제거(useDelta = -5000) → 환원.
        let (balance, changes) = PointLedger.changes(
            currentBalance: 4500, previousEarned: 1500, newEarned: 1500, previousUsed: 5000, newUsed: 0)
        XCTAssertEqual(balance, 9500)
        XCTAssertEqual(changes, [.init(type: .paymentUse, delta: 5000, balanceAfter: 9500, description: "예약 결제 사용 취소")])
    }

    func testEarnAdjustedDown() {
        let (balance, changes) = PointLedger.changes(
            currentBalance: 4500, previousEarned: 1500, newEarned: 1000, previousUsed: 0, newUsed: 0)
        XCTAssertEqual(balance, 4000)
        XCTAssertEqual(changes, [.init(type: .paymentEarn, delta: -500, balanceAfter: 4000, description: "예약 결제 적립 조정")])
    }

    func testNoChange() {
        let (balance, changes) = PointLedger.changes(
            currentBalance: 4500, previousEarned: 1500, newEarned: 1500, previousUsed: 5000, newUsed: 5000)
        XCTAssertEqual(balance, 4500)
        XCTAssertTrue(changes.isEmpty)
    }

    func testBalanceClampsAtZero() {
        let (balance, _) = PointLedger.changes(
            currentBalance: 100, previousEarned: 0, newEarned: 0, previousUsed: 0, newUsed: 5000)
        XCTAssertEqual(balance, 0)
    }

    // MARK: - apply(to:)

    func testApplyEarnUpdatesCustomer() {
        let c = Customer(id: 1, name: "가", tel: "010", points: 8000, pointHistories: [])
        let updated = PointLedger.apply(
            to: c, previousEarned: 0, newEarned: 1500, previousUsed: 0, newUsed: 0,
            reservationId: 42, now: "2026-07-24T00:00:00Z", makeId: { "id-1" })
        XCTAssertEqual(updated?.points, 9500)
        XCTAssertEqual(updated?.pointHistories?.count, 1)
        let entry = updated?.pointHistories?.first
        XCTAssertEqual(entry?.type, .paymentEarn)
        XCTAssertEqual(entry?.delta, 1500)
        XCTAssertEqual(entry?.balance, 9500)
        XCTAssertEqual(entry?.relatedReservationId, 42)
    }

    func testApplyNoChangeReturnsNil() {
        let c = Customer(id: 1, name: "가", tel: "010", points: 8000, pointHistories: [])
        let updated = PointLedger.apply(
            to: c, previousEarned: 0, newEarned: 0, previousUsed: 0, newUsed: 0,
            reservationId: 1, now: "t", makeId: { "id" })
        XCTAssertNil(updated)
    }

    func testApplyPrependsNewestFirst() {
        let c = Customer(id: 1, name: "가", tel: "010", points: 8000, pointHistories: [])
        // 사용 5000 + 적립 1500 → 이력 2건, 최신(적립)이 맨 앞.
        let updated = PointLedger.apply(
            to: c, previousEarned: 0, newEarned: 1500, previousUsed: 0, newUsed: 5000,
            reservationId: 7, now: "t", makeId: { "id" })
        XCTAssertEqual(updated?.points, 4500)
        XCTAssertEqual(updated?.pointHistories?.map(\.type), [.paymentEarn, .paymentUse])
    }
}
