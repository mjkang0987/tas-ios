import SwiftUI

/// 서비스/카테고리 색상 — 웹 `client/features/services/model.ts` 이식.
///
/// 웹은 색을 **서비스 단위**로 준다: 카테고리 기본색(`CATEGORY_BASE_COLOR_MAP`)에
/// `SHADE_STEPS` 농도를 얹어 같은 카테고리 안에서도 서비스마다 다른 색이 나온다
/// (커트 3종이 서로 다른 파랑). 카테고리 색만 쓰면 이 구분이 사라진다.
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

    /// LEGACY_NAME_MAP — 옛 서비스명을 현재 카탈로그 이름으로 매핑(하위호환).
    static let legacyNameMap: [String: String] = [
        "남자 일반펌": "일반펌",
        "남자 디자인펌": "디자인펌",
        "여자 일반펌": "일반펌",
        "여자 디자인펌": "디자인펌",
        "셋팅펌": "디지털/셋팅",
        "남자 매직": "매직",
        "여자 매직": "매직",
        "다운펌+커트": "디자인펌",
        "펌 롤": "일반펌",
        "펌 매직": "매직",
        "뿌리/전체(멋내기)": "전체염색",
        "뿌리/전체(새치)": "뿌리염색",
    ]

    /// FALLBACK_COLOR (웹과 동일한 3자리 표기).
    static let fallbackHex = "#999"

    /// SHADE_STEPS — 카테고리 안 서비스 순서대로 얹는 밝기 보정.
    private static let shadeSteps = [0, 14, -14, 26, -26, 36, -36, 46, -46]

    // MARK: - 카테고리 색

    /// getCategoryBaseColor(category, storeMap) — 매장 맵 우선.
    static func categoryBaseHex(_ category: String, storeMap: [String: String] = [:]) -> String {
        storeMap[category] ?? categoryBaseColorMap[category] ?? generate(category)
    }

    static func categoryColor(_ category: String, storeMap: [String: String] = [:]) -> Color {
        Color(hex: categoryBaseHex(category, storeMap: storeMap)) ?? .gray
    }

    // MARK: - 서비스 색

    /// buildServiceColorMap — 서비스명 → hex. 카테고리 기본색 + 카탈로그 내 순번 농도.
    /// 순번은 **카탈로그 순서**로 정해지므로 catalog 배열 순서를 흐트러뜨리면 색이 바뀐다.
    static func buildServiceColorMap(
        catalog: [ServiceItem],
        storeMap: [String: String] = [:]
    ) -> [String: String] {
        var categoryOrder: [String] = []
        var grouped: [String: [ServiceItem]] = [:]
        for item in catalog {
            if grouped[item.category] == nil { categoryOrder.append(item.category) }
            grouped[item.category, default: []].append(item)
        }

        var colorMap: [String: String] = [:]
        for category in categoryOrder {
            let base = categoryBaseHex(category, storeMap: storeMap)
            for (index, item) in (grouped[category] ?? []).enumerated() {
                colorMap[item.name] = adjustHex(base, delta: shadeDelta(index))
            }
        }

        // 옛 이름은 매핑된 현재 이름과 같은 색으로.
        for (legacy, current) in legacyNameMap {
            if let color = colorMap[current], colorMap[legacy] == nil {
                colorMap[legacy] = color
            }
        }
        return colorMap
    }

    /// getServiceColor(service, colorMap) — 정확히 일치하는 이름이 없으면
    /// 긴 이름부터 부분 문자열로 훑고, 그래도 없으면 폴백.
    ///
    /// 웹은 길이 내림차순·동률은 카탈로그 삽입 순서지만 Swift `Dictionary`엔 순서가 없다.
    /// 동률은 이름 오름차순으로 고정해 결정론만 맞춘다(카탈로그에 없는 이름에서만 타는 경로).
    static func serviceHex(_ service: String, in colorMap: [String: String]) -> String {
        if let direct = colorMap[service] { return direct }
        let names = colorMap.keys.sorted {
            $0.count == $1.count ? $0 < $1 : $0.count > $1.count
        }
        for name in names where service.contains(name) {
            return colorMap[name] ?? fallbackHex
        }
        return fallbackHex
    }

    static func color(_ service: String, in colorMap: [String: String]) -> Color {
        Color(hex: serviceHex(service, in: colorMap)) ?? .gray
    }

    // MARK: - 서비스 문자열

    /// parseServiceString — "커트+펌"을 개별 시술로 분리.
    /// `knownNames`를 주면 이름 자체에 `+`가 든 서비스("다운펌+커트")를 greedy로 보존한다.
    static func parseServiceString(_ str: String, knownNames: Set<String>? = nil) -> [String] {
        guard !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let parts = str
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let knownNames, parts.count > 1 else { return parts }

        var result: [String] = []
        var i = 0
        while i < parts.count {
            var matched = false
            var j = parts.count
            while j > i + 1 {
                let combined = parts[i..<j].joined(separator: "+")
                if knownNames.contains(combined) {
                    result.append(combined)
                    i = j
                    matched = true
                    break
                }
                j -= 1
            }
            if !matched {
                result.append(parts[i])
                i += 1
            }
        }
        return result
    }

    /// joinServiceNames — 분리의 역연산.
    static func joinServiceNames(_ names: [String]) -> String { names.joined(separator: "+") }

    // MARK: - 내부

    /// getShadeDelta(index) — 9개 스텝을 돌고 한 바퀴마다 8씩 더 벌린다(부호 교대).
    private static func shadeDelta(_ index: Int) -> Int {
        let base = shadeSteps[index % shadeSteps.count]
        let cycle = index / shadeSteps.count
        return base + (cycle * 8 * (cycle % 2 == 0 ? 1 : -1))
    }

    /// adjustHexColor(hex, delta) — RGB 각 채널에 delta를 더하고 0…255로 자른다.
    private static func adjustHex(_ hex: String, delta: Int) -> String {
        guard let c = HexColor.components(hex) else { return fallbackHex }
        return HexColor.string(r: c.r + delta, g: c.g + delta, b: c.b + delta)
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
        func channel(_ n: Double) -> Int {
            let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
            return Int((255 * (l - a * max(min(k - 3, 9 - k, 1), -1))).rounded())
        }
        return HexColor.string(r: channel(0), g: channel(8), b: channel(4))
    }
}
