import SwiftUI

/// 매장 정보 편집 — 이름 + 기능 토글(적립금·회원권·온라인예약).
/// 웹 설정 > 매장관리의 PATCH /api/store 필드 중 앱에서 노출하는 부분만 편집한다.
/// (업종·예약 슬러그는 재온보딩 영역이라 표시 전용으로 남긴다.)
struct StoreSettingsEditView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    var service = TASService()

    @State private var name = ""
    /// 선택한 대표 업종 value("hair" 등). 빈 문자열이면 "선택 안 함".
    @State private var shopType = ""
    @State private var usePointSystem = false
    @State private var useMembershipSystem = false
    @State private var useCouponSystem = false
    @State private var useOnlineBooking = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("매장") {
                    TextField("매장 이름", text: $name)
                    Picker("업종", selection: $shopType) {
                        Text("선택 안 함").tag("")
                        ForEach(ShopCatalog.industryGroups(including: shopType), id: \.category) { group in
                            Section(group.category) {
                                ForEach(group.items) { ind in
                                    Text("\(ind.emoji) \(ind.label)").tag(ind.value)
                                }
                            }
                        }
                    }
                }

                Section {
                    Toggle("적립금", isOn: $usePointSystem)
                    // 쿠폰·회원권·온라인예약은 서버가 있어야 동작한다(발급/차감 API, 공개 예약 페이지).
                    // 게스트에게 토글만 주면 켜도 쓸 수 없으니 아예 노출하지 않는다.
                    if !session.isGuest {
                        Toggle("쿠폰", isOn: $useCouponSystem)
                        Toggle("회원권", isOn: $useMembershipSystem)
                        Toggle("온라인예약", isOn: $useOnlineBooking)
                    }
                } header: {
                    Text("기능")
                } footer: {
                    if session.isGuest {
                        Text("게스트 모드에선 적립금만 사용할 수 있어요. 쿠폰·회원권·온라인예약은 로그인 후 켤 수 있습니다.")
                    } else {
                        Text("기능을 켜면 설정 화면에 세부 설정 항목이 나타납니다.")
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("매장 정보")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .onAppear(perform: setup)
        }
    }

    private func setup() {
        guard let store = session.currentStore else { return }
        name = store.name
        // 여러 업종이 있어도 웹처럼 대표(첫) 업종 1개를 선택값으로.
        shopType = ShopCatalog.primaryIndustry(shopType: store.shopType)?.value ?? ""
        usePointSystem = store.usePointSystem ?? false
        useMembershipSystem = store.useMembershipSystem ?? false
        useCouponSystem = store.useCouponSystem ?? false
        useOnlineBooking = store.useOnlineBooking ?? false
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { errorMessage = "매장 이름을 입력해주세요."; return }
        guard let current = session.currentStore else { errorMessage = "매장 정보를 불러오지 못했습니다."; return }
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await service.updateStore(
                current: current,
                name: trimmed,
                shopType: shopType.isEmpty ? nil : shopType,
                usePointSystem: usePointSystem,
                useMembershipSystem: useMembershipSystem,
                useCouponSystem: useCouponSystem,
                useOnlineBooking: useOnlineBooking
            )
            session.currentStore = updated
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
