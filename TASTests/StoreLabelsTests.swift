import XCTest
@testable import TAS

/// 업종별 화면 용어(웹 getStoreLabels)와 조사 붙이기.
final class StoreLabelsTests: XCTestCase {
    func testLabelsFollowFirstKnownIndustry() {
        XCTAssertEqual(StoreLabels.of(shopType: "hair"), .default)
        XCTAssertEqual(StoreLabels.of(shopType: "restaurant").assignee, "테이블")
        XCTAssertEqual(StoreLabels.of(shopType: "restaurant").service, "메뉴")
        // 콤마로 이은 여러 업종 — 모르는 값은 건너뛰고 첫 유효 업종
        XCTAssertEqual(StoreLabels.of(shopType: "unknown, yoga, cafe").service, "수업")
        XCTAssertEqual(StoreLabels.of(shopType: nil), .default)
        XCTAssertEqual(StoreLabels.of(shopType: "nope"), .default)
    }

    func testJosaFollowsFinalConsonant() {
        XCTAssertEqual("서비스".josa(.iGa), "서비스가")
        XCTAssertEqual("수업".josa(.iGa), "수업이")
        XCTAssertEqual("메뉴".josa(.eulReul), "메뉴를")
        XCTAssertEqual("테이블".josa(.eulReul), "테이블을")
        XCTAssertEqual("담당자".josa(.eunNeun), "담당자는")
        XCTAssertEqual("상담".josa(.eunNeun), "상담은")
        XCTAssertEqual("룸".josa(.euroRo), "룸으로")
        XCTAssertEqual("테이블".josa(.euroRo), "테이블로")   // ㄹ 받침은 '로'
        XCTAssertEqual("PT".josa(.iGa), "PT가")             // 한글이 아니면 받침 없음으로
    }
}
