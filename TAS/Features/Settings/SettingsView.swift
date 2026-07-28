import SwiftUI

/// 설정 — 매장 정보 및 로그아웃. 웹의 `/settings/*` 허브에 대응하는 스켈레톤.
struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @State private var showStoreEdit = false
    @State private var showHoursEdit = false
    @State private var showPointSettings = false
    @State private var showBookingSettings = false

    /// 온라인예약을 켰지만 공개 주소(슬러그)나 매장 연락처가 비어 있는 상태.
    /// 게스트는 설정 자체가 로그인 전용이라 판정에서 제외한다.
    private var bookingNeedsSetup: Bool {
        guard !session.isGuest, let store = session.currentStore, store.useOnlineBooking == true else { return false }
        let slug = store.bookingSlug ?? ""
        let contact = store.bookingSettings?.contactTel ?? ""
        return slug.isEmpty || contact.isEmpty
    }

    /// 켜진 기능이 하나라도 있으면 "기능 설정" 섹션을 노출.
    private var hasFeatureSettings: Bool {
        guard let store = session.currentStore else { return false }
        return store.usePointSystem == true || store.useCouponSystem == true
            || store.useMembershipSystem == true || store.useOnlineBooking == true
    }

    var body: some View {
        NavigationStack {
            List {
                Section("매장") {
                    LabeledContent("이름", value: session.currentStore?.name ?? "-")
                    if let label = ShopCatalog.shopTypeLabel(session.currentStore?.shopType) {
                        LabeledContent("업종", value: label)
                    }
                    // 공개 예약 주소는 온라인예약을 쓸 때만 의미가 있다(편집은 온라인예약 설정에서).
                    if session.currentStore?.useOnlineBooking == true,
                       let slug = session.currentStore?.bookingSlug, !slug.isEmpty {
                        LabeledContent("예약 주소", value: slug)
                    }
                    Button("매장 정보 편집") { showStoreEdit = true }
                        .disabled(session.currentStore == nil)
                    Button("영업시간·휴무 설정") { showHoursEdit = true }
                        .disabled(session.currentStore == nil)
                }

                // 매장 정보에서 켠 기능은 여기서 **바로 그 기능의 설정 화면으로** 들어간다.
                // (읽기 전용 토글을 다시 보여주지 않는다 — 켜고 끄는 곳은 매장 정보 편집 한 곳.)
                if hasFeatureSettings {
                    Section {
                        if session.currentStore?.usePointSystem == true {
                            Button { showPointSettings = true } label: {
                                Label("적립금 설정", systemImage: "wonsign.circle")
                            }
                        }
                        if session.currentStore?.useCouponSystem == true {
                            NavigationLink {
                                CouponsView()
                            } label: {
                                Label("쿠폰 관리", systemImage: "ticket")
                            }
                        }
                        if session.currentStore?.useMembershipSystem == true {
                            NavigationLink {
                                MembershipsView()
                            } label: {
                                Label("회원권 관리", systemImage: "creditcard")
                            }
                        }
                        if session.currentStore?.useOnlineBooking == true {
                            Button { showBookingSettings = true } label: {
                                HStack {
                                    Label("온라인예약 설정", systemImage: "calendar.badge.clock")
                                    // 토글만 켜고 주소·연락처를 비워두면 공개 예약 페이지가 열리지 않는다.
                                    // (서버는 예약 설정을 저장할 때만 필수를 강제해서, 켜두기만 한 상태가 생긴다.)
                                    if bookingNeedsSetup {
                                        Spacer()
                                        Text("설정 필요").font(.caption).foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("기능 설정")
                    } footer: {
                        Text("사용할 기능은 매장 정보 편집에서 켜고 끕니다.")
                    }
                }

                Section("관리") {
                    NavigationLink {
                        ServicesView()
                    } label: {
                        Label("서비스", systemImage: "menucard")
                    }
                    NavigationLink {
                        AssigneesView()
                    } label: {
                        Label("담당자", systemImage: "person.text.rectangle")
                    }
                    NavigationLink {
                        NoticesView()
                    } label: {
                        Label("공지", systemImage: "megaphone")
                    }
                    NavigationLink {
                        RevenueView()
                    } label: {
                        Label("매출", systemImage: "wonsign.circle")
                    }
                }

                Section {
                    if let user = session.user {
                        LabeledContent("권한", value: user.role.rawValue)
                        Button("로그아웃", role: .destructive) {
                            session.signOut()
                        }
                    } else if session.isGuest {
                        LabeledContent("모드", value: "게스트")
                        Button("로그아웃 (게스트 데이터 삭제)", role: .destructive) {
                            session.logoutGuest()
                        }
                    }
                } header: {
                    Text("계정")
                } footer: {
                    if session.isGuest {
                        Text("게스트 데이터는 이 기기에만 저장돼요. 로그아웃하면 모두 삭제됩니다. 로그인하면 데이터를 계정으로 옮길 수 있어요.")
                    }
                }

                Section {
                    LabeledContent("API", value: AppConfig.apiBaseURL.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("설정")
            .sheet(isPresented: $showStoreEdit) {
                StoreSettingsEditView().environment(session)
            }
            .sheet(isPresented: $showHoursEdit) {
                StoreHoursEditView().environment(session)
            }
            .sheet(isPresented: $showPointSettings) {
                PointSettingsEditView().environment(session)
            }
            .sheet(isPresented: $showBookingSettings) {
                BookingSettingsEditView().environment(session)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(SessionStore())
}
