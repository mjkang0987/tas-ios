import SwiftUI

/// 설정 — 매장 정보 및 로그아웃. 웹의 `/settings/*` 허브에 대응하는 스켈레톤.
struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ReminderScheduler.self) private var reminders
    @State private var notificationsDenied = false
    @State private var showStoreEdit = false
    @State private var showHoursEdit = false
    @State private var showBookingSettings = false
    @State private var toast: Toast?

    /// 쿠폰·회원권·온라인예약은 서버(발급/차감 API·공개 예약 페이지)가 있어야 동작한다.
    /// 게스트에겐 매장 정보 편집에서 토글도 감추므로 설정 목록에서도 함께 감춘다.
    private var serverFeaturesAvailable: Bool { !session.isGuest }

    /// 온라인예약을 켰지만 공개 주소(슬러그)나 매장 연락처가 비어 있는 상태.
    /// 게스트는 설정 자체가 로그인 전용이라 판정에서 제외한다.
    private var bookingNeedsSetup: Bool {
        guard !session.isGuest, let store = session.currentStore, store.useOnlineBooking == true else { return false }
        let slug = store.bookingSlug ?? ""
        let contact = store.bookingSettings?.contactTel ?? ""
        return slug.isEmpty || contact.isEmpty
    }

    /// 웹 `isSettingsMenuVisible` — 로그인한 직원(오너 아님)은 관리 메뉴를 보지 않는다.
    private var isLoggedInStaff: Bool { session.user.map { $0.role != .owner } ?? false }
    @State private var confirmGuestLogout = false

    var body: some View {
        NavigationStack {
            List {
                // 웹 `/menu` 머리 카드 — 매장 이름(작게) · 사용자(크게) · 이메일
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        if let name = session.currentStore?.name, !name.isEmpty {
                            Text(name).font(.tasSmall).foregroundStyle(Color.textSecondary)
                        }
                        Text(session.isGuest ? "게스트" : (session.user?.name ?? "-")).font(.tasTitle.weight(.bold))
                        if !session.isGuest, let email = session.user?.email, !email.isEmpty {
                            Text(email).font(.tasSmall).foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 웹 `SETTINGS_SUBMENU` 차례·이름·노출 조건(매출·고객 명단은 아래 탭에 있어 뺀다 — 웹 HIDDEN_IN_MENU)
                if !isLoggedInStaff {
                    Section {
                        menuButton("매장 관리", systemImage: "storefront") { showStoreEdit = true }
                            .disabled(session.currentStore == nil)
                        // 웹은 매장 관리 한 화면에 영업시간·휴무까지 — 앱은 편집 화면이 둘이라 바로 아래에 둔다
                        menuButton("영업시간·휴무", systemImage: "clock") { showHoursEdit = true }
                            .disabled(session.currentStore == nil)
                        if session.currentStore?.usePointSystem == true {
                            NavigationLink { PointManageView() } label: { menuLabel("적립금 관리", systemImage: "wonsign.circle") }
                        }
                        if serverFeaturesAvailable, session.currentStore?.useMembershipSystem == true {
                            NavigationLink { MembershipsView() } label: { menuLabel("회원권 관리", systemImage: "creditcard") }
                        }
                        if serverFeaturesAvailable, session.currentStore?.useCouponSystem == true {
                            NavigationLink { CouponsView() } label: { menuLabel("쿠폰 관리", systemImage: "ticket") }
                        }
                        if serverFeaturesAvailable, session.currentStore?.useOnlineBooking == true {
                            menuButton("고객 예약 설정", systemImage: "calendar.badge.clock",
                                       // 토글만 켜고 주소·연락처를 비워두면 공개 예약 페이지가 열리지 않는다.
                                       note: bookingNeedsSetup ? "설정 필요" : nil) { showBookingSettings = true }
                            // 웹처럼 공지는 고객 예약 페이지에 나가는 것이라 온라인예약을 켰을 때만
                            NavigationLink { NoticesView() } label: { menuLabel("공지사항 관리", systemImage: "megaphone") }
                        }
                        NavigationLink { ServicesView() } label: { menuLabel("\(session.labels.service) 관리", systemImage: "menucard") }
                        NavigationLink { AssigneesView() } label: { menuLabel("\(session.labels.assignee) 관리", systemImage: "person.text.rectangle") }
                    }
                }

                Section {
                    Link(destination: AppConfig.apiBaseURL.appending(path: "inquiry")) {
                        menuLabel("고객센터", systemImage: "envelope")
                    }
                    .accessibilityHint("웹 페이지 열기")
                    if session.user != nil {
                        Button { session.signOut() } label: { menuLabel("로그아웃", systemImage: "rectangle.portrait.and.arrow.forward") }
                    } else if session.isGuest {
                        // 웹처럼 한 번 묻는다 — 게스트 데이터는 이 기기에만 있어 지우면 되돌릴 수 없다
                        Button { confirmGuestLogout = true } label: { menuLabel("로그아웃", systemImage: "rectangle.portrait.and.arrow.forward") }
                            // 누른 줄에 붙여야 묻는 창이 그 줄을 가리킨다
                            .confirmationDialog("게스트 데이터를 모두 지우고 로그아웃할까요?", isPresented: $confirmGuestLogout, titleVisibility: .visible) {
                                Button("삭제하고 로그아웃", role: .destructive) { session.logoutGuest() }
                                Button("취소", role: .cancel) {}
                            }
                    }
                } footer: {
                    if session.isGuest {
                        Text("게스트 데이터는 이 기기에만 저장돼요. 로그아웃하면 모두 삭제됩니다. 로그인하면 데이터를 계정으로 옮길 수 있어요.")
                    }
                }

                // 웹에 없는 앱 기능(지시자 2026-10-22) — 예약 시각 전 휴대폰 알림. 안드로이드와 같은 선택지.
                Section {
                    Picker(selection: Binding(
                        get: { reminders.leadMinutes },
                        set: { minutes in
                            reminders.setLeadMinutes(minutes)
                            Task { notificationsDenied = !(await reminders.requestAuthorizationIfNeeded()) }
                        }
                    )) {
                        ForEach(ReservationReminder.leadOptions, id: \.self) { minutes in
                            Text(ReservationReminder.leadLabel(minutes)).tag(minutes)
                        }
                    } label: {
                        menuLabel("예약 알림", systemImage: "bell")
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 12) {
                        if notificationsDenied {
                            Text("알림이 꺼져 있어 보낼 수 없어요. 설정 앱 › TAS › 알림에서 켜 주세요.")
                        }
                        // 웹 `/menu` 아래 약관 링크 — 웹 페이지를 브라우저로 연다
                        HStack(spacing: 16) {
                            Link("이용약관", destination: AppConfig.apiBaseURL.appending(path: "terms"))
                            Link("개인정보처리방침", destination: AppConfig.apiBaseURL.appending(path: "privacy"))
                            if !session.isGuest {
                                Link("개인정보 처리위탁", destination: AppConfig.apiBaseURL.appending(path: "dpa"))
                            }
                        }
                        .font(.tasSmall)
                        .foregroundStyle(Color.textSecondary)
                        .frame(minHeight: 44)
                        Text(AppConfig.apiBaseURL.absoluteString).font(.tasXSmall)
                    }
                }
            }
            // 웹 카드 사이 간격 — 시스템 기본(넓음)보다 좁혀 한 화면에 더 보이게
            .listSectionSpacing(.compact)
            .navigationTitle("설정")
            // 웹 머리처럼 제목은 왼쪽 한 줄(큰 제목 칸 없음) — 그만큼 내용이 더 보인다
            .toolbarTitleDisplayMode(.inlineLarge)
            .toast($toast)
            .task { notificationsDenied = !(await reminders.requestAuthorizationIfNeeded()) }
            .sheet(isPresented: $showStoreEdit) {
                StoreSettingsEditView(onSaved: { toast = Toast(text: $0) }).environment(session)
            }
            .sheet(isPresented: $showHoursEdit) {
                StoreHoursEditView(onSaved: { toast = Toast(text: $0) }).environment(session)
            }
            .sheet(isPresented: $showBookingSettings) {
                BookingSettingsEditView().environment(session)
            }
        }
    }
}

extension SettingsView {
    /// 웹 메뉴 줄 — 보라 아이콘 + 검정 글자(밀어 들어가는 줄·시트 여는 줄·링크 모두 같은 모양).
    private func menuLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title).foregroundStyle(Color.textPrimary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Color.accentColor)
        }
    }

    /// 시트를 여는 메뉴 줄 — 밀어 들어가는 줄(NavigationLink)과 같은 모양(글자색·오른쪽 화살표).
    private func menuButton(_ title: String, systemImage: String, note: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                menuLabel(title, systemImage: systemImage)
                Spacer()
                if let note { Text(note).font(.caption).foregroundStyle(Color.warningText) }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel)) // 밀어 들어가는 줄의 시스템 화살표와 같은 색
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(SessionStore())
        .environment(ReminderScheduler.shared)
}
