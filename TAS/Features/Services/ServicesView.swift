import SwiftUI
import Observation

@MainActor
@Observable
final class ServicesViewModel {
    var state: Loadable<ServicesResponse> = .idle
    var actionError: String?

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    var services: [ServiceItem] { state.value?.services ?? [] }
    var categoryColors: [String: String] { state.value?.categoryBaseColors ?? [:] }

    /// 카테고리별 그룹(등장 순서 유지) — 목록 섹션용.
    var grouped: [(category: String, items: [ServiceItem])] {
        var order: [String] = []
        var map: [String: [ServiceItem]] = [:]
        for s in services {
            if map[s.category] == nil { order.append(s.category) }
            map[s.category, default: []].append(s)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    /// 기존 카테고리 목록(폼의 카테고리 선택용).
    var categories: [String] {
        var seen = Set<String>(); var out: [String] = []
        for s in services where !seen.contains(s.category) {
            seen.insert(s.category); out.append(s.category)
        }
        return out
    }

    func color(_ category: String) -> Color {
        ServiceColor.categoryColor(category, storeMap: categoryColors)
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await service.fetchServices())
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// 서비스 추가/수정 — name을 식별자로 upsert(이름은 폼에서 편집 시 고정).
    /// 새 카테고리는 기본 색을 보강해 categoryBaseColors에 함께 저장.
    func save(_ item: ServiceItem) async -> Bool {
        var list = services
        if let i = list.firstIndex(where: { $0.name == item.name }) {
            list[i] = item
        } else {
            list.append(item)
        }
        var colors = categoryColors
        if colors[item.category] == nil {
            colors[item.category] = ServiceColor.categoryBaseHex(item.category)
        }
        do {
            state = .loaded(try await service.saveServices(list, categoryBaseColors: colors))
            actionError = nil
            return true
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 서비스 삭제 — 카탈로그에서만 제거(기존 예약의 서비스 문자열은 보존).
    func delete(_ name: String) async {
        let list = services.filter { $0.name != name }
        do {
            state = .loaded(try await service.saveServices(list, categoryBaseColors: categoryColors))
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// 서비스(시술) 관리 — 웹 설정 > `ServiceManageSection` 이식(추가/수정/삭제). 설정에서 push.
struct ServicesView: View {
    @State private var viewModel = ServicesViewModel()
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case create
        case edit(ServiceItem)
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let s): return "edit-\(s.name)"
            }
        }
    }

    var body: some View {
        LoadableView(state: viewModel.state, loadingText: "서비스 불러오는 중…") { _ in
            List {
                ForEach(viewModel.grouped, id: \.category) { group in
                    Section {
                        ForEach(group.items) { item in
                            Button {
                                activeSheet = .edit(item)
                            } label: {
                                ServiceRow(item: item)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button("삭제", role: .destructive) {
                                    Task { await viewModel.delete(item.name) }
                                }
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            ColorDot(color: viewModel.color(group.category), size: 8)
                            Text(group.category)
                        }
                    }
                }
            }
        }
        .navigationTitle("서비스")
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
                ServiceFormView(existingCategories: viewModel.categories) { await viewModel.save($0) }
            case .edit(let item):
                ServiceFormView(editing: item, existingCategories: viewModel.categories) { await viewModel.save($0) }
            }
        }
        .task { await viewModel.load() }
    }
}

private struct ServiceRow: View {
    let item: ServiceItem

    var body: some View {
        HStack {
            Text(item.name).font(.subheadline)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(formatWon(item.price)).font(.footnote.weight(.medium))
                Text("\(item.durationMinutes)분").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack { ServicesView() }
}
