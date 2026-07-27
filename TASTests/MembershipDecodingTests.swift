import XCTest
@testable import TAS

/// 회원권 발급분(CustomerMembership) 디코딩·상태 매핑 — 웹 memberships/model.ts 미러.
final class MembershipDecodingTests: XCTestCase {

    func testMembershipsResponseDecodesProductsAndIssued() throws {
        let json = Data(#"""
        {
          "products": [{"id":"p1","name":"10회권","totalCount":10,"validDays":90,"price":100000,"status":"active"}],
          "memberships": [{"id":"m1","customerId":7,"productId":"p1","name":"10회권","totalCount":10,"remainingCount":8,"issuedAt":"2026-07-01T00:00:00Z","expiresAt":"2026-10-01T00:00:00Z","status":"active"}]
        }
        """#.utf8)
        let resp = try JSONDecoder().decode(MembershipsResponse.self, from: json)
        XCTAssertEqual(resp.products.count, 1)
        XCTAssertEqual(resp.memberships?.count, 1)
        let m = try XCTUnwrap(resp.memberships?.first)
        XCTAssertEqual(m.id, "m1")
        XCTAssertEqual(m.customerId, 7)
        XCTAssertEqual(m.remainingCount, 8)
        XCTAssertEqual(m.status, .active)
    }

    func testMembershipsResponseToleratesMissingMembershipsKey() throws {
        // 게스트/구버전 응답: memberships 키가 없어도 디코드(옵셔널).
        let resp = try JSONDecoder().decode(MembershipsResponse.self, from: Data(#"{"products":[]}"#.utf8))
        XCTAssertTrue(resp.products.isEmpty)
        XCTAssertNil(resp.memberships)
    }

    func testStatusRawValues() {
        XCTAssertEqual(CustomerMembershipStatus.usedUp.rawValue, "used_up")
        XCTAssertEqual(CustomerMembershipStatus(rawValue: "used_up"), .usedUp)
        XCTAssertEqual(CustomerMembershipStatus(rawValue: "cancelled"), .cancelled)
    }

    func testUseActionRawValues() {
        XCTAssertEqual(MembershipUseAction.use.rawValue, "use")
        XCTAssertEqual(MembershipUseAction.restore.rawValue, "restore")
    }
}
