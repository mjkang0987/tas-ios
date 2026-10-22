import SwiftUI
import GoogleSignIn
import UserNotifications

@main
struct TASApp: App {
    @State private var session = SessionStore()

    init() {
        // 예약 알림 — 앞에 있을 때 배너·누르면 상세. 앱이 꺼진 채 알림을 눌러 켜질 때도 받도록 시작하자마자 단다.
        UNUserNotificationCenter.current().delegate = ReminderScheduler.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(GuestStore.shared)
                .environment(ReminderScheduler.shared)
                .task { await session.bootstrap() }
                // 네이티브 Google 로그인 OAuth 콜백 URL 처리(리버스 클라이언트 ID 스킴).
                // Google URL이 아니면 handle이 false를 반환해 무해하다.
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
