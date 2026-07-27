import SwiftUI
import Observation

@MainActor
@Observable
final class CouponsViewModel {
    struct Data {
        var products: [CouponProduct]
        var coupons: [CustomerCoupon]       // 발급분(로그인 시)
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
    var sortedProducts: [CouponProduct] {
        (state.value?.products ?? []).sorted { a, b in
            let av = a.status == "active", bv = b.status == "active"
            if av != bv { return av }
            return a.name < b.name
        }
    }

    /// 직접 발급 대상 상품 — 활성 + 코드형 제외(코드형은 코드 사용 흐름 전용, 서버 가드와 일치).
    var activeProducts: [CouponProduct] {
        (state.value?.products ?? [])
            .filter { $0.status == "active" && ($0.code ?? "").isEmpty }
            .sorted { $0.name < $1.name }
    }

    /// 발급분 — 사용가능 먼저, 그다음 발급일 최신순.
    var issued: [CustomerCoupon] {
        (state.value?.coupons ?? []).sorted { a, b in
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
            async let coupons = service.fetchCoupons()
            async let customers = service.fetchCustomers()
            let (cpn, cus) = try await (coupons, customers)
            let byId = Dictionary(cus.customers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            state = .loaded(Data(products: cpn.products, coupons: cpn.coupons ?? [],
                                 customersById: byId, customers: cus.customers))
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func save(_ product: CouponProduct, isNew: Bool) async -> Bool {
        do {
            if isNew { _ = try await service.createCoupon(product) }
            else { _ = try await service.updateCoupon(product) }
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
            try await service.deleteCoupon(id: id)
            await load()
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - 발급 (로그인 전용)

    @discardableResult
    func issue(customerId: Int, productId: String) async -> Bool {
        do {
            _ = try await service.issueCoupon(customerId: customerId, productId: productId)
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
            try await service.cancelCoupon(id: id)
            await load()
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// 쿠폰 관리 — 웹 설정 > `CouponManageSection` 이식(상품 CRUD + 직접 발급).
/// 발급은 로그인 전용(웹과 동일). 결제 자동 차감은 백엔드 Phase 3(미구현).
struct CouponsView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel = CouponsViewModel()
    @State private var tab: Tab = .products
    @State private var activeSheet: ActiveSheet?

    private enum Tab: String, CaseIterable { case products = "상품", issue = "발급" }

    private enum ActiveSheet: Identifiable {
        case create
        case edit(CouponProduct)
        case issue
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let c): return "edit-\(c.id)"
            case .issue: return "issue"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            LoadableView(state: viewModel.state, loadingText: "쿠폰 불러오는 중…") { _ in
                switch tab {
                case .products: productList
                case .issue: issueTab
                }
            }
        }
        .navigationTitle("쿠폰")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if tab == .products {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { activeSheet = .create } label: { Image(systemName: "plus") }
                        .disabled(viewModel.state.value == nil)
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                CouponFormView { await viewModel.save($0, isNew: true) }
            case .edit(let product):
                CouponFormView(editing: product) { await viewModel.save($0, isNew: false) }
            case .issue:
                CouponIssueSheet(
                    customers: viewModel.customers,
                    products: viewModel.activeProducts,
                    issued: viewModel.issued,
                    onIssue: { await viewModel.issue(customerId: $0, productId: $1) }
                )
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - 상품 탭

    @ViewBuilder private var productList: some View {
        if viewModel.sortedProducts.isEmpty {
            ContentUnavailableView("쿠폰 없음", systemImage: "ticket",
                                   description: Text("우측 상단 + 로 쿠폰 상품을 등록하세요."))
        } else {
            List {
                ForEach(viewModel.sortedProducts) { product in
                    Button { activeSheet = .edit(product) } label: { CouponRow(product: product) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("삭제", role: .destructive) { Task { await viewModel.delete(product.id) } }
                        }
                }
            }
        }
    }

    // MARK: - 발급 탭 (로그인 전용)

    @ViewBuilder private var issueTab: some View {
        if !session.isSignedIn {
            ContentUnavailableView("로그인 필요", systemImage: "lock",
                                   description: Text("쿠폰 발급은 로그인 후 이용할 수 있습니다."))
        } else {
            List {
                Section {
                    Button { activeSheet = .issue } label: { Label("쿠폰 발급", systemImage: "plus.circle") }
                        .disabled(viewModel.activeProducts.isEmpty)
                    if viewModel.activeProducts.isEmpty {
                        Text("직접 발급할 수 있는 쿠폰이 없습니다. (보관·코드형 제외)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let err = viewModel.actionError {
                    Section { Text(err).font(.footnote).foregroundStyle(.red) }
                }
                if viewModel.issued.isEmpty {
                    Section { Text("발급된 쿠폰이 없습니다.").font(.footnote).foregroundStyle(.secondary) }
                } else {
                    Section("발급 내역") {
                        ForEach(viewModel.issued) { c in
                            IssuedCouponRow(
                                coupon: c,
                                customerName: viewModel.customerName(c.customerId),
                                onCancel: { await viewModel.cancel(c.id) }
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 상품 행

private struct CouponRow: View {
    let product: CouponProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(product.name).font(.subheadline.weight(.medium)).lineLimit(1)
                if product.status != "active" {
                    Text("보관").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(CouponFormatting.discountText(product.discountType, product.discountValue, product.maxDiscount))
                    .font(.caption.weight(.semibold)).foregroundStyle(.tint)
            }
            HStack(spacing: 8) {
                if let c = product.code, !c.isEmpty {
                    Label(c, systemImage: "barcode").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("직접발급").font(.caption2).foregroundStyle(.secondary)
                }
                if let v = product.validDays, v > 0 {
                    Text("유효 \(v)일").font(.caption2).foregroundStyle(.secondary)
                }
                if let m = product.minOrderAmount, m > 0 {
                    Text("최소 \(formatWon(m))").font(.caption2).foregroundStyle(.secondary)
                }
                if product.oncePerCustomer {
                    Text("고객당 1장").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - 발급 내역 행

private struct IssuedCouponRow: View {
    let coupon: CustomerCoupon
    let customerName: String
    let onCancel: () async -> Void

    private var isActive: Bool { coupon.status == .active }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(customerName).font(.subheadline.weight(.semibold))
                Text(coupon.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(coupon.status.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            HStack(spacing: 10) {
                Text(CouponFormatting.discountText(coupon.discountType, coupon.discountValue, coupon.maxDiscount))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
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

private struct CouponIssueSheet: View {
    let customers: [Customer]
    let products: [CouponProduct]
    /// 발급분 — '고객당 1장' 상품의 중복 보유를 미리 걸러 서버 400을 피한다.
    let issued: [CustomerCoupon]
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

    /// '고객당 1장' 상품인데 해당 고객이 미사용 보유 중이면 사유 반환(발급 차단).
    private var blockedReason: String? {
        guard let customerId = selectedCustomerId, let productId = selectedProductId,
              let product = products.first(where: { $0.id == productId }),
              product.oncePerCustomer else { return nil }
        let holds = issued.contains {
            $0.customerId == customerId && $0.productId == productId && $0.status == .active
        }
        return holds ? "이 고객은 해당 쿠폰을 이미 보유 중입니다. (고객당 1장)" : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("고객") {
                    if let name = selectedCustomerName {
                        HStack {
                            Text(name)
                            Spacer()
                            Button("변경") { selectedCustomerId = nil; query = "" }.font(.caption)
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

                Section("쿠폰") {
                    Picker("상품", selection: $selectedProductId) {
                        Text("선택").tag(String?.none)
                        ForEach(products) { p in
                            Text(p.name).tag(String?.some(p.id))
                        }
                    }
                }

                if let blockedReason {
                    Section { Text(blockedReason).font(.footnote).foregroundStyle(.orange) }
                }
                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("쿠폰 발급")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("발급") { Task { await issue() } }
                        .disabled(isSaving || selectedCustomerId == nil || selectedProductId == nil || blockedReason != nil)
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

/// 쿠폰 할인 표시 — 상품/발급 행 공용(하드코딩 중복 방지).
enum CouponFormatting {
    static func discountText(_ type: CouponDiscountType, _ value: Int, _ maxDiscount: Int?) -> String {
        switch type {
        case .amount:
            return "\(value.formatted())원 할인"
        case .rate:
            var s = "\(value)% 할인"
            if let m = maxDiscount, m > 0 { s += " (최대 \(formatWon(m)))" }
            return s
        }
    }
}

#Preview {
    NavigationStack { CouponsView() }
        .environment(SessionStore())
}
