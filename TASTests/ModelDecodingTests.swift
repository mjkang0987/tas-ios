import XCTest
@testable import TAS

/// 도메인 모델 디코딩·파생값 테스트 — Store 디코딩(웹 스키마 매핑)과 고객/예약 헬퍼.
final class ModelDecodingTests: XCTestCase {

    func testStoreDecodesStoreNameToName() throws {
        let json = Data(#"{"storeName":"테스트샵","shopType":"hair","usePointSystem":true}"#.utf8)
        let store = try JSONDecoder().decode(Store.self, from: json)
        XCTAssertEqual(store.name, "테스트샵")
        XCTAssertEqual(store.shopType, "hair")
        XCTAssertEqual(store.usePointSystem, true)
        XCTAssertEqual(store.id, "")   // id 누락 허용 → ""
    }

    func testStoreTolerabesMissingFields() throws {
        let store = try JSONDecoder().decode(Store.self, from: Data("{}".utf8))
        XCTAssertEqual(store.name, "매장")   // name 누락 → 기본값
        XCTAssertEqual(store.id, "")
        XCTAssertNil(store.shopType)
    }

    func testCustomerFormattedTel() {
        XCTAssertEqual(Customer(id: 1, name: "가", tel: "01012345678").formattedTel, "010-1234-5678")
        XCTAssertEqual(Customer(id: 2, name: "나", tel: "0212345678").formattedTel, "021-234-5678")
        XCTAssertEqual(Customer(id: 3, name: "다", tel: "123").formattedTel, "123")   // 형식 밖 → 원본
    }

    func testIsNewCustomerVisit() {
        let c = Customer(id: 1, name: "가", tel: "010", firstVisitDate: "2026-07-24")
        XCTAssertTrue(c.isNewCustomerVisit(on: "2026-07-24"))
        XCTAssertFalse(c.isNewCustomerVisit(on: "2026-07-25"))
        XCTAssertFalse(Customer(id: 2, name: "나", tel: "010").isNewCustomerVisit(on: "2026-07-24"))
    }

    func testReservationPaymentAndDisplayState() {
        var r = Reservation(id: 1, date: "2026-07-24", startTime: "10:00", endTime: "11:00",
                            service: "컷", customerId: 1, status: .active)
        XCTAssertFalse(r.hasCompletedPayment)
        XCTAssertEqual(r.displayState, .booked)

        r.paymentEntries = [PaymentEntry(method: .card, amount: 10000)]
        XCTAssertTrue(r.hasCompletedPayment)
        XCTAssertEqual(r.displayState, .paid)

        r.status = .cancelled
        XCTAssertEqual(r.displayState, .cancelled)

        r.status = .noshow
        XCTAssertEqual(r.displayState, .noshow)
    }

    func testReservationIsOnline() {
        let online = Reservation(id: 1, date: "2026-07-24", startTime: "10:00", endTime: "11:00",
                                 service: "컷", customerId: 1, channel: .online)
        let phone = Reservation(id: 2, date: "2026-07-24", startTime: "10:00", endTime: "11:00",
                                service: "컷", customerId: 1, channel: .phone)
        XCTAssertTrue(online.isOnline)
        XCTAssertFalse(phone.isOnline)
    }
}
