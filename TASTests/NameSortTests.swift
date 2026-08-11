import XCTest
@testable import TAS

/// 이름 정렬 규칙 — 웹 `compareCustomerName`(tas #175)·`compareAssigneeName` 이식본 검증.
///
/// Swift 기본 `<`는 코드포인트 비교라 대문자가 소문자보다 앞서고 '고객10'이 '고객9'보다 앞선다.
/// 여기 테스트는 그 두 가지가 웹과 같은 결과로 뒤집혔는지 본다.
final class NameSortTests: XCTestCase {

    private func customer(_ id: Int, _ name: String) -> Customer {
        Customer(id: id, name: name, tel: "01000000000")
    }

    // MARK: - 고객 (Intl.Collator('ko', {numeric: true}))

    func testCustomerNamesSortInKoreanAlphabeticalOrder() {
        let list = [customer(1, "하윤"), customer(2, "가온"), customer(3, "나린")]
        XCTAssertEqual(list.sortedByName().map(\.name), ["가온", "나린", "하윤"])
    }

    func testCaseDoesNotOutrankAlphabeticalOrder() {
        // 코드포인트 비교면 'Zoe'(0x5A) < 'apple'(0x61)이라 Z가 먼저 나온다.
        let list = [customer(1, "Zoe"), customer(2, "apple")]
        XCTAssertEqual(list.sortedByName().map(\.name), ["apple", "Zoe"])
    }

    func testTrailingNumbersCompareNumerically() {
        // 코드포인트 비교면 '고객10' < '고객9'('1' < '9').
        let list = [customer(1, "고객10"), customer(2, "고객9"), customer(3, "고객1")]
        XCTAssertEqual(list.sortedByName().map(\.name), ["고객1", "고객9", "고객10"])
    }

    func testSameNameIsBrokenByIdForStableOrder() {
        let list = [customer(7, "김민수"), customer(3, "김민수"), customer(5, "김민수")]
        XCTAssertEqual(list.sortedByName().map(\.id), [3, 5, 7])
    }

    func testSortedByNameDoesNotMutateSource() {
        let list = [customer(1, "하윤"), customer(2, "가온")]
        _ = list.sortedByName()
        XCTAssertEqual(list.map(\.name), ["하윤", "가온"], "원본은 그대로여야 한다")
    }

    // MARK: - 담당자 (영문 → 한글 → 기타)

    func testAssigneeLatinNamesComeBeforeHangul() {
        XCTAssertEqual(NameSort.assigneeName("Anna", "가온"), .orderedAscending)
        XCTAssertEqual(NameSort.assigneeName("가온", "Anna"), .orderedDescending)
    }

    func testAssigneeHangulComesBeforeOtherScripts() {
        XCTAssertEqual(NameSort.assigneeName("가온", "3번실"), .orderedAscending)
        XCTAssertEqual(NameSort.assigneeName("ㄱ실장", "3번실"), .orderedAscending, "자모도 한글 그룹")
    }

    func testAssigneeNamesInSameGroupSortAlphabetically() {
        XCTAssertEqual(NameSort.assigneeName("가온", "하윤"), .orderedAscending)
        XCTAssertEqual(NameSort.assigneeName("Zoe", "apple"), .orderedDescending)
    }

    func testAssigneeEmptyNameFallsToOtherGroup() {
        XCTAssertEqual(NameSort.assigneeName("", "가온"), .orderedDescending)
    }
}
