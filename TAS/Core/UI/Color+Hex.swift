import SwiftUI

/// hex 문자열 파싱/조립 — `Color(hex:)`와 `ServiceColor`의 색 보정이 **같은 파서**를 쓰게 한다.
///
/// 따로 두면 한쪽만 늘어나 조용히 갈린다. 실제로 그랬다: 3자리 축약 지원을
/// `Color(hex:)`에만 넣는 바람에 `ServiceColor.adjustHex`는 `#999` 같은 값을 받으면
/// 카테고리 전체를 폴백 회색으로 떨어뜨렸다(매장 커스텀 `categoryBaseColors`는 자유 문자열).
enum HexColor {
    /// "#2D7FF9" / "2D7FF9" / 3자리 축약("#999") → RGB 채널. 실패 시 nil.
    static func components(_ hex: String) -> (r: Int, g: Int, b: Int)? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        return (
            Int((value & 0xFF0000) >> 16),
            Int((value & 0x00FF00) >> 8),
            Int(value & 0x0000FF)
        )
    }

    /// RGB 채널 → "#rrggbb". 범위를 벗어난 값은 0…255로 자른다.
    static func string(r: Int, g: Int, b: Int) -> String {
        func channel(_ v: Int) -> String { String(format: "%02x", min(max(v, 0), 255)) }
        return "#\(channel(r))\(channel(g))\(channel(b))"
    }
}

extension Color {
    /// hex 문자열로 Color 생성. 실패 시 nil. 3자리 축약도 받는다(웹 폴백색이 `#999`).
    init?(hex: String?) {
        guard let hex, let c = HexColor.components(hex) else { return nil }
        self.init(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }
}

extension HexColor {
    /// 웹 `features/colors/contrast.ts` backgroundForWhiteText — 흰 글자를 얹는 색 바탕(담당자 뱃지)은
    /// 흰 글자가 4.5:1 이 될 때까지 같은 색을 진하게(색상·채도 유지, 밝기만 0.01씩 내림). 이미 진하면 그대로.
    /// 바탕은 사장님이 고른 색이라 다른 색으로 바꾸지 않는다(노랑 #FBBC04 → #926D02). 세 플랫폼이 같은 값을 낸다.
    static func backgroundForWhiteText(r: Int, g: Int, b: Int) -> (r: Int, g: Int, b: Int) {
        func luminance(_ r: Int, _ g: Int, _ b: Int) -> Double {
            func f(_ v: Int) -> Double {
                let x = Double(v) / 255
                return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
        }
        func whiteContrast(_ r: Int, _ g: Int, _ b: Int) -> Double { 1.05 / (luminance(r, g, b) + 0.05) }
        if whiteContrast(r, g, b) >= 4.5 { return (r, g, b) }

        let (rn, gn, bn) = (Double(r) / 255, Double(g) / 255, Double(b) / 255)
        let maxV = max(rn, gn, bn), minV = min(rn, gn, bn)
        let l0 = (maxV + minV) / 2
        let d = maxV - minV
        let s = d == 0 ? 0 : (l0 > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV))
        let h: Double
        if d == 0 { h = 0 }
        else if maxV == rn { h = ((gn - bn) / d + (gn < bn ? 6 : 0)) * 60 }
        else if maxV == gn { h = ((bn - rn) / d + 2) * 60 }
        else { h = ((rn - gn) / d + 4) * 60 }

        var l = l0
        while l > 0 {
            let a = s * min(l, 1 - l)
            func f(_ n: Double) -> Int {
                let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
                return Int((255 * (l - a * max(min(k - 3, 9 - k, 1), -1))).rounded())
            }
            let c = (f(0), f(8), f(4))
            if whiteContrast(c.0, c.1, c.2) >= 4.5 { return c }
            l -= 0.01
        }
        return (0, 0, 0)
    }
}

extension Color {
    /// 흰 글자를 얹을 바탕 — 밝은 색만 같은 색을 진하게(`HexColor.backgroundForWhiteText`).
    var forWhiteText: Color {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        let c = HexColor.backgroundForWhiteText(r: Int((r * 255).rounded()), g: Int((g * 255).rounded()), b: Int((b * 255).rounded()))
        return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }
}

extension Color {
    /// 밝은·어두운 모드에 다른 색 — 웹 색(밝은 바탕 기준 4.5:1)이 어두운 바탕에선 대비가 모자라는 자리(위험 글자·링크)에 쓴다.
    static func adaptive(light: String, dark: String) -> Color {
        let l = UIColor(Color(hex: light) ?? .primary)
        let d = UIColor(Color(hex: dark) ?? .primary)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? d : l })
    }

    /// 위험(취소·노쇼·삭제) 글자 — 밝은 모드는 웹 `#C5221F`, 어두운 모드는 밝힌 빨강.
    static let dangerText = adaptive(light: "#C5221F", dark: "#FF6B6B")
    /// 흰 글자를 얹는 브랜드 채움(주 버튼·선택한 날) — 모드와 상관없이 웹 `--brand-color` #6526D9(흰 글자 7:1).
    /// AccentColor 는 어두운 모드에서 글자가 읽히게 밝은 보라(#A57BFF)로 바뀌는데, 그 위 흰 글자는 3:1 이라 채움엔 따로 쓴다.
    static let brandFill = Color(hex: "#6526D9") ?? .purple
    /// 링크(고객명) — 밝은 모드는 웹 `#1967D2`(흰 바탕 5.3:1), 어두운 모드는 밝힌 파랑.
    static let linkText = adaptive(light: "#1967D2", dark: "#6CA8FF")
}
