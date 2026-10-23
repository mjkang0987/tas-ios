import SwiftUI

/// 배지 색 — 웹 `RESERVATION_STATUS_BADGE_STYLES`(reservations/model.ts) 이식.
///
/// 웹은 단일 예약 상태 배지와 고객 목록의 카운트 배지("예약(3)")를 **같은 맵**으로 그린다.
/// 그래서 색은 여기 한 벌만 두고, 무엇을 그리든 톤만 골라 쓴다.
/// (이전엔 `StatusBadge` 안에 switch로 박혀 있어 카운트 배지를 그릴 수 없었고,
///  `completed` 톤은 아예 이식되지 않았다.)
enum BadgeTone {
    case booked, cancelled, completed, noshow, paid, unpaid, requested

    /// 글자색은 배경 위 대비 4.5:1 이상(WCAG AA, 작은 글자) — 2026-10-19 웹·안드로이드와 함께 진하게 바꿈.
    /// 예전 값(대비): booked #4285F4(3.1) · cancelled #999(2.5) · completed #34A853(2.7) · noshow #EA4335(3.3) · requested #A88417(3.3).
    var foregroundHex: String {
        switch self {
        case .booked: return "#1967D2"
        case .cancelled: return "#666666"
        case .completed: return "#137333"
        case .noshow: return "#C5221F"
        case .paid: return "#6526D9"
        case .unpaid: return "#92400E"
        case .requested: return "#806600"
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

/// 담당자 뱃지 — 웹 `AssigneeLabel`(= `ColorTag`, 담당자 색 배경 + 흰 글자 알약) 이식.
/// 점 하나로 두면 이름과 색의 연결이 약하고, 웹과 모양이 갈린다.
struct AssigneeBadge: View {
    let name: String
    let color: Color?

    var body: some View {
        Text(name)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            // 밝은 담당자 색(노랑 등)은 흰 글자가 안 읽혀 같은 색을 진하게 깐다(웹·안드로이드와 같은 값).
            .background((color ?? .secondary).forWhiteText, in: Capsule())
            .foregroundStyle(.white)
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

/// 고객 메모 태그 — 웹 `StyledMemoTag`(태그 색 알약 + 흰 글자) 이식. 예약 상세·고객 상세가 같이 쓴다.
struct MemoTagPill: View {
    let tag: CustomerMemoTag

    var body: some View {
        Text(tag.text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            // 밝은 태그 색은 흰 글자가 안 읽혀 같은 색을 진하게 깐다(웹 backgroundForWhiteText 와 같은 값).
            .background((Color(hex: tag.color) ?? .secondary).forWhiteText, in: Capsule())
            .foregroundStyle(.white)
    }
}
