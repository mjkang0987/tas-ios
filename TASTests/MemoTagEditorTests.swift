import XCTest
@testable import TAS

/// 메모 태그 더하기 규칙 — 웹 addTag(앞뒤 공백 제거 · 빈 글자 무시 · 같은 글자 거부 · 끝에 붙임).
final class MemoTagEditorTests: XCTestCase {
    private let tags = [CustomerMemoTag(text: "두피 민감", color: "#EA4335")]

    func testAddsTrimmedTagAtEnd() {
        let result = MemoTagEditor.adding("  VIP ", color: "#34A853", to: tags)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.tags.map(\.text), ["두피 민감", "VIP"])
        XCTAssertEqual(result.tags.last?.color, "#34A853")
    }

    func testBlankIsIgnoredWithoutError() {
        let result = MemoTagEditor.adding("   ", color: "#34A853", to: tags)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.tags, tags)
    }

    func testDuplicateIsRejected() {
        let result = MemoTagEditor.adding("두피 민감 ", color: "#34A853", to: tags)
        XCTAssertEqual(result.error, "같은 메모 태그가 이미 있습니다.")
        XCTAssertEqual(result.tags, tags)
    }
}
