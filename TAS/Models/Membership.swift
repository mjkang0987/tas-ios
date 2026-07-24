import Foundation

/// 회원권 상품(카탈로그) — memberships/model.ts `MembershipProduct`.
/// 적립금(금액)과 별개의 횟수·기간권. (고객 발급·차감은 웹도 후속 단계라 상품 CRUD까지만.)
struct MembershipProduct: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var totalCount: Int?    // 횟수 (nil = 무제한/기간제)
    var validDays: Int?     // 발급일로부터 유효일수 (nil = 무기한)
    var price: Int
    var status: String      // "active" | "archived"
}

/// GET /api/memberships 응답(발급된 회원권 `memberships`는 아직 미사용).
struct MembershipsResponse: Codable {
    var products: [MembershipProduct]
}
