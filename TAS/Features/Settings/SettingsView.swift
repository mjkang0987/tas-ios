import SwiftUI

/// 설정 — 매장 정보 및 로그아웃. 웹의 `/settings/*` 허브에 대응하는 스켈레톤.
struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @State private var showStoreEdit = false

    var body: some View {
        NavigationStack {
            List {
                Section("매장") {
                    LabeledContent("이름", value: session.currentStore?.name ?? "-")
                    if let type = session.currentStore?.shopType {
                        LabeledContent("업종", value: type)
                    }
                    if let slug = session.currentStore?.bookingSlug {
                        LabeledContent("예약 슬러그", value: slug)
                    }
                    Button("매장 정보 편집") { showStoreEdit = true }
                        .disabled(session.currentStore == nil)
                }

                Section("기능") {
                    Toggle("적립금", isOn: .constant(session.currentStore?.usePointSystem ?? false)).disabled(true)
                    Toggle("회원권", isOn: .constant(session.currentStore?.useMembershipSystem ?? false)).disabled(true)
                    Toggle("온라인예약", isOn: .constant(session.currentStore?.useOnlineBooking ?? false)).disabled(true)
                }

                Section("관리") {
                    NavigationLink {
                        AssigneesView()
                    } label: {
                        Label("담당자", systemImage: "person.text.rectangle")
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
        }
    }
}

#Preview {
    SettingsView()
        .environment(SessionStore())
}
