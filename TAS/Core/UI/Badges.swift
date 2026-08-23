import SwiftUI

/// 배지 색 — 웹 `RESERVATION_STATUS_BADGE_STYLES`(reservations/model.ts) 이식.
///
/// 웹은 단일 예약 상태 배지와 고객 목록의 카운트 배지("예약(3)")를 **같은 맵**으로 그린다.
/// 그래서 색은 여기 한 벌만 두고, 무엇을 그리든 톤만 골라 쓴다.
/// (이전엔 `StatusBadge` 안에 switch로 박혀 있어 카운트 배지를 그릴 수 없었고,
///  `completed` 톤은 아예 이식되지 않았다.)
enum BadgeTone {
    case booked, cancelled, completed, noshow, paid, unpaid, requested

    var foregroundHex: String {
        switch self {
        case .booked: return "#4285F4"
        case .cancelled: return "#999"
        case .completed: return "#34A853"
        case .noshow: return "#EA4335"
        case .paid: return "#6526D9"
        case .unpaid: return "#92400E"
        case .requested: return "#A88417"
        }
    }

    var backgroundHex: String {
        switch self {
        case .booked: return "#E8F0FE"
        case .cancelled: return "#F1F1F1"
        case .completed: return "#E6F4EA"
        case .noshow: return "#FCE8E6"
        case .paid: return "#6526D9"     // 웹은 rgba(...,0.08) — 아래 opacity로 맞춘다
        case .unpaid: return "#FEF3C7"
        case .requested: return "#FEF7E0"
        }
    }

    /// 웹이 배경을 rgba로 준 톤만 불투명도를 따로 적용한다.
    var backgroundOpacity: Double { self == .paid ? 0.08 : 1 }

    var foreground: Color { Color(hex: foregroundHex) ?? .gray }
    var background: Color { (Color(hex: backgroundHex) ?? .gray.opacity(0.15)).opacity(backgroundOpacity) }
}

/// 배지 한 칸 — 웹 `ReservationStatusBadge` styled span(3/8 패딩, radius 4, 11pt 600) 이식.
struct ToneBadge: View {
    let tone: BadgeTone
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tone.background, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(tone.foreground)
    }
}

/// 예약 상태 뱃지 — 캘린더 행·예약 상세 등에서 공용으로 재사용.
struct StatusBadge: View {
    let state: ReservationDisplayState

    var body: some View {
        ToneBadge(tone: tone, text: state.label)
    }

    private var tone: BadgeTone {
        switch state {
        case .booked: return .booked
        case .paid: return .paid
        case .cancelled: return .cancelled
        case .noshow: return .noshow
        case .requested: return .requested
        }
    }
}

extension CustomerStats.EffectiveStatus {
    /// 색은 여기 한 곳에서만 고른다 — 배지·통계 숫자가 따로 매핑하면 화면마다 어긋난다.
    var tone: BadgeTone {
        switch self {
        case .booked: return .booked
        case .completed: return .completed
        case .cancelled: return .cancelled
        case .noshow: return .noshow
        }
    }
}

/// 고객 목록의 상태별 건수 배지 — 웹 `AddressCustomerSummary`의 "예약(3)" 형태.
struct StatusCountBadge: View {
    let status: CustomerStats.EffectiveStatus
    let count: Int

    var body: some View {
        ToneBadge(tone: status.tone, text: "\(status.label)(\(count))")
    }
}

/// 신규 고객 뱃지 — 웹 `NewCustomerBadge` 대응(첫 방문 표시).
struct NewCustomerBadge: View {
    var body: some View {
        Text("신규")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((Color(hex: "00A896") ?? .teal).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(Color(hex: "00A896") ?? .teal)
    }
}
