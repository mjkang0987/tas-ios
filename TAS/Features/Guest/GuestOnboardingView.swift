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
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("게스트로 시작하기")
                .font(.system(.title, design: .rounded).bold())
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
            Text("매장 이름")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("예: 테이크어시트 헤어", text: $storeName)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { nameFocused = false }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - 업종 선택

    private var industryPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("업종 선택")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("고르면 기본 서비스가 자동으로 채워져요 (나중에 수정 가능)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            ForEach(ShopCatalog.categories, id: \.key) { category in
                let items = ShopCatalog.industries.filter { $0.category == category.key }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(category.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                            ForEach(items) { industry in
                                industryChip(industry)
                            }
                        }
                    }
                }
            }
        }
    }

    private func industryChip(_ industry: ShopIndustry) -> some View {
        let selected = selectedTypes.contains(industry.value)
        return Button {
            if selected { selectedTypes.remove(industry.value) }
            else { selectedTypes.insert(industry.value) }
        } label: {
            HStack(spacing: 6) {
                Text(industry.emoji)
                Text(industry.label)
                    .font(.subheadline)
                    .foregroundStyle(selected ? Color.accentColor : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(selected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
