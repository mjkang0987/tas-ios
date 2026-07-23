import SwiftUI

/// 선택형 필터 칩(공용). 라벨 + 선택 상태 + 선택적 색 점.
/// 캘린더 담당자 필터 등 가로 칩 바에서 재사용.
struct FilterChip: View {
    let label: String
    var color: Color? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let color { ColorDot(color: color, size: 7) }
                Text(label).font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
