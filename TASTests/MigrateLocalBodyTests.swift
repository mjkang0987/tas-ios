import XCTest
@testable import TAS

/// 게스트→로그인 이관 payload 인코딩 검증 — 스냅샷 필드가 최상위로 평탄화되고
/// confirm 플래그가 함께 실리는지(로그인 없이 검증 가능한 부분).
final class MigrateLocalBodyTests: XCTestCase {

    func testFlattensSnapshotFieldsWithConfirm() throws {
        var snap = GuestSnapshot()
        snap.storeName = "테스트샵"
        snap.shopType = "hair"
        snap.onboarded = true
        snap.customers = [Customer(id: 1, name: "가", tel: "01012345678")]
        snap.reservations = [
            Reservation(id: 1, date: "2026-07-24", startTime: "10:00", endTime: "11:00",
                        service: "컷", customerId: 1)
        ]

        let data = try JSONEncoder().encode(MigrateLocalBody(snapshot: snap, confirm: true))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // 스냅샷 필드가 최상위로.
        XCTAssertEqual(obj["storeName"] as? String, "테스트샵")
        XCTAssertEqual(obj["shopType"] as? String, "hair")
        XCTAssertEqual(obj["onboarded"] as? Bool, true)
        XCTAssertEqual((obj["customers"] as? [Any])?.count, 1)
        XCTAssertEqual((obj["reservations"] as? [Any])?.count, 1)
        // confirm 플래그 동봉.
        XCTAssertEqual(obj["confirm"] as? Bool, true)
    }

    func testConfirmFalseEncoded() throws {
        let data = try JSONEncoder().encode(MigrateLocalBody(snapshot: GuestSnapshot(), confirm: false))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["confirm"] as? Bool, false)
    }
}
