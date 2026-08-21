import SwiftUI

extension Color {
    /// "#2D7FF9" / "2D7FF9" / 3자리 축약("#999") 형태의 hex 문자열로 Color 생성. 실패 시 nil.
    /// 3자리를 받는 이유: 웹의 서비스 색 폴백(`FALLBACK_COLOR`)이 `#999`다.
    init?(hex: String?) {
        guard let hex else { return nil }
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }
}
