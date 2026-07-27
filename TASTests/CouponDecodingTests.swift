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

    // MARK: - oncePerCustomer (고객당 1장)

    func testOncePerCustomerDecodes() throws {
        let json = Data(#"""
        {"products":[{"id":"cp1","name":"생일쿠폰","discountType":"amount","discountValue":5000,
          "maxDiscount":null,"minOrderAmount":null,"validDays":null,"code":null,
          "oncePerCustomer":true,"status":"active"}]}
        """#.utf8)
        let resp = try JSONDecoder().decode(CouponsResponse.self, from: json)
        XCTAssertEqual(resp.products.first?.oncePerCustomer, true)
    }

    /// 서버가 아직 필드를 안 주는 경우(머지 전)에도 디코딩되고 false로 취급.
    func testOncePerCustomerDefaultsFalseWhenMissing() throws {
        let json = Data(#"""
        {"products":[{"id":"cp1","name":"쿠폰","discountType":"rate","discountValue":10,
          "maxDiscount":null,"minOrderAmount":null,"validDays":null,"code":null,"status":"active"}]}
        """#.utf8)
        let resp = try JSONDecoder().decode(CouponsResponse.self, from: json)
        XCTAssertEqual(resp.products.first?.oncePerCustomer, false)
    }

    func testOncePerCustomerEncodes() throws {
        let p = CouponProduct(id: "cp1", name: "생일쿠폰", discountType: .amount, discountValue: 5000,
                              maxDiscount: nil, minOrderAmount: nil, validDays: nil, code: nil,
                              oncePerCustomer: true, status: "active")
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        XCTAssertEqual(obj["oncePerCustomer"] as? Bool, true)
    }

    func testDiscountFormatting() {
        XCTAssertTrue(CouponFormatting.discountText(.amount, 10000, nil).contains("할인"))
        XCTAssertTrue(CouponFormatting.discountText(.rate, 10, nil).hasPrefix("10% 할인"))
        XCTAssertTrue(CouponFormatting.discountText(.rate, 10, 5000).contains("최대"))
    }
}
