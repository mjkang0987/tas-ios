import Foundation

/// 예약 알림(기기 알림) — 웹에 없는 앱 기능(지시자 2026-10-22). 무엇을 언제 알릴지만 정한다(등록은 `ReminderScheduler`).
/// 안드로이드 `domain/Reminder.kt` 와 같은 규칙이다.
enum ReservationReminder {
    /// 설정에서 고르는 알림 시점(분). 0 = 끔.
    static let leadOptions = [0, 10, 30, 60]
    static let defaultLead = 30

    /// 시점 표시 — "끔" · "10분 전" · "1시간 전".
    static func leadLabel(_ minutes: Int) -> String {
        if minutes <= 0 { return "끔" }
        if minutes % 60 == 0 { return "\(minutes / 60)시간 전" }
        return "\(minutes)분 전"
    }

    /// 매장 설정의 지각 알림 기준(분). 0 = 끔.
    static let lateOptions = [0, 5, 10, 15, 20, 30]
    static let defaultLate = 15

    static func lateLabel(_ minutes: Int) -> String { minutes <= 0 ? "끔" : "\(minutes)분 후" }

    /// 알림 종류 — 시작 전(설정의 시점) · 지각(매장 설정의 기준, 시작 뒤).
    enum Kind: String { case before, late }

    struct Item: Equatable {
        var reservationId: Int
        var fireDate: Date
        var title: String
        var body: String
        var kind: Kind = .before
    }

    /// 알릴 예약 — 진행 중(상태 없음·active)만. 취소·노쇼·완료는 끝났고, 확정대기는 아직 오는지 모른다.
    private static func isRemindable(_ r: Reservation) -> Bool { r.status == nil || r.status == .active }

    private static let startFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = KST.timeZone // 예약 날짜·시각은 매장(KST) 기준
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static func summary(_ r: Reservation, _ customerNames: [Int: String]) -> String {
        // 못 찾으면 캘린더·상세와 같은 "고객 #id"
        let name = customerNames[r.customerId].flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? "고객 #\(r.customerId)"
        let what = r.service.isEmpty ? "" : " · \(r.service)"
        return "\(r.startTime) \(name)\(what)"
    }

    /// 한 예약의 시작 전 알림 — 시각을 못 읽거나 알릴 예약이 아니면 nil.
    static func item(for r: Reservation, customerNames: [Int: String], leadMinutes: Int) -> Item? {
        guard leadMinutes > 0, isRemindable(r),
              let start = startFormatter.date(from: "\(r.date) \(r.startTime)") else { return nil }
        return Item(
            reservationId: r.id,
            fireDate: start.addingTimeInterval(-Double(leadMinutes) * 60),
            title: "예약 \(leadLabel(leadMinutes))",
            body: summary(r, customerNames)
        )
    }

    /// 한 예약의 지각 알림 — 시작 뒤 [lateMinutes] 가 지나도 진행 중이면. 결제까지 끝났으면 손님은 온 것이라 알리지 않는다.
    static func lateItem(for r: Reservation, customerNames: [Int: String], lateMinutes: Int) -> Item? {
        guard lateMinutes > 0, isRemindable(r), !r.hasCompletedPayment,
              let start = startFormatter.date(from: "\(r.date) \(r.startTime)") else { return nil }
        return Item(
            reservationId: r.id,
            fireDate: start.addingTimeInterval(Double(lateMinutes) * 60),
            title: "손님이 아직 안 오셨나요?",
            body: "\(summary(r, customerNames)) — 예약 \(lateMinutes)분 지남",
            kind: .late
        )
    }

    /// 등록할 알림 — 지금 이후에 울릴 것, [horizonDays] 안, 이른 순 [limit] 건까지.
    /// iOS 는 앱당 대기 알림이 64개라 가까운 것만 잡고, 캘린더를 열 때마다 다시 채운다.
    static func upcoming(
        _ reservations: [Reservation],
        customerNames: [Int: String],
        leadMinutes: Int,
        now: Date,
        horizonDays: Int = 30,
        limit: Int = 60,
        lateMinutes: Int = 0
    ) -> [Item] {
        guard leadMinutes > 0 || lateMinutes > 0 else { return [] }
        let until = now.addingTimeInterval(Double(horizonDays) * 24 * 60 * 60)
        let before: [Item] = reservations.compactMap { item(for: $0, customerNames: customerNames, leadMinutes: leadMinutes) }
        let late: [Item] = reservations.compactMap { lateItem(for: $0, customerNames: customerNames, lateMinutes: lateMinutes) }
        let items = before + late
        let inWindow = items.filter { $0.fireDate > now && $0.fireDate <= until }
        return Array(inWindow.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }
}
