import Foundation

/// 쿠폰 할인 유형 — coupons/model.ts `CouponDiscountType`.
enum CouponDiscountType: String, Codable, Hashable, CaseIterable {
    case amount, rate
    var label: String { self == .amount ? "정액(원)" : "정률(%)" }
}

/// 쿠폰 상품(템플릿) — coupons/model.ts `CouponProduct`.
/// (발급·결제 차감은 웹도 "추후 지원" 상태라 상품 등록까지만 다룬다.)
struct CouponProduct: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var discountType: CouponDiscountType
    var discountValue: Int          // 원(amount) 또는 %(rate)
    var maxDiscount: Int?           // rate일 때 최대 할인액
    var minOrderAmount: Int?        // 최소 주문금액
    var validDays: Int?             // 발급일+유효일수 (nil = 무기한)
    var code: String?               // 코드형이면 코드 (nil = 직접발급 전용)
    var status: String              // "active" | "archived"
}

/// GET /api/coupons 응답(발급된 쿠폰 `coupons`는 아직 미사용).
struct CouponsResponse: Codable {
    var products: [CouponProduct]
}
