import Foundation

/// KST(Asia/Seoul) 고정 날짜 유틸 — 매장 기준 시간. 공용(캘린더·매출 등에서 재사용).
enum KST {
    static let timeZone = TimeZone(identifier: "Asia/Seoul")!

    /// 월요일 시작(웹 WEEKDAY_LABELS) KST 캘린더.
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.firstWeekday = 2
        return c
    }

    static let dayKey: DateFormatter = formatter("yyyy-MM-dd")     // "2026-07-23"
    static let monthKey: DateFormatter = formatter("yyyy-MM")      // "2026-07"
    static let monthLabel: DateFormatter = formatter("yyyy.MM")    // "2026.07"

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = format
        return f
    }
}
