import SwiftUI
import Observation

@MainActor
@Observable
final class MembershipsViewModel {
    var state: Loadable<[MembershipProduct]> = .idle
    var actionError: String?

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    /// 활성 먼저 → 이름순.
    var sorted: [MembershipProduct] {
        (state.value ?? []).sorted { a, b in
            let av = a.status == "active", bv = b.status == "active"
            if av != bv { return av }
            return a.name < b.name
        }
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await service.fetchMemberships().products)
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
}

/// 회원권 관리 — 웹 설정 > `MembershipManageSection` 이식(상품 카탈로그).
struct MembershipsView: View {
    @State private var viewModel = MembershipsViewModel()
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case create
        case edit(MembershipProduct)
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let m): return "edit-\(m.id)"
            }
        }
    }

    var body: some View {
        LoadableView(state: viewModel.state, loadingText: "회원권 불러오는 중…") { _ in
            if viewModel.sorted.isEmpty {
                ContentUnavailableView("회원권 없음", systemImage: "creditcard", description: Text("우측 상단 + 로 회원권을 등록하세요.\n발급·차감은 추후 지원됩니다."))
            } else {
                List {
                    ForEach(viewModel.sorted) { product in
                        Button {
                            activeSheet = .edit(product)
                        } label: {
                            MembershipRow(product: product)
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
        .navigationTitle("회원권")
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
                MembershipFormView { await viewModel.save($0, isNew: true) }
            case .edit(let product):
                MembershipFormView(editing: product) { await viewModel.save($0, isNew: false) }
            }
        }
        .task { await viewModel.load() }
    }
}

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

#Preview {
    NavigationStack { MembershipsView() }
}
