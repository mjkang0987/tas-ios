import XCTest
@testable import TAS

/// 온라인 예약 설정 — 웹에서 이식한 검증 규칙과 디코딩.
/// 슬러그·연락처 형식은 서버가 같은 규칙으로 400을 주므로 앱에서 먼저 걸러야 한다.
final class BookingSettingsTests: XCTestCase {

    func testSlugValidation() {
        // 소문자 영숫자·하이픈 3~32자, 하이픈으로 시작·끝 불가.
        XCTAssertTrue(BookingSettings.isValidSlug("mystore"))
        XCTAssertTrue(BookingSettings.isValidSlug("my-store-1"))
        XCTAssertTrue(BookingSettings.isValidSlug("abc"))                       // 최소 3자
        XCTAssertTrue(BookingSettings.isValidSlug(String(repeating: "a", count: 32)))

        XCTAssertFalse(BookingSettings.isValidSlug("ab"))                       // 2자
        XCTAssertFalse(BookingSettings.isValidSlug(String(repeating: "a", count: 33)))
        XCTAssertFalse(BookingSettings.isValidSlug("-store"))                   // 하이픈 시작
        XCTAssertFalse(BookingSettings.isValidSlug("store-"))                   // 하이픈 끝
        XCTAssertFalse(BookingSettings.isValidSlug("MyStore"))                  // 대문자
        XCTAssertFalse(BookingSettings.isValidSlug("my store"))                 // 공백
        XCTAssertFalse(BookingSettings.isValidSlug("가게"))
    }

    func testContactTelValidation() {
        // 서버 store.ts와 동일: 숫자·+·-·()·공백 8~20자. 휴대폰 형식으로 재조립하지 않는다.
        XCTAssertTrue(BookingSettings.isValidContactTel("02-1234-5678"))
        XCTAssertTrue(BookingSettings.isValidContactTel("1588-0000"))
        XCTAssertTrue(BookingSettings.isValidContactTel("010-1234-5678"))
        XCTAssertTrue(BookingSettings.isValidContactTel("+82 2 1234 5678"))

        XCTAssertFalse(BookingSettings.isValidContactTel("010"))                // 8자 미만
        XCTAssertFalse(BookingSettings.isValidContactTel("문의는 카톡으로"))
        XCTAssertFalse(BookingSettings.isValidContactTel(String(repeating: "1", count: 21)))
    }

    func testWithDefaultTextsFillsOnlyMissing() {
        var settings = BookingSettings()
        settings.noticeText = "우리 매장 안내문"
        let filled = settings.withDefaultTexts()

        XCTAssertEqual(filled.noticeText, "우리 매장 안내문")                      // 입력값 보존
        XCTAssertEqual(filled.doneText, BookingSettings.DefaultTexts.done)      // 빈 칸만 기본 문구
        XCTAssertEqual(filled.confirmText, BookingSettings.DefaultTexts.confirm)
        XCTAssertEqual(filled.cancelText, BookingSettings.DefaultTexts.cancel)
    }

    func testStoreDecodesBookingSettings() throws {
        let json = Data(#"""
        {"storeName":"테스트샵","useOnlineBooking":true,"bookingSlug":"mystore",
         "bookingSettings":{"slotIntervalMin":15,"minLeadMinutes":0,"maxAdvanceDays":14,
         "allowAssigneeChoice":false,"contactTel":"02-1234-5678","noticeText":null,
         "bookableServiceNames":["커트","펌"]}}
        """#.utf8)
        let store = try JSONDecoder().decode(Store.self, from: json)
        let booking = try XCTUnwrap(store.bookingSettings)

        XCTAssertEqual(store.bookingSlug, "mystore")
        XCTAssertEqual(booking.slotIntervalMin, 15)
        XCTAssertEqual(booking.minLeadMinutes, 0)
        XCTAssertEqual(booking.maxAdvanceDays, 14)
        XCTAssertFalse(booking.allowAssigneeChoice)
        XCTAssertEqual(booking.contactTel, "02-1234-5678")
        XCTAssertNil(booking.noticeText)
        XCTAssertEqual(booking.bookableServiceNames, ["커트", "펌"])
    }

    func testBookingSettingsFallsBackToServerDefaults() throws {
        // 마이그레이션 전/부분 응답도 허용 — 누락 필드는 서버 기본값.
        let booking = try JSONDecoder().decode(BookingSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(booking.slotIntervalMin, 30)
        XCTAssertEqual(booking.minLeadMinutes, 60)
        XCTAssertEqual(booking.maxAdvanceDays, 30)
        XCTAssertTrue(booking.allowAssigneeChoice)
        XCTAssertNil(booking.contactTel)
        XCTAssertNil(booking.bookableServiceNames)          // nil = 전체 노출

        // bookingSettings 자체가 없는 응답도 무해해야 한다(온라인예약 미사용 매장).
        let store = try JSONDecoder().decode(Store.self, from: Data(#"{"storeName":"샵"}"#.utf8))
        XCTAssertNil(store.bookingSettings)
    }
}
