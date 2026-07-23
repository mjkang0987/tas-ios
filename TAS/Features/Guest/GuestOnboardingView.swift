import SwiftUI

/// 게스트 온보딩 — 웹 `/onboarding/guest` 이식.
///
/// 로그인 없이 매장 이름 + 업종을 받아 로컬 스냅샷을 온보딩 완료 상태로 만든다.
/// 업종을 고르면 웹처럼 기본 서비스·카테고리 색·기본 담당자(원장)를 자동 시드한다.
/// 게스트 데이터는 이 기기에만 저장되며, 로그인 시 서버로 이관할 수 있다.
struct GuestOnboardingView: View {
    @Environment(GuestStore.self) private var guest
    @Environment(SessionStore.self) private var session
    @State private var storeName = ""
    @State private var selectedTypes: Set<String> = []
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 32)
                header
                guestNotice
                storeNameField
                industryPicker
                actions
                Button("로그인으로 돌아가기") { session.exitGuest() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Spacer(minLength: 24)
            }
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
        .background(Color(.systemBackground))
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { nameFocused = false }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("게스트로 시작하기")
                .font(.title2.bold())
            Text("⚡ 30초 설정으로 바로 시작")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// 게스트 모드 안내(웹 GuestNotice).
    private var guestNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("게스트 모드 안내", systemImage: "info.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text("데이터는 이 기기에만 저장돼요. 다른 기기에선 보이지 않고, 앱 데이터를 지우면 사라져요. 로그인하면 지금까지 입력한 데이터를 계정으로 옮길 수 있어요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var storeNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("샵 이름")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("예) 우리 매장", text: $storeName)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { nameFocused = false }
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - 업종 선택 (웹 OnboardingStep1 — 평평한 그리드 + 세로 카드)

    private var industryPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("업종 (복수 선택 가능)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(ShopCatalog.industries) { industry in
                    industryCard(industry)
                }
            }
        }
    }

    private func industryCard(_ industry: ShopIndustry) -> some View {
        let selected = selectedTypes.contains(industry.value)
        return Button {
            if selected { selectedTypes.remove(industry.value) }
            else { selectedTypes.insert(industry.value) }
        } label: {
            VStack(spacing: 4) {
                Text(industry.emoji)
                    .font(.system(size: 24))
                Text(industry.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(industry.desc)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(selected ? Color.accentColor.opacity(0.06) : Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? Color.accentColor : Color(.separator), lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 액션

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                start()
            } label: {
                Text("시작하기")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)

            Button("설정 없이 둘러보기") { skip() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func start() {
        let name = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let types = Array(selectedTypes)
        // 웹처럼 'etc'는 실제 업종 문자열에서 제외.
        let realTypes = types.filter { $0 != "etc" }.sorted()
        guest.completeOnboarding(
            storeName: name.isEmpty ? nil : name,
            shopType: realTypes.isEmpty ? nil : realTypes.joined(separator: ","),
            services: ShopCatalog.defaultServices(for: types),
            assignees: ShopCatalog.defaultAssignees(),
            categoryBaseColors: ShopCatalog.categoryColors(for: types)
        )
        session.currentStore = guest.syntheticStore
    }

    private func skip() {
        // 업종 없이 기본 담당자만 두고 진입(웹 '건너뛰기'에 대응).
        guest.completeOnboarding(storeName: nil, shopType: nil,
                                 services: [], assignees: ShopCatalog.defaultAssignees())
        session.currentStore = guest.syntheticStore
    }
}

#Preview {
    GuestOnboardingView()
        .environment(GuestStore.shared)
        .environment(SessionStore())
}
