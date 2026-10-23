import XCTest
@testable import TAS

/// 적립금 산식 테스트 — 결제 화면에서 분리한 PointMath.
final class PointMathTests: XCTestCase {

    func testEarnedAmount() {
        XCTAssertEqual(PointMath.earnedAmount(base: 10000, rate: 10), 1000)
        XCTAssertEqual(PointMath.earnedAmount(base: 15000, rate: 3), 450)
        XCTAssertEqual(PointMath.earnedAmount(base: 999, rate: 10), 99)   // 내림
        XCTAssertEqual(PointMath.earnedAmount(base: 10000, rate: 0), 0)   // 적립률 0
        XCTAssertEqual(PointMath.earnedAmount(base: 0, rate: 10), 0)
    }

    func testPointsUsedAndNonPointTotal() {
        let entries = [
            PaymentEntry(method: .card, amount: 15000),
            PaymentEntry(method: .points, amount: 5000),
            PaymentEntry(method: .cash, amount: 3000),
        ]
        XCTAssertEqual(PointMath.pointsUsed(in: entries), 5000)
        XCTAssertEqual(PointMath.nonPointTotal(in: entries), 18000)   // 카드+현금(포인트 제외)
    }

    func testNoPointEntries() {
        let entries = [PaymentEntry(method: .card, amount: 10000)]
        XCTAssertEqual(PointMath.pointsUsed(in: entries), 0)
        XCTAssertEqual(PointMath.nonPointTotal(in: entries), 10000)
    }

    func testEmptyEntries() {
        XCTAssertEqual(PointMath.pointsUsed(in: []), 0)
        XCTAssertEqual(PointMath.nonPointTotal(in: []), 0)
    }

    // 웹 cancelRefund.test.ts 와 같은 경우
    func testRefundOnCancel() {
        var r = Reservation(id: 1, date: "2026-10-23", startTime: "10:00", endTime: "11:00", service: "컷", customerId: 1, status: .completed)
        r.paymentCompleted = true
        r.paymentEntries = [PaymentEntry(method: .card, amount: 20000), PaymentEntry(method: .points, amount: 3000)]
        r.pointEarned = 1000
        XCTAssertEqual(PointMath.refundOnCancel(r), 2000)
        r.paymentEntries = [PaymentEntry(method: .card, amount: 20000)]
        XCTAssertEqual(PointMath.refundOnCancel(r), -1000)
        r.status = .cancelled
        XCTAssertEqual(PointMath.refundOnCancel(r), 0)          // 이미 취소
        var unpaid = Reservation(id: 2, date: "2026-10-23", startTime: "10:00", endTime: "11:00", service: "컷", customerId: 1, status: .active)
        unpaid.paymentEntries = []
        XCTAssertEqual(PointMath.refundOnCancel(unpaid), 0)     // 결제 전
    }
}
