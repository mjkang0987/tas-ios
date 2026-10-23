import SwiftUI

/// Top-level router: login gate → main tabs.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(GuestStore.self) private var guest

    var body: some View {
        content
            // 글자를 따로 정하지 않은 곳(목록 행·입력칸 등)도 웹 본문 크기(14)로 — 공용 단계는 `Theme.swift`
            .font(.tasBody)
            // 한국어 전용 앱 — 기기 언어가 영어여도 날짜 고르기·요일이 웹처럼 한국어('2026년 10월 24일')로 나오게
            .environment(\.locale, Locale(identifier: "ko_KR"))
            // 로그인 직후 게스트 데이터가 있고 계정에 이미 매장이 있으면 이관 확인.
            .alert("게스트 데이터 이관", isPresented: migrationConfirmBinding) {
                Button("취소", role: .cancel) { session.cancelMigration() }
                Button("이관") { Task { await session.confirmMigration() } }
            } message: {
                Text("이미 설정된 매장이 있습니다. 이 기기의 게스트 데이터를 계정으로 이관할까요?")
            }
            .alert("알림", isPresented: migrationMessageBinding) {
                Button("확인", role: .cancel) { session.migrationMessage = nil }
            } message: {
                Text(session.migrationMessage ?? "")
            }
    }

    @ViewBuilder private var content: some View {
        switch session.state {
        case .loading:
            ProgressView("불러오는 중…")
        case .signedOut:
            LoginView()
        case .guest:
            // 게스트 진입 순서: 약관 동의 → 온보딩 → 메인.
            if !guest.hasConsented {
                GuestConsentView()
            } else if guest.isOnboarded {
                MainTabView()
            } else {
                GuestOnboardingView()
            }
        case .signedIn:
            MainTabView()
        }
    }

    private var migrationConfirmBinding: Binding<Bool> {
        Binding(get: { session.pendingMigration }, set: { if !$0 { session.pendingMigration = false } })
    }

    private var migrationMessageBinding: Binding<Bool> {
        Binding(get: { session.migrationMessage != nil }, set: { if !$0 { session.migrationMessage = nil } })
    }
}

/// Primary navigation, mirroring the web app's top-level pages
/// (캘린더 `/`, 주소록 `/address`, 매출 `/settings/revenue`, 설정 `/menu`).
/// 웹 `MobileTabBar`와 항목·순서를 맞춘다 — 탭바에 올린 화면은 설정 목록에서 뺀다
/// (웹 `pages/menu.tsx`의 `HIDDEN_IN_MENU`와 같은 규칙).
struct MainTabView: View {
    private enum Tab { case calendar, customers, revenue, settings }
    @State private var tab: Tab = .calendar
    @Environment(ReminderScheduler.self) private var reminders

    var body: some View {
        TabView(selection: $tab) {
            CalendarView()
                .tabItem { Label("캘린더", systemImage: "calendar") }
                .tag(Tab.calendar)

            CustomersView()
                .tabItem { Label("고객", systemImage: "person.2") }
                .tag(Tab.customers)

            RevenueView()
                .tabItem { Label("매출", systemImage: "wonsign") }
                .tag(Tab.revenue)

            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        // 예약 알림은 기본이 켜짐(30분 전)이라 처음 한 번 권한을 묻는다 — 안 물으면 조용히 안 울린다
        .task { await reminders.requestAuthorizationIfNeeded() }
        // 예약 알림을 눌러 들어오면 캘린더 탭으로 — 상세는 캘린더가 연다
        .onChange(of: reminders.pendingReservationId) { _, id in
            if id != nil { tab = .calendar }
        }
    }
}

#Preview {
    MainTabView()
        .environment(SessionStore())
        .environment(ReminderScheduler.shared)
}
