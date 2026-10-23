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

    private func ratio(_ x: String, _ y: String) -> Double {
        let (a, b) = (luminance(x), luminance(y))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// 어두운 화면 — 글자 7:1 이상, 배지 바탕이 카드(#1C1C1E)와 구분(1.3:1 이상). 첫 시안은 1.2:1 로 배지가 묻혔다(지시자 2026-10-24).
    func testDarkTonesAreReadableAndStandOut() {
        let tones: [BadgeTone] = [.booked, .cancelled, .completed, .noshow, .paid, .unpaid, .requested]
        for tone in tones {
            XCTAssertGreaterThanOrEqual(ratio(tone.darkForegroundHex, tone.darkBackgroundHex), 7, "\(tone) 글자")
            XCTAssertGreaterThanOrEqual(ratio(tone.darkBackgroundHex, "#1C1C1E"), 1.3, "\(tone) 바탕")
        }
    }

    /// 웹 features/colors/contrast.ts backgroundForWhiteText 와 같은 결과(세 플랫폼이 같은 색을 낸다).
    func testBackgroundForWhiteTextMatchesWeb() {
        let expected: [String: String] = [
            "#4285F4": "#206ff2", "#34A853": "#298542", "#EA4335": "#e42718", "#FBBC04": "#926d02",
            "#FF6D01": "#c35300", "#46BDC6": "#2a8087", "#9334E6": "#9334e6", "#E91E8C": "#dd1682",
            "#2D7FF9": "#0f6df8", "#E85D75": "#e12c4b", "#00A896": "#008476", "#FB8C00": "#ae6100",
        ]
        for (input, output) in expected {
            let c = HexColor.components(input)!
            let d = HexColor.backgroundForWhiteText(r: c.r, g: c.g, b: c.b)
            XCTAssertEqual(HexColor.string(r: d.r, g: d.g, b: d.b), output, input)
        }
        for v in 0...255 {
            let d = HexColor.backgroundForWhiteText(r: v, g: v, b: v)
            let hex = HexColor.string(r: d.r, g: d.g, b: d.b)
            XCTAssertGreaterThanOrEqual(1.05 / (luminance(hex) + 0.05), 4.5, "회색 \(v)")
        }
    }
}
