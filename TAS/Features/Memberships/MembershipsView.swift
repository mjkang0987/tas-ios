import SwiftUI
import Observation

@MainActor
@Observable
final class MembershipsViewModel {
    struct Data {
        var products: [MembershipProduct]
        var memberships: [CustomerMembership]      // 발급분(로그인 시)
        var customersById: [Int: Customer]
        var customers: [Customer]
    }

    var state: Loadable<Data> = .idle
    var actionError: String?

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    /// 활성 먼저 → 이름순.
    var sortedProducts: [MembershipProduct] {
        (state.value?.products ?? []).sorted { a, b in
            let av = a.status == "active", bv = b.status == "active"
            if av != bv { return av }
            return a.name < b.name
        }
    }

    /// 발급 대상으로 고를 수 있는 활성 상품.
    var activeProducts: [MembershipProduct] {
        (state.value?.products ?? []).filter { $0.status == "active" }.sorted { $0.name < $1.name }
    }

    /// 발급분 — 사용중 먼저, 그다음 발급일 최신순.
    var issued: [CustomerMembership] {
        (state.value?.memberships ?? []).sorted { a, b in
            let av = a.status == .active, bv = b.status == .active
            if av != bv { return av }
            return a.issuedAt > b.issuedAt
        }
    }

    var customers: [Customer] { state.value?.customers ?? [] }
    func customerName(_ id: Int) -> String { state.value?.customersById[id]?.name ?? "고객 #\(id)" }

    func load() async {
        state = .loading
        do {
            async let memberships = service.fetchMemberships()
            async let customers = service.fetchCustomers()
            let (mem, cus) = try await (memberships, customers)
            let byId = Dictionary(cus.customers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            state = .loaded(Data(products: mem.products, memberships: mem.memberships ?? [],
                                 customersById: byId, customers: cus.customers))
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func save(_ product: MembershipProduct, isNew: Bool) async -> Bool {
        do {
            if isNew { _ = try await service.createMembership(product) }
            else { _ = try await service.updateMembership(product) }
            await load()
            actionError = nil
            return true
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func delete(_ id: String) async {
        do {
            try await service.deleteMembership(id: id)
            await load()
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - 발급/차감 (로그인 전용)

    @discardableResult
    func issue(customerId: Int, productId: String) async -> Bool {
        do {
            _ = try await service.issueMembership(customerId: customerId, productId: productId)
            await load()
            actionError = nil
            return true
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func cancel(_ id: String) async {
        do {
            try await service.cancelMembership(id: id)
            await load()
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func use(_ id: String, action: MembershipUseAction) async {
        do {
            _ = try await service.useMembership(id: id, action: action)
            await load()
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// 회원권 관리 — 웹 설정 > `MembershipManageSection` 이식(상품 CRUD + 발급/차감).
///
/// **화면 전체가 로그인 전용**(웹 `isLocal` 게이트와 동일). 상품만 게스트에서 만들 수 있게 두면
/// 발급도 못 하고, `POST /api/migrate-local`이 받는 건 서비스·담당자·고객·예약뿐이라
/// 로그인해도 계정으로 넘어가지 않는 막다른 데이터가 된다.
struct MembershipsView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel = MembershipsViewModel()
    @State private var tab: Tab = .products
    @State private var activeSheet: ActiveSheet?

    private enum Tab: String, CaseIterable { case products = "상품", issue = "발급" }

    private enum ActiveSheet: Identifiable {
        case create
        case edit(MembershipProduct)
        case issue
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let m): return "edit-\(m.id)"
            case .issue: return "issue"
            }
        }
    }

    var body: some View {
        Group {
            if session.isSignedIn {
                content
            } else {
                ContentUnavailableView("로그인 필요", systemImage: "lock",
                                       description: Text("회원권은 로그인 후 이용할 수 있습니다."))
            }
        }
        .navigationTitle("회원권")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.isSignedIn, tab == .products {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { activeSheet = .create } label: { Image(systemName: "plus") }
                        .disabled(viewModel.state.value == nil)
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                MembershipFormView { await viewModel.save($0, isNew: true) }
            case .edit(let product):
                MembershipFormView(editing: product) { await viewModel.save($0, isNew: false) }
            case .issue:
                MembershipIssueSheet(
                    customers: viewModel.customers,
                    products: viewModel.activeProducts,
                    onIssue: { await viewModel.issue(customerId: $0, productId: $1) }
                )
            }
        }
        .task {
            // 게스트는 잠금 안내만 — 로컬 스냅샷을 읽을 필요가 없다.
            if session.isSignedIn { await viewModel.load() }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            LoadableView(state: viewModel.state, loadingText: "회원권 불러오는 중…") { _ in
                switch tab {
                case .products: productList
                case .issue: issueTab
                }
            }
        }
    }

    // MARK: - 상품 탭

    @ViewBuilder private var productList: some View {
        if viewModel.sortedProducts.isEmpty {
            ContentUnavailableView("회원권 없음", systemImage: "creditcard",
                                   description: Text("우측 상단 + 로 회원권 상품을 등록하세요."))
        } else {
            List {
                ForEach(viewModel.sortedProducts) { product in
                    Button { activeSheet = .edit(product) } label: { MembershipRow(product: product) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("삭제", role: .destructive) { Task { await viewModel.delete(product.id) } }
                        }
                }
            }
        }
    }

    // MARK: - 발급 탭 (화면 전체가 로그인 전용이라 별도 게이트 없음)

    private var issueTab: some View {
        List {
            Section {
                Button {
                    activeSheet = .issue
                } label: {
                    Label("회원권 발급", systemImage: "plus.circle")
                }
                .disabled(viewModel.activeProducts.isEmpty)
                if viewModel.activeProducts.isEmpty {
                    Text("발급할 활성 회원권 상품이 없습니다.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let err = viewModel.actionError {
                Section { Text(err).font(.footnote).foregroundStyle(.red) }
            }
            if viewModel.issued.isEmpty {
                Section { Text("발급된 회원권이 없습니다.").font(.footnote).foregroundStyle(.secondary) }
            } else {
                Section("발급 내역") {
                    ForEach(viewModel.issued) { m in
                        IssuedMembershipRow(
                            membership: m,
                            customerName: viewModel.customerName(m.customerId),
                            onUse: { await viewModel.use(m.id, action: .use) },
                            onRestore: { await viewModel.use(m.id, action: .restore) },
                            onCancel: { await viewModel.cancel(m.id) }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 상품 행

private struct MembershipRow: View {
    let product: MembershipProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(product.name).font(.subheadline.weight(.medium)).lineLimit(1)
                if product.status != "active" {
                    Text("보관").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatWon(product.price)).font(.caption.weight(.semibold))
            }
            HStack(spacing: 8) {
                if let c = product.totalCount, c > 0 {
                    Text("\(c)회").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("횟수 무제한").font(.caption2).foregroundStyle(.secondary)
                }
                if let v = product.validDays, v > 0 {
                    Text("유효 \(v)일").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("무기한").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - 발급 내역 행

private struct IssuedMembershipRow: View {
    let membership: CustomerMembership
    let customerName: String
    let onUse: () async -> Void
    let onRestore: () async -> Void
    let onCancel: () async -> Void

    private var countLabel: String {
        guard let remaining = membership.remainingCount, let total = membership.totalCount else { return "무제한" }
        return "\(remaining)/\(total)회"
    }
    private var isActive: Bool { membership.status == .active }
    private var isCountable: Bool { membership.totalCount != nil && membership.remainingCount != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(customerName).font(.subheadline.weight(.semibold))
                Text(membership.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(membership.status.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            HStack(spacing: 10) {
                Text(countLabel).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                if isActive && isCountable {
                    Button("차감") { Task { await onUse() } }
                        .buttonStyle(.bordered).controlSize(.mini)
                    Button("복원") { Task { await onRestore() } }
                        .buttonStyle(.bordered).controlSize(.mini)
                }
                if isActive {
                    Button("취소", role: .destructive) { Task { await onCancel() } }
                        .buttonStyle(.bordered).controlSize(.mini)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 발급 시트 (고객 + 상품 선택)

private struct MembershipIssueSheet: View {
    let customers: [Customer]
    let products: [MembershipProduct]
    let onIssue: (Int, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedCustomerId: Int?
    @State private var selectedProductId: String?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var filteredCustomers: [Customer] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return customers.filter { $0.name.contains(q) || $0.tel.contains(q) }.prefix(6).map { $0 }
    }

    private var selectedCustomerName: String? {
        selectedCustomerId.flatMap { id in customers.first { $0.id == id }?.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("고객") {
                    if let name = selectedCustomerName {
                        HStack {
                            Text(name)
                            Spacer()
                            Button("변경") { selectedCustomerId = nil; query = "" }
                                .font(.caption)
                        }
                    } else {
                        TextField("고객명 또는 연락처 검색", text: $query)
                            .autocorrectionDisabled()
                        ForEach(filteredCustomers) { c in
                            Button {
                                selectedCustomerId = c.id
                            } label: {
                                HStack {
                                    Text(c.name)
                                    Spacer()
                                    Text(c.formattedTel).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("회원권") {
                    Picker("상품", selection: $selectedProductId) {
                        Text("선택").tag(String?.none)
                        ForEach(products) { p in
                            Text(p.name).tag(String?.some(p.id))
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("회원권 발급")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("발급") { Task { await issue() } }
                        .disabled(isSaving || selectedCustomerId == nil || selectedProductId == nil)
                }
            }
        }
    }

    private func issue() async {
        guard let customerId = selectedCustomerId, let productId = selectedProductId else { return }
        isSaving = true
        defer { isSaving = false }
        if await onIssue(customerId, productId) {
            dismiss()
        } else {
            errorMessage = "발급에 실패했습니다."
        }
    }
}

#Preview {
    NavigationStack { MembershipsView() }
        .environment(SessionStore())
}
