import SwiftUI

/// 레이어 하단 버튼 — 웹 `StyledActionButton`(ModalStyles) 이식. 채운 색은 주 동작 하나만, 나머지는 테두리.
/// 보이는 크기는 웹(높이 32·글자 13·둥글기 8 — 짧은 글자도 가로로 긴 버튼), 누르는 자리는 iOS 기준 44pt(위아래 6 은 안 보이는 여백).
struct ActionButtonStyle: ButtonStyle {
    enum Kind { case primary, dangerOutline, plain }
    var kind: Kind = .plain

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
            .opacity(configuration.isPressed ? 0.7 : 1)
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
