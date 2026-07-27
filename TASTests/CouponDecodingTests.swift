import XCTest
@testable import TAS

/// 발급 쿠폰(CustomerCoupon) 디코딩·상태·할인표기 — 웹 coupons/model.ts 미러.
final class CouponDecodingTests: XCTestCase {

    func testCouponsResponseDecodesProductsAndIssued() throws {
        let json = Data(#"""
        {
          "products":[{"id":"cp1","name":"1만원 할인","discountType":"amount","discountValue":10000,"maxDiscount":null,"minOrderAmount":20000,"validDays":30,"code":null,"status":"active"}],
          "coupons":[{"id":"c1","customerId":7,"productId":"cp1","name":"1만원 할인","discountType":"amount","discountValue":10000,"maxDiscount":null,"minOrderAmount":20000,"issuedAt":"2026-07-01T00:00:00Z","expiresAt":"2026-07-31T00:00:00Z","usedAt":null,"status":"active"}]
        }
        """#.utf8)
        let resp = try JSONDecoder().decode(CouponsResponse.self, from: json)
        XCTAssertEqual(resp.products.count, 1)
        XCTAssertEqual(resp.coupons?.count, 1)
        let c = try XCTUnwrap(resp.coupons?.first)
        XCTAssertEqual(c.id, "c1")
        XCTAssertEqual(c.customerId, 7)
        XCTAssertEqual(c.discountType, .amount)
        XCTAssertEqual(c.status, .active)
        XCTAssertNil(c.usedAt)
    }

    func testCouponsResponseToleratesMissingCouponsKey() throws {
        let resp = try JSONDecoder().decode(CouponsResponse.self, from: Data(#"{"products":[]}"#.utf8))
        XCTAssertTrue(resp.products.isEmpty)
        XCTAssertNil(resp.coupons)
    }

    func testStatusRawValues() {
        XCTAssertEqual(CustomerCouponStatus(rawValue: "used"), .used)
        XCTAssertEqual(CustomerCouponStatus(rawValue: "expired"), .expired)
        XCTAssertEqual(CustomerCouponStatus.cancelled.rawValue, "cancelled")
    }

    func testDiscountFormatting() {
        XCTAssertTrue(CouponFormatting.discountText(.amount, 10000, nil).contains("할인"))
        XCTAssertTrue(CouponFormatting.discountText(.rate, 10, nil).hasPrefix("10% 할인"))
        XCTAssertTrue(CouponFormatting.discountText(.rate, 10, 5000).contains("최대"))
    }
}
