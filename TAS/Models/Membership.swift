import Foundation

/// 회원권 상품(카탈로그) — memberships/model.ts `MembershipProduct`.
/// 적립금(금액)과 별개의 횟수·기간권.
struct MembershipProduct: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var totalCount: Int?    // 횟수 (nil = 무제한/기간제)
    var validDays: Int?     // 발급일로부터 유효일수 (nil = 무기한)
    var price: Int
    var status: String      // "active" | "archived"
}

/// 발급된 회원권 상태 — memberships/model.ts `CustomerMembership.status`.
enum CustomerMembershipStatus: String, Codable, Hashable {
    case active
    case expired
    case usedUp = "used_up"
    case cancelled

    var label: String {
        switch self {
        case .active: return "사용중"
        case .expired: return "만료"
        case .usedUp: return "소진"
        case .cancelled: return "취소"
        }
    }
}

/// 고객에게 발급된 회원권 — memberships/model.ts `CustomerMembership`.
/// 발급 시점 상품 스냅샷 + 잔여 횟수/만료. (발급·차감은 로그인 전용 — 웹 `membership-issue`·`membership-use`)
struct CustomerMembership: Codable, Identifiable, Hashable {
    var id: String
    var customerId: Int             // 고객 legacyId
    var productId: String?
    var name: String                // 발급 시점 상품명 스냅샷
    var totalCount: Int?
    var remainingCount: Int?
    var issuedAt: String
    var expiresAt: String?
    var status: CustomerMembershipStatus
}

/// GET /api/memberships 응답 — 상품 + 발급 목록(로그인 시). 게스트는 발급분 없음.
struct MembershipsResponse: Codable {
    var products: [MembershipProduct]
    var memberships: [CustomerMembership]? = nil
}

/// `/api/membership-use` 액션 — 수동 차감/복원.
enum MembershipUseAction: String, Codable {
    case use
    case restore
}
