import Foundation

/// KST(Asia/Seoul) 고정 날짜 유틸 — 매장 기준 시간. 공용(캘린더·매출 등에서 재사용).
enum KST {
    static let timeZone = TimeZone(identifier: "Asia/Seoul")!

    /// 요일 라벨(월 시작) — 웹 `WEEKDAY_LABELS`. 담당자 스케줄·영업시간 배열의 인덱스 순서와 같다.
    /// 화면마다 복붙하지 말고 여기서 가져다 쓴다.
    static let weekdayLabels = ["월", "화", "수", "목", "금", "토", "일"]
    /// 달력 머리(일요일 시작) — 웹 캘린더·안드로이드와 같다. 근무시간·정기휴무 칸은 위 월요일 시작 배열(데이터 순서)을 쓴다.
    static let calendarWeekdayLabels = ["일", "월", "화", "수", "목", "금", "토"]

    /// 날짜의 요일 라벨. 칼럼 순서(index)가 아니라 **날짜**에서 낸다 —
    /// 3일 뷰는 기준일부터 시작해 index 와 요일이 어긋나기 때문이다.
    static func weekdayLabel(for date: Date) -> String {
        let weekday = calendar.component(.weekday, from: date)   // 1=일 … 7=토
        return weekdayLabels[(weekday + 5) % 7]                  // 월요일 시작 배열로
    }

    /// 일요일 시작 KST 캘린더 — 웹 캘린더(월·주 뷰)·안드로이드와 같은 주(일~토).
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.firstWeekday = 1
        return c
    }

    static let dayKey: DateFormatter = formatter("yyyy-MM-dd")     // "2026-07-23"
    static let monthKey: DateFormatter = formatter("yyyy-MM")      // "2026-07"
    static let monthLabel: DateFormatter = formatter("yyyy.MM")    // "2026.07"

    /// 이력 시각 ISO8601 → "M.d HH:mm"(KST). 초 소수점 유무 모두 허용 — 예약 변경 이력·적립금 이력이 같이 쓴다.
    static func timestampLabel(_ iso: String) -> String {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = withFrac.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        return timestamp.string(from: date)
    }
    private static let timestamp: DateFormatter = formatter("M.d HH:mm")

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = format
        return f
    }
}
