import Foundation

/// 쿠폰 할인 유형 — coupons/model.ts `CouponDiscountType`.
enum CouponDiscountType: String, Codable, Hashable, CaseIterable {
    case amount, rate
    var label: String { self == .amount ? "정액(원)" : "정률(%)" }
}

/// 쿠폰 상품(템플릿) — coupons/model.ts `CouponProduct`.
struct CouponProduct: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var discountType: CouponDiscountType
    var discountValue: Int          // 원(amount) 또는 %(rate)
    var maxDiscount: Int?           // rate일 때 최대 할인액
    var minOrderAmount: Int?        // 최소 주문금액
    var validDays: Int?             // 발급일+유효일수 (nil = 무기한)
    var code: String?               // 코드형이면 코드 (nil = 직접발급 전용)
    /// true면 고객당 1장 — 미사용(active) 보유분이 있으면 재발급 불가.
    var oncePerCustomer: Bool = false
    var status: String              // "active" | "archived"
}

extension CouponProduct {
    /// 커스텀 디코더 — `oncePerCustomer`를 아직 주지 않는 서버 응답도 허용(false 취급).
    /// (extension에 두어 memberwise init은 그대로 유지 — Store.swift와 동일 패턴)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        discountType = try c.decode(CouponDiscountType.self, forKey: .discountType)
        discountValue = try c.decode(Int.self, forKey: .discountValue)
        maxDiscount = try c.decodeIfPresent(Int.self, forKey: .maxDiscount)
        minOrderAmount = try c.decodeIfPresent(Int.self, forKey: .minOrderAmount)
        validDays = try c.decodeIfPresent(Int.self, forKey: .validDays)
        code = try c.decodeIfPresent(String.self, forKey: .code)
        oncePerCustomer = try c.decodeIfPresent(Bool.self, forKey: .oncePerCustomer) ?? false
        status = try c.decode(String.self, forKey: .status)
    }
}

/// 발급된 쿠폰 상태 — coupons/model.ts `CustomerCoupon.status`.
enum CustomerCouponStatus: String, Codable, Hashable {
    case active
    case used
    case expired
    case cancelled

    var label: String {
        switch self {
        case .active: return "사용가능"
        case .used: return "사용됨"
        case .expired: return "만료"
        case .cancelled: return "취소"
        }
    }
}

/// 고객에게 발급된 쿠폰 — coupons/model.ts `CustomerCoupon`.
/// 발급 시점 상품 스냅샷. (발급은 로그인 전용 — 웹 `coupon-issue`; 결제 차감은 Phase 3 미구현.)
struct CustomerCoupon: Codable, Identifiable, Hashable {
    var id: String
    var customerId: Int             // 고객 legacyId
    var productId: String?
    var name: String                // 발급 시점 상품명 스냅샷
    var discountType: CouponDiscountType
    var discountValue: Int
    var maxDiscount: Int?
    var minOrderAmount: Int?
    var issuedAt: String
    var expiresAt: String?
    var usedAt: String?
    var status: CustomerCouponStatus
}

/// GET /api/coupons 응답 — 상품 + 발급 목록(로그인 시). 게스트는 발급분 없음.
struct CouponsResponse: Codable {
    var products: [CouponProduct]
    var coupons: [CustomerCoupon]? = nil
}
