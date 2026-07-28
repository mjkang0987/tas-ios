import XCTest
@testable import TAS

/// 업종 카탈로그 — 목록에서 내린 업종(사람 진료 3종, 웹 tas #168) 처리 규약 검증.
/// 새로 고를 수는 없지만 기존 데이터의 라벨은 계속 해석돼야 하고, 편집 화면에서
/// 선택값이 비어 보이거나 저장 시 조용히 지워지면 안 된다.
final class ShopCatalogTests: XCTestCase {

    private let retiredValues = ["clinic", "dental", "oriental"]

    func testRetiredIndustriesAreNotSelectable() {
        let selectable = Set(ShopCatalog.industries.map(\.value))
        for value in retiredValues {
            XCTAssertFalse(selectable.contains(value), "\(value)는 선택 목록에서 제외돼야 한다")
        }
        XCTAssertTrue(selectable.contains("vet"), "동물병원은 유지")
    }

    func testRetiredIndustryLabelsStillResolve() {
        XCTAssertEqual(ShopCatalog.shopTypeLabel("clinic"), "병원·의원")
        XCTAssertEqual(ShopCatalog.shopTypeLabel("dental"), "치과")
        XCTAssertEqual(ShopCatalog.shopTypeLabel("oriental"), "한의원")
        // 혼합 토큰도 순서대로 해석.
        XCTAssertEqual(ShopCatalog.shopTypeLabel("clinic,hair"), "병원·의원·헤어샵")
        XCTAssertEqual(ShopCatalog.primaryIndustry(shopType: "oriental")?.label, "한의원")
    }

    func testIndustryGroupsIncludeCurrentRetiredValueOnly() {
        let medicalDefault = ShopCatalog.industryGroups()
            .first { $0.items.contains { $0.value == "vet" } }?.items ?? []
        XCTAssertEqual(medicalDefault.map(\.value), ["vet"], "기본 목록엔 동물병원만")

        let medicalWithLegacy = ShopCatalog.industryGroups(including: "clinic")
            .first { $0.items.contains { $0.value == "vet" } }?.items ?? []
        XCTAssertEqual(medicalWithLegacy.map(\.value), ["vet", "clinic"],
                       "현재 값이 내려간 업종이면 그 분류에 끼워 넣는다")

        // 현재 값이 살아있는 업종이면 아무것도 덧붙지 않는다.
        let medicalWithLive = ShopCatalog.industryGroups(including: "hair")
            .first { $0.items.contains { $0.value == "vet" } }?.items ?? []
        XCTAssertEqual(medicalWithLive.map(\.value), ["vet"])
    }

    func testRetiredIndustriesHaveNoServicePreset() {
        // 내려간 업종엔 전용 프리셋이 없다. 다만 카탈로그가 비면 예약에서 서비스를 못 고르는
        // 막다른 길이 되므로 defaultServices는 공용 "기본 서비스" 1개로 폴백한다.
        XCTAssertEqual(ShopCatalog.defaultServices(for: retiredValues).map(\.name), ["기본 서비스"])
        XCTAssertTrue(ShopCatalog.categoryColors(for: retiredValues).isEmpty)
    }
}
