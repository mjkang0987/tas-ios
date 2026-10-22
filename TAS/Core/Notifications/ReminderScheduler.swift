import Foundation
import Observation
import UserNotifications

/// 예약 알림 등록 — 알릴 예약(`ReservationReminder`)마다 로컬 알림을 걸고, 빠진 것은 지운다.
/// 로컬 알림은 OS 가 정한 시각에 정확히 울린다(안드로이드처럼 따로 정확한 알람 권한이 없다).
/// 알림을 누르면 `pendingReservationId` 에 담아 캘린더가 그 예약 상세를 연다.
@MainActor
@Observable
final class ReminderScheduler: NSObject {
    static let shared = ReminderScheduler()

    private static let idPrefix = "reservation-reminder-"
    private static let leadKey = "reminderLeadMinutes"
    nonisolated static let reservationIdKey = "reservationId"

    /// 알림을 눌러 열 예약 — 캘린더가 상세를 연 뒤 비운다.
    var pendingReservationId: Int?

    /// 설정의 알림 시점(분, 0 = 끔). 기기 설정이라 게스트 스냅샷·서버에는 넣지 않는다. 바꿀 땐 `setLeadMinutes`.
    private(set) var leadMinutes: Int = UserDefaults.standard.object(forKey: "reminderLeadMinutes") as? Int ?? ReservationReminder.defaultLead

    func setLeadMinutes(_ minutes: Int) async {
        leadMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: Self.leadKey)
        await resync()
    }

    // 설정을 바꿨을 때 다시 맞추려고 마지막으로 받은 예약을 들고 있는다(캘린더가 불러올 때마다 갱신).
    private var lastReservations: [Reservation] = []
    private var lastNames: [Int: String] = [:]

    private let center = UNUserNotificationCenter.current()

    /// 켜져 있는데 아직 묻지 않았으면 권한을 묻는다. 거절 상태면 false.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        guard leadMinutes > 0 else { return true }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    /// 지금 예약에 맞춰 알림을 다시 건다. 캘린더가 예약을 불러올 때마다(추가·변경·취소 뒤 reload 포함) 부른다.
    func sync(reservations: [Reservation], customerNames: [Int: String]) async {
        lastReservations = reservations
        lastNames = customerNames
        await resync()
    }

    private func resync() async {
        let items = ReservationReminder.upcoming(lastReservations, customerNames: lastNames, leadMinutes: leadMinutes, now: Date())
        let keep = Set(items.map { Self.idPrefix + String($0.reservationId) })
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { !keep.contains($0) })
        for item in items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.userInfo = [Self.reservationIdKey: item.reservationId]
            var components = KST.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            components.timeZone = KST.timeZone // 기기 시간대와 달라도 매장 시각에 울린다
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            // 같은 식별자는 덮어쓴다 — 시각이 바뀐 예약도 새 시각으로 바뀐다
            try? await center.add(UNNotificationRequest(identifier: Self.idPrefix + String(item.reservationId), content: content, trigger: trigger))
        }
    }
}

extension ReminderScheduler: UNUserNotificationCenterDelegate {
    /// 앱이 앞에 있을 때도 배너로 보인다(기본은 안 보임).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// 알림을 누르면 그 예약 상세로.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let id = response.notification.request.content.userInfo[Self.reservationIdKey] as? Int else { return }
        await MainActor.run { self.pendingReservationId = id }
    }
}
