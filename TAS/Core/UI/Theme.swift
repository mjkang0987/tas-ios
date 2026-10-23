import SwiftUI

/// 공용 디자인 값 — 웹 `styles/globalStyle.ts`·안드로이드 `TasTokens.kt` 와 같은 값(지시자 2026-10-24: 세 플랫폼 일관성).
/// 밝은 값은 웹 그대로, 어두운 값은 같은 색을 어두운 바탕에 맞춘 것(글자 7:1 이상, 바탕이 카드와 구분). 시스템 테마를 따라간다.
/// 화면에서 색·글자 크기를 직접 적지 말고 여기 이름을 쓴다.
extension Color {
    // MARK: 글자 — 웹 --black-color · --dark-gray-color · --dark-gray-color2
    static let textPrimary = adaptive(light: "#212121", dark: "#F5F5F7")
    static let textSecondary = adaptive(light: "#525252", dark: "#D1D1D6")
    static let textTertiary = adaptive(light: "#6E6E6E", dark: "#AEAEB2")

    // MARK: 선 — 웹 --border-color · --light-gray-color
    static let borderLine = adaptive(light: "#CCCCCC", dark: "#48484A")
    static let dividerLine = adaptive(light: "#E3E3E3", dark: "#3A3A3C")

    // MARK: 의미 색(글자로 쓰는 것) — 웹 --success-text · --warning-text · --info-color · --caution-color · --orange-color
    static let successText = adaptive(light: "#15803D", dark: "#A8DAB5")
    static let warningText = adaptive(light: "#92400E", dark: "#FDE68A")
    static let infoText = adaptive(light: "#1660CC", dark: "#AECBFA")
    static let cautionText = adaptive(light: "#806600", dark: "#F6D860")
    /// 주황(현재 시각 선·강조 점) — 웹 --orange-color. 글자에는 쓰지 않는다(흰 바탕 대비 부족).
    static let accentOrange = Color(hex: "#FF7300") ?? .orange
    /// 네이버 — 웹 --naver-color(흰 글자 바탕).
    static let naverFill = Color(hex: "#208200") ?? .green
    /// 파랑 글자(적립금 증감 등) — 웹 --blue-color hsl(196,100%,32%).
    static let blueText = adaptive(light: "#0080A3", dark: "#7FD4F0")
    /// 흰 글자를 얹는 위험 채움(알림 개수 배지 등) — 웹 --danger-color. 모드와 상관없이 고정(흰 글자 4.9:1).
    static let dangerFill = Color(hex: "#C93A30") ?? .red
    /// 신규 고객 — 웹 --new-customer-color.
    static let newCustomerText = adaptive(light: "#00756A", dark: "#8EE6DA")
}

/// 글자 단계 — 웹 18 / 16 / 14 / 13 / 12 / 11px 과 같은 pt.
/// iOS 글자 크기 설정(Dynamic Type)을 따라 함께 커지도록 가까운 시스템 단계에 묶는다(안드로이드 sp 와 같은 방식).
/// 시스템 글꼴에는 `relativeTo` 가 없어 `.custom` 을 쓴다 — 없는 이름은 시스템 글꼴로 바뀌고 크기 따라가기는 그대로 산다.
extension Font {
    private static func scaled(_ size: CGFloat, _ style: Font.TextStyle) -> Font {
        .custom(".AppleSystemUIFont", size: size, relativeTo: style)
    }

    /// 18 — 웹 --big-font(레이어 제목·큰 숫자)
    static let tasTitle = scaled(18, .headline).weight(.semibold)
    /// 16 — 웹 --large-font
    static let tasLarge = scaled(16, .callout)
    /// 14 — 웹 --font(본문)
    static let tasBody = scaled(14, .subheadline)
    /// 13 — 웹 --medium-font (= .footnote)
    static let tasMedium = scaled(13, .footnote)
    /// 12 — 웹 --small-font (= .caption)
    static let tasSmall = scaled(12, .caption)
    /// 11 — 웹 --xsmall-font (= .caption2, 배지)
    static let tasXSmall = scaled(11, .caption2)
}

extension Color {
    /// 사장님이 고른 색(서비스 카테고리 등)을 **글자**로 쓸 때 — 밝은 화면은 그대로(웹과 같다),
    /// 어두운 화면은 흰색 쪽으로 섞어 어두운 바탕에서 읽히게 한다.
    var tintText: Color {
        let base = UIColor(self)
        return Color(uiColor: UIColor { traits in
            guard traits.userInterfaceStyle == .dark else { return base }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            base.getRed(&r, green: &g, blue: &b, alpha: &a)
            let mix: CGFloat = 0.55
            return UIColor(red: r + (1 - r) * mix, green: g + (1 - g) * mix, blue: b + (1 - b) * mix, alpha: a)
        })
    }

    /// 같은 색을 **옅은 바탕**으로 — 밝은 화면은 웹과 같은 9.4%, 어두운 화면은 카드와 구분되게 더 진하게.
    var tintFill: Color {
        let base = UIColor(self)
        return Color(uiColor: UIColor { traits in
            base.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.28 : 0.094)
        })
    }
}
