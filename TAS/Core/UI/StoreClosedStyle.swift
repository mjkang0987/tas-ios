import SwiftUI

/// 캘린더의 휴무(임시 휴업일·정기 휴무) 표시 — 웹(tas) 이식.
///
/// **글자가 아니라 배경 틴트 + 테두리로 표시한다.** 웹에서 처음엔 "휴업일" 배지를 넣었는데
/// 모바일 좁은 열(390px 주 뷰)에 글자가 안 들어가 한 글자씩 세로로 쪼개져 결국 걷어냈다.
/// 앱의 월 셀은 그보다 더 좁다.
///
/// 색만으로는 VoiceOver 에 아무것도 전달되지 않으므로 `accessibilityLabel` 을 함께 붙인다.
/// 이 modifier 를 쓰는 것만으로 라벨이 따라오게 해서, 호출부가 빠뜨릴 수 없게 한다.
///
/// 붙이는 곳이 월 셀(44pt 정사각)·일 헤더(가로 바)·주 섹션 헤더로 크기가 제각각이라
/// 뷰를 감싸지 않고 **장식만 입히는 modifier** 로 둔다(감싸면 기존 여백·정렬이 틀어진다).
private struct StoreClosedStyle: ViewModifier {
    let kind: StoreClosedKind?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if let kind {
            content
                .background(tint(kind), in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(border(kind), lineWidth: 1)
                )
                .accessibilityLabel(kind.label)
        } else {
            content
        }
    }

    /// 임시 휴업일은 오너가 직접 찍은 날이라 눈에 띄어야 하고(적색 계열),
    /// 정기 휴무는 매주 반복이라 배경처럼 가라앉힌다(회색 계열). 웹과 같은 구분.
    private func tint(_ kind: StoreClosedKind) -> Color {
        switch kind {
        case .date: return Color(hex: "FF3B30")?.opacity(0.10) ?? Color.red.opacity(0.10)
        case .weekday: return Color.secondary.opacity(0.10)
        }
    }

    private func border(_ kind: StoreClosedKind) -> Color {
        switch kind {
        case .date: return Color(hex: "FF3B30")?.opacity(0.35) ?? Color.red.opacity(0.35)
        case .weekday: return Color.secondary.opacity(0.30)
        }
    }
}

extension View {
    /// 휴무면 틴트 + 테두리 + VoiceOver 라벨을 입힌다. `nil` 이면 아무것도 하지 않는다.
    /// 표시 전용이다 — 웹과 마찬가지로 휴무일에도 예약 생성은 막지 않는다.
    func storeClosed(_ kind: StoreClosedKind?, cornerRadius: CGFloat = 8) -> some View {
        modifier(StoreClosedStyle(kind: kind, cornerRadius: cornerRadius))
    }
}
