import SwiftUI

/// 레이어 하단 버튼 — 웹 `StyledActionButton`(ModalStyles) 이식. 채운 색은 주 동작 하나만, 나머지는 테두리.
/// 보이는 크기는 웹(높이 32·글자 13·둥글기 8 — 짧은 글자도 가로로 긴 버튼), 누르는 자리는 iOS 기준 44pt(위아래 6 은 안 보이는 여백).
struct ActionButtonStyle: ButtonStyle {
    enum Kind { case primary, dangerOutline, plain }
    var kind: Kind = .plain
    // 직접 만든 버튼 모양은 .disabled 를 그려 주지 않는다 — 못 누르는 버튼이 눌리는 것처럼 보이지 않게
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.tasMedium.weight(kind == .plain ? .medium : .semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if kind != .primary {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(border, lineWidth: 1)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .dangerOutline: return .dangerText
        case .plain: return .textSecondary // 시스템 .secondary 는 흰 바탕 3.4:1 — 글자 대비 4.5:1 미달
        }
    }

    private var background: Color {
        kind == .primary ? .brandFill : Color(.systemBackground)
    }

    private var border: Color {
        kind == .dangerOutline ? Color.dangerText.opacity(0.4) : Color(.separator)
    }
}

extension ButtonStyle where Self == ActionButtonStyle {
    static func action(_ kind: ActionButtonStyle.Kind = .plain) -> ActionButtonStyle { ActionButtonStyle(kind: kind) }
}

extension View {
    /// 레이어 머리의 주 버튼(저장·충전) — 웹 저장 버튼처럼 보라 채움 + 흰 글자.
    /// iOS 26 툴바는 어두운 화면에서 채운 버튼 글자를 검게 칠해(foregroundStyle 도 무시) 보라 위 대비가 2:1 로 떨어진다.
    /// 이 버튼만 밝은 화면으로 그리면 밝은 화면과 같은 흰 글자가 된다(바탕은 어차피 보라 채움).
    func primaryToolbarButton() -> some View {
        buttonStyle(.borderedProminent).tint(.brandFill).environment(\.colorScheme, .light)
    }
}
