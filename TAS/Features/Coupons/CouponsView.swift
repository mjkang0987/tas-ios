import SwiftUI
import Observation

@MainActor
@Observable
final class CouponsViewModel {
    var state: Loadable<[CouponProduct]> = .idle
    var actionError: String?

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    /// 활성 먼저 → 이름순.
    var sorted: [CouponProduct] {
        (state.value ?? []).sorted { a, b in
            let av = a.status == "active", bv = b.status == "active"
            if av != bv { return av }
            return a.name < b.name
        }
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await service.fetchCoupons().products)
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
}

/// 쿠폰 관리 — 웹 설정 > `CouponManageSection` 이식(상품 등록).
struct CouponsView: View {
    @State private var viewModel = CouponsViewModel()
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case create
        case edit(CouponProduct)
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let c): return "edit-\(c.id)"
            }
        }
    }

    var body: some View {
        LoadableView(state: viewModel.state, loadingText: "쿠폰 불러오는 중…") { _ in
            if viewModel.sorted.isEmpty {
                ContentUnavailableView("쿠폰 없음", systemImage: "ticket", description: Text("우측 상단 + 로 쿠폰을 등록하세요.\n발급·결제 차감은 추후 지원됩니다."))
            } else {
                List {
                    ForEach(viewModel.sorted) { product in
                        Button {
                            activeSheet = .edit(product)
                        } label: {
                            CouponRow(product: product)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("삭제", role: .destructive) {
                                Task { await viewModel.delete(product.id) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("쿠폰")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    activeSheet = .create
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(viewModel.state.value == nil)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                CouponFormView { await viewModel.save($0, isNew: true) }
            case .edit(let product):
                CouponFormView(editing: product) { await viewModel.save($0, isNew: false) }
            }
        }
        .task { await viewModel.load() }
    }
}

private struct CouponRow: View {
    let product: CouponProduct

    private var discountText: String {
        switch product.discountType {
        case .amount: return "\(product.discountValue.formatted())원 할인"
        case .rate:
            var s = "\(product.discountValue)% 할인"
            if let m = product.maxDiscount, m > 0 { s += " (최대 \(formatWon(m)))" }
            return s
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(product.name).font(.subheadline.weight(.medium)).lineLimit(1)
                if product.status != "active" {
                    Text("보관").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(discountText).font(.caption.weight(.semibold)).foregroundStyle(.tint)
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
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack { CouponsView() }
}
