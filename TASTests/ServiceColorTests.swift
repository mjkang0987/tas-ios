import XCTest
import SwiftUI
@testable import TAS

/// 서비스 색·시술 문자열 — 웹 `client/features/services/model.ts` 이식본 검증.
///
/// 여기서 보는 핵심은 **카테고리색과 서비스색이 다르다**는 것이다. 웹은 카테고리 기본색에
/// `SHADE_STEPS` 농도를 얹어 같은 카테고리 안에서도 서비스마다 다른 색을 준다.
/// 카테고리색을 그대로 쓰면 커트 3종이 전부 같은 파랑이 되는데, 그게 이식 전 iOS 상태였다.
final class ServiceColorTests: XCTestCase {

    private func item(_ name: String, _ category: String) -> ServiceItem {
        ServiceItem(name: name, durationMinutes: 30, category: category, price: 10000)
    }

    /// 웹 SERVICE_CATALOG의 순서를 그대로 따른다 — 색이 카탈로그 순번으로 정해지기 때문.
    private var catalog: [ServiceItem] {
        [
            item("남성커트", "커트"), item("여성커트", "커트"), item("주니어커트", "커트"),
            item("일반펌", "펌"), item("디자인펌", "펌"), item("디지털/셋팅", "펌"),
        ]
    }

    // MARK: - 서비스별 농도

    func testSameCategoryServicesGetDifferentShades() {
        let map = ServiceColor.buildServiceColorMap(catalog: catalog)
        XCTAssertEqual(Set(["남성커트", "여성커트", "주니어커트"].compactMap { map[$0] }).count, 3)
    }

    /// 커트 기본색 #2D7FF9 (45,127,249)에 SHADE_STEPS[0,14,-14]를 얹은 값.
    func testShadeStepsMatchWeb() {
        let map = ServiceColor.buildServiceColorMap(catalog: catalog)
        XCTAssertEqual(map["남성커트"], "#2d7ff9")   // delta 0
        XCTAssertEqual(map["여성커트"], "#3b8dff")   // delta +14, b는 263 → 255로 잘림
        XCTAssertEqual(map["주니어커트"], "#1f71eb")  // delta -14
    }

    func testCategoryColorIsNotServiceColor() {
        let map = ServiceColor.buildServiceColorMap(catalog: catalog)
        XCTAssertEqual(ServiceColor.categoryBaseHex("커트"), "#2D7FF9")
        XCTAssertNotEqual(map["여성커트"], "#2D7FF9")
    }

    func testStoreCustomCategoryColorWins() {
        let map = ServiceColor.buildServiceColorMap(catalog: catalog, storeMap: ["커트": "#000000"])
        XCTAssertEqual(map["남성커트"], "#000000")
        XCTAssertEqual(map["여성커트"], "#0e0e0e")  // delta +14
    }

    func testLegacyNameSharesColorWithCurrentName() {
        let map = ServiceColor.buildServiceColorMap(catalog: catalog)
        // LEGACY_NAME_MAP: 셋팅펌 → 디지털/셋팅
        XCTAssertEqual(map["셋팅펌"], map["디지털/셋팅"])
        XCTAssertNotNil(map["셋팅펌"])
    }

    // MARK: - 색 해석

    func testUnknownServiceFallsBackToWebFallbackColor() {
        let map = ServiceColor.buildServiceColorMap(catalog: catalog)
        XCTAssertEqual(ServiceColor.serviceHex("두피 스케일링", in: map), ServiceColor.fallbackHex)
    }

    /// 이름이 정확히 없으면 **긴 이름부터** 부분 문자열로 훑는다(웹과 동일).
    func testSubstringMatchPrefersLongerName() {
        let map = ServiceColor.buildServiceColorMap(catalog: catalog)
        XCTAssertEqual(ServiceColor.serviceHex("남성커트 (숱정리)", in: map), map["남성커트"])
    }

    // MARK: - 시술 문자열 분리

    func testSplitsCombinedServices() {
        XCTAssertEqual(ServiceColor.parseServiceString("커트+펌"), ["커트", "펌"])
    }

    func testTrimsAndDropsEmptyParts() {
        XCTAssertEqual(ServiceColor.parseServiceString(" 커트 + + 펌 "), ["커트", "펌"])
    }

    func testEmptyStringYieldsNoServices() {
        XCTAssertEqual(ServiceColor.parseServiceString("   "), [])
    }

    /// 이름 자체에 '+'가 든 서비스("다운펌+커트")는 통째로 보존한다 — greedy.
    func testKeepsServiceNamesContainingPlus() {
        let known: Set<String> = ["다운펌+커트", "펌", "커트", "다운펌"]
        XCTAssertEqual(ServiceColor.parseServiceString("다운펌+커트+펌", knownNames: known),
                       ["다운펌+커트", "펌"])
    }

    func testWithoutKnownNamesPlusAlwaysSplits() {
        XCTAssertEqual(ServiceColor.parseServiceString("다운펌+커트"), ["다운펌", "커트"])
    }

    func testJoinIsInverseOfSplit() {
        XCTAssertEqual(ServiceColor.joinServiceNames(["커트", "펌"]), "커트+펌")
    }

    // MARK: - hex 파싱

    /// 웹 FALLBACK_COLOR가 3자리(#999)라 Color(hex:)가 이를 받아야 한다.
    func testThreeDigitHexExpands() {
        XCTAssertNotNil(Color(hex: ServiceColor.fallbackHex))
        XCTAssertNotNil(Color(hex: "#abc"))
        XCTAssertNil(Color(hex: "#ab"))
        XCTAssertNil(Color(hex: "not-a-color"))
    }
}
