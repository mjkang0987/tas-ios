import Foundation

/// 알림 종의 '곧 시작하는 예약' — 웹 `features/notifications/upcoming.ts` 이식.
/// 날짜·시각은 매장(KST) 기준(캘린더와 같다).
enum UpcomingReservations {
    /// '곧 시작'으로 보여 주는 범위(분).
    static let windowMinutes = 60
    /// 곧 시작 칸에 보이는 최대 건수(웹 `UPCOMING_MAX_SHOWN`).
    static let maxShown = 3

    struct Item: Equatable {
        var reservation: Reservation
        /// 지금부터 시작까지 남은 분(0 = 지금 시작)
        var minutesUntil: Int
    }

    /// 진행 중인 예약만 — 취소·노쇼·완료는 끝났고, 확정대기는 아직 오는지 모른다(예약 알림과 같은 규칙).
    private static func isCandidate(_ r: Reservation) -> Bool { r.status == nil || r.status == .active }

    private static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    /// 오늘 예약 중 지금부터 [window] 분 안에 시작하는 것(이른 순)과, 그 뒤 오늘의 다음 예약 하나.
    static func compute(_ reservations: [Reservation], now: Date, window: Int = windowMinutes) -> (soon: [Item], next: Item?) {
        let today = KST.dayKey.string(from: now)
        let clock = KST.calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
        var later: [Item] = []
        for r in reservations where r.date == today && isCandidate(r) {
            if let start = minutes(r.startTime), start >= nowMinutes {
                later.append(Item(reservation: r, minutesUntil: start - nowMinutes))
            }
        }
        later.sort { $0.minutesUntil != $1.minutesUntil ? $0.minutesUntil < $1.minutesUntil : $0.reservation.id < $1.reservation.id }
        return (later.filter { $0.minutesUntil <= window }, later.first { $0.minutesUntil > window })
    }

    /// "지금" · "20분 후" · "1시간 후" · "2시간 30분 후".
    static func untilLabel(_ minutes: Int) -> String {
        if minutes <= 0 { return "지금" }
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)분 후" }
        return m == 0 ? "\(h)시간 후" : "\(h)시간 \(m)분 후"
    }

    /// 종 표시 — 처리할 것(대기 중 예약 요청)은 빨간 숫자, 곧 시작하는 예약만 있으면 보라 점.
    /// 곧 시작은 숫자에 넣지 않는다 — 영업 중엔 늘 있어 처리할 일이 묻힌다.
    static func bellIndicator(todo: Int, soon: Int) -> (count: Int, dot: Bool) {
        (todo, todo == 0 && soon > 0)
    }
}
