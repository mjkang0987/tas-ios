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
            // 이관 뒤 기존 담당자와 이름이 같은 새 담당자 — 쌍마다 하나씩(웹 GuestMigrationLayer '담당자 병합').
            .alert("\(session.labels.assignee) 병합", isPresented: assigneeMergeBinding, presenting: session.assigneeMergePairs.first) { _ in
                Button("따로 유지") { Task { await session.resolveAssigneeMerge(merge: false) } }
                // 웹처럼 병합이 기본
                Button("병합") { Task { await session.resolveAssigneeMerge(merge: true) } }.keyboardShortcut(.defaultAction)
            } message: { pair in
                // 업종 용어(선생님·룸 등)에 와/과·라면/이라면이 갈리지 않게 문구를 짰다
                Text("게스트 데이터에 기존과 이름이 같은 \(session.labels.assignee.josa(.iGa)) 있습니다. 둘이 같다면 병합을 선택해 예약을 합쳐주세요.\n\n\(pair.existingAssignee.name) + \(pair.newAssignee.name) (게스트)")
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
            // 이관·병합이 끝나면 새로 만들어 서버 데이터를 다시 받는다(웹 clearLocalAndReload)
            MainTabView().id(session.dataEpoch)
        }
    }

    private var migrationConfirmBinding: Binding<Bool> {
        Binding(get: { session.pendingMigration }, set: { if !$0 { session.pendingMigration = false } })
    }

    /// 병합 요청 중엔 내려 두고, 끝나면 다음 쌍을 띄운다. 닫기는 버튼 동작(resolveAssigneeMerge)이 맡는다.
    private var assigneeMergeBinding: Binding<Bool> {
        Binding(get: { !session.assigneeMergePairs.isEmpty && !session.isMergingAssignee }, set: { _ in })
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
        // 넓은 화면(펼친 iPhone Duo·iPad) = 왼쪽 사이드바, 좁은 화면 = 아래 탭바 — 웹 641px 이상 왼쪽 메뉴(Aside)와 같은 갈림.
        // 직접 그리지 않고 iOS 기본 사이드바를 쓴다(지시자 2026-10-26: iOS 에서 어긋나지 않는 선에서 웹처럼).
        .sidebarAdaptableTabs()
        // 예약 알림은 기본이 켜짐(30분 전)이라 처음 한 번 권한을 묻는다 — 안 물으면 조용히 안 울린다
        .task { await reminders.requestAuthorizationIfNeeded() }
        // 예약 알림을 눌러 들어오면 캘린더 탭으로 — 상세는 캘린더가 연다
        .onChange(of: reminders.pendingReservationId) { _, id in
            if id != nil { tab = .calendar }
        }
    }
}

private extension View {
    /// iOS 18 부터 — 17 은 지금처럼 탭바(iPad 는 위쪽 탭).
    @ViewBuilder func sidebarAdaptableTabs() -> some View {
        if #available(iOS 18.0, *) { tabViewStyle(.sidebarAdaptable) } else { self }
    }
}

#Preview {
    MainTabView()
        .environment(SessionStore())
        .environment(ReminderScheduler.shared)
}
