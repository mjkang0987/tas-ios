import XCTest
@testable import TAS

/// 검색 매치 하이라이트 구간 — 웹 `search-highlight.ts` 이식 검증.
final class SearchHighlightTests: XCTestCase {

    private func matched(_ text: String, _ range: Range<String.Index>?) -> String? {
        guard let range else { return nil }
        return String(text[range])
    }

    func testFindsPlainSubstringMatch() {
        let text = "김민수"
        let range = SearchHighlight.matchRange(in: text, query: "민수")
        XCTAssertEqual(matched(text, range), "민수")
    }

    func testCaseSensitiveByDefault() {
        XCTAssertNil(SearchHighlight.matchRange(in: "Kim", query: "kim"))
    }

    func testCaseInsensitiveOptionIgnoresCase() {
        let text = "Kim"
        let range = SearchHighlight.matchRange(in: text, query: "kim", caseInsensitive: true)
        XCTAssertEqual(matched(text, range), "Kim")
    }

    func testFallsBackToChosungMatchWhenNoPlainMatch() {
        let name1 = "김민수"
        XCTAssertEqual(matched(name1, SearchHighlight.matchRange(in: name1, query: "ㄱㅁㅅ")), "김민수")

        let name2 = "이김민수"
        XCTAssertEqual(matched(name2, SearchHighlight.matchRange(in: name2, query: "ㄱㅁㅅ")), "김민수")
    }

    func testPlainMatchTakesPriorityOverChosungMatch() {
        // '가'는 그 자체로 문자열에 있으므로 초성 규칙과 무관하게 일반 부분일치로 먼저 잡힌다.
        let text = "가나다"
        let range = SearchHighlight.matchRange(in: text, query: "가")
        XCTAssertEqual(matched(text, range), "가")
    }

    func testReturnsNilWhenNothingMatches() {
        XCTAssertNil(SearchHighlight.matchRange(in: "김민수", query: "박서준"))
        XCTAssertNil(SearchHighlight.matchRange(in: "김민수", query: "ㅂㅅㅈ"))
    }

    func testReturnsNilForEmptyQuery() {
        XCTAssertNil(SearchHighlight.matchRange(in: "김민수", query: ""))
    }
}
