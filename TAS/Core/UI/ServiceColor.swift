import SwiftUI

/// 서비스/카테고리 색상 — 웹 `client/features/services/model.ts` 이식.
/// 우선순위: 매장 커스텀(categoryBaseColors) → 기본 맵 → 이름 해시 생성.
enum ServiceColor {
    /// CATEGORY_BASE_COLOR_MAP (웹과 동일).
    static let categoryBaseColorMap: [String: String] = [
        "커트": "#2D7FF9",
        "펌": "#E53935",
        "컬러": "#FB8C00",
        "크리닉": "#00A896",
        "드라이": "#6D6F78",
        "기타": "#8E8E93",
    ]

    /// getCategoryBaseColor(category, storeMap) — 매장 맵 우선.
    static func categoryBaseHex(_ category: String, storeMap: [String: String] = [:]) -> String {
        storeMap[category] ?? categoryBaseColorMap[category] ?? generate(category)
    }

    static func categoryColor(_ category: String, storeMap: [String: String] = [:]) -> Color {
        Color(hex: categoryBaseHex(category, storeMap: storeMap)) ?? .gray
    }

    /// generateCategoryBaseColor — 이름 해시 → HSL(0.62, 0.5).
    private static func generate(_ category: String) -> String {
        var hash: UInt32 = 0
        for scalar in category.unicodeScalars {
            hash = hash &* 31 &+ UInt32(truncatingIfNeeded: scalar.value)
        }
        return hslToHex(h: Double(hash % 360), s: 0.62, l: 0.5)
    }

    /// hslToHex — 웹과 동일 알고리즘.
    private static func hslToHex(h: Double, s: Double, l: Double) -> String {
        let a = s * min(l, 1 - l)
        func component(_ n: Double) -> String {
            let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
            let color = l - a * max(min(k - 3, 9 - k, 1), -1)
            return String(format: "%02x", Int((255 * color).rounded()))
        }
        return "#\(component(0))\(component(8))\(component(4))"
    }
}
