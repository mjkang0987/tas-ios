import XCTest
@testable import TAS

/// 상태 배지 글자 대비 — 배경 위 4.5:1 이상(WCAG AA, 작은 글자). 웹 badgeContrast.test.ts 와 같은 기준.
final class BadgeContrastTests: XCTestCase {
    private func luminance(_ hex: String) -> Double {
        let c = HexColor.components(hex)!
        func f(_ v: Int) -> Double {
            let x = Double(v) / 255
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b)
    }

    /// 배경 불투명도가 1 보다 작으면 흰 바탕 위에 섞은 색으로 본다.
    private func background(_ tone: BadgeTone) -> String {
        let c = HexColor.components(tone.backgroundHex)!
        let a = tone.backgroundOpacity
        func mix(_ v: Int) -> Int { Int((Double(v) * a + 255 * (1 - a)).rounded()) }
        return HexColor.string(r: mix(c.r), g: mix(c.g), b: mix(c.b))
    }

    func testEveryToneMeetsAA() {
        let tones: [BadgeTone] = [.booked, .cancelled, .completed, .noshow, .paid, .unpaid, .requested]
        for tone in tones {
            let (a, b) = (luminance(tone.foregroundHex), luminance(background(tone)))
            let ratio = (max(a, b) + 0.05) / (min(a, b) + 0.05)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(tone) 대비 \(ratio)")
        }
    }
}
