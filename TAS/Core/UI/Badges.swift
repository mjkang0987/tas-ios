import SwiftUI

/// 예약 상태 뱃지 — 웹 `RESERVATION_STATUS_BADGE_STYLES`와 동일 색/라벨.
/// 캘린더 행·예약 상세 등에서 공용으로 재사용.
struct StatusBadge: View {
    let state: ReservationDisplayState

    var body: some View {
        Text(state.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(foreground)
    }

    private var foreground: Color {
        switch state {
        case .booked: return Color(hex: "4285F4") ?? .blue
        case .paid: return Color(hex: "6526D9") ?? .purple
        case .cancelled: return Color(hex: "999999") ?? .gray
        case .noshow: return Color(hex: "EA4335") ?? .red
        case .requested: return Color(hex: "A88417") ?? .orange
        }
    }

    private var background: Color {
        switch state {
        case .booked: return Color(hex: "E8F0FE") ?? .blue.opacity(0.12)
        case .paid: return (Color(hex: "6526D9") ?? .purple).opacity(0.08)
        case .cancelled: return Color(hex: "F1F1F1") ?? .gray.opacity(0.15)
        case .noshow: return Color(hex: "FCE8E6") ?? .red.opacity(0.12)
        case .requested: return Color(hex: "FEF7E0") ?? .orange.opacity(0.12)
        }
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
