import XCTest
@testable import TAS

/// 공지 '노출' 한도(`StoreNotice.canShow`) — 서버 `/api/notices` 409 `visible_limit` 규칙 이식본.
/// 한도는 숨김 → 노출 전환 때만 본다. 이미 노출 중인 공지는 (한도 도입 전 초과분이어도) 막지 않는다.
final class NoticeTests: XCTestCase {

    func testNewNoticeCanShowBelowLimit() {
        XCTAssertTrue(StoreNotice.canShow(wasVisible: false, otherVisibleCount: StoreNotice.maxVisible - 1))
    }

    func testNewNoticeBlockedAtLimit() {
        XCTAssertFalse(StoreNotice.canShow(wasVisible: false, otherVisibleCount: StoreNotice.maxVisible))
    }

    func testAlreadyVisibleNoticeIsNeverBlocked() {
        // 레거시: 한도 도입 전부터 4개 이상 노출 중인 매장
        XCTAssertTrue(StoreNotice.canShow(wasVisible: true, otherVisibleCount: StoreNotice.maxVisible + 1))
    }

    // 웹 MAX_VISIBLE_NOTICES 와 같은 값이어야 서버 409 와 어긋나지 않는다.
    func testMaxVisibleMatchesWeb() {
        XCTAssertEqual(StoreNotice.maxVisible, 3)
    }
}
