import XCTest
@testable import TAS

/// 한글 초성 검색 — 웹 `chosung.ts` 이식 검증.
final class ChosungTests: XCTestCase {

    // MARK: - extract (getChosung)

    func testExtractConvertsSyllablesToChosung() {
        XCTAssertEqual(Chosung.extract("김민수"), "ㄱㅁㅅ")
    }

    func testExtractDistinguishesDoubleConsonants() {
        XCTAssertEqual(Chosung.extract("까치"), "ㄲㅊ")
    }

    func testExtractPassesThroughNonHangul() {
        XCTAssertEqual(Chosung.extract("Kim3"), "Kim3")
    }

    func testExtractOnlyConvertsHangulInMixedText() {
        XCTAssertEqual(Chosung.extract("김민수2호점"), "ㄱㅁㅅ2ㅎㅈ")
    }

    // MARK: - isQuery (isChosungQuery)

    func testIsQueryTrueForChosungOnly() {
        XCTAssertTrue(Chosung.isQuery("ㄱㅁㅅ"))
        XCTAssertTrue(Chosung.isQuery("ㅎ"))
    }

    func testIsQueryFalseForMixedOrEmpty() {
        XCTAssertFalse(Chosung.isQuery("김ㅁㅅ"))
        XCTAssertFalse(Chosung.isQuery(""))
        XCTAssertFalse(Chosung.isQuery("010"))
    }

    // MARK: - matches (matchesChosung)

    func testMatchesTrueWhenChosungQueryIsSubstringOfTargetChosung() {
        XCTAssertTrue(Chosung.matches("김민수", "ㄱㅁㅅ"))
        XCTAssertTrue(Chosung.matches("김민수", "ㄱㅁ"))
        XCTAssertTrue(Chosung.matches("이김민수", "ㄱㅁㅅ"))
    }

    func testMatchesFalseWhenOrderOrCompositionDiffers() {
        XCTAssertFalse(Chosung.matches("김민수", "ㅁㄱㅅ"))
        XCTAssertFalse(Chosung.matches("김민수", "ㄱㅈㅅ"))
    }

    func testMatchesFalseWhenQueryIsNotChosungOnly() {
        XCTAssertFalse(Chosung.matches("김민수", "김민수"))
        XCTAssertFalse(Chosung.matches("김민수", ""))
    }
}
