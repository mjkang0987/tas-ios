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
