import XCTest
@testable import TAS

/// 고객 검색 필터 — 이름/전화/초성/메모 매칭과 매치된 메모 태그 산출(`filterResult`) 검증.
/// state를 직접 주입해 네트워크 없이 검증한다(`RevenueViewModelTests`와 같은 패턴).
@MainActor
final class CustomersViewModelTests: XCTestCase {

    private func customer(_ id: Int, _ name: String, tel: String = "01000000000", memoTags: [CustomerMemoTag]? = nil) -> Customer {
        Customer(id: id, name: name, tel: tel, memoTags: memoTags)
    }

    private func makeVM(_ customers: [Customer]) -> CustomersViewModel {
        let m = CustomersViewModel()
        m.state = .loaded(CustomersViewModel.Data(
            customers: customers,
            reservationsByCustomer: [:],
            assigneesById: [:],
            serviceColorMap: [:],
            statsByCustomer: [:],
            today: "2026-01-01"
        ))
        return m
    }

    func testEmptyQueryReturnsAllCustomersSortedByName() {
        let m = makeVM([customer(1, "하윤"), customer(2, "가온")])
        m.searchText = ""
        XCTAssertEqual(m.filterResult.customers.map(\.name), ["가온", "하윤"])
        XCTAssertTrue(m.filterResult.matchedMemoTags.isEmpty)
    }

    func testNameSubstringMatch() {
        let m = makeVM([customer(1, "김민수"), customer(2, "박서준")])
        m.searchText = "민수"
        XCTAssertEqual(m.filterResult.customers.map(\.id), [1])
    }

    func testChosungMatch() {
        let m = makeVM([customer(1, "김민수"), customer(2, "김진수")])
        m.searchText = "ㄱㅁㅅ"
        XCTAssertEqual(m.filterResult.customers.map(\.id), [1], "김진수는 초성이 ㄱㅈㅅ라 걸리지 않는다")
    }

    func testPhoneDigitsMatch() {
        let m = makeVM([customer(1, "김민수", tel: "01011112222"), customer(2, "박서준", tel: "01099998888")])
        m.searchText = "1111"
        XCTAssertEqual(m.filterResult.customers.map(\.id), [1])
    }

    func testMemoTagMatchIncludesCustomerAndReturnsMatchedTags() {
        let vip = CustomerMemoTag(text: "VIP", color: "#4285F4")
        let m = makeVM([
            customer(1, "김민수", memoTags: [vip]),
            customer(2, "박서준", memoTags: [CustomerMemoTag(text: "알레르기", color: "#EA4335")]),
        ])
        m.searchText = "VIP"

        let result = m.filterResult
        XCTAssertEqual(result.customers.map(\.id), [1])
        XCTAssertEqual(result.matchedMemoTags[1]?.map(\.text), ["VIP"])
        XCTAssertNil(result.matchedMemoTags[2], "매치되지 않은 고객은 키 자체가 없어야 한다")
    }

    func testMatchedMemoTagsEmptyWhenCustomerMatchedByNameNotMemo() {
        // 이름으로 걸린 결과는 메모가 매치 근거가 아니므로 matchedMemoTags에 없어야 한다.
        let m = makeVM([customer(1, "김민수", memoTags: [CustomerMemoTag(text: "VIP", color: "#4285F4")])])
        m.searchText = "김민수"

        let result = m.filterResult
        XCTAssertEqual(result.customers.map(\.id), [1])
        XCTAssertNil(result.matchedMemoTags[1])
    }

    func testWhitespaceOnlyQueryBehavesAsEmpty() {
        let m = makeVM([customer(1, "가온")])
        m.searchText = "   "
        XCTAssertEqual(m.filterResult.customers.map(\.id), [1])
    }

    func testMemoMatchingIsNotChosungAware() {
        // 메모 태그 매칭은 일반 부분일치만 본다(웹 address.tsx와 동일 규칙) — 이름과 달리 초성
        // 질의로는 메모가 걸리지 않아야 한다. "김치"의 초성은 "ㄱㅊ"이지만 매칭 대상이 아니다.
        let m = makeVM([customer(1, "박서준", memoTags: [CustomerMemoTag(text: "김치", color: "#4285F4")])])
        m.searchText = "ㄱㅊ"
        XCTAssertTrue(m.filterResult.customers.isEmpty, "메모는 초성 대상이 아니므로 결과가 없어야 한다")
    }

    func testTrimmedSearchQueryMatchesFilterTrimRule() {
        // 필터(filterResult)와 화면(하이라이트 등)이 같은 트림 규칙을 봐야 한다 — 각자 다시
        // 트림하면 규칙이 갈릴 때 필터엔 걸리는데 하이라이트만 안 뜨는 어긋남이 생긴다.
        let m = CustomersViewModel()
        m.searchText = "  김민수  "
        XCTAssertEqual(m.trimmedSearchQuery, "김민수")
    }
}
