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
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await service.fetchServices())
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// 서비스 추가/수정 — 수정이면 `originalName` 자리를 바꾼다(이름도 바꿀 수 있다).
    /// 이름·가격·시간이 바뀌면 앞으로의 미결제 예약에도 반영하고(웹 `updateService`), 결과 문구를 돌려준다. 실패면 nil.
    func save(_ item: ServiceItem, originalName: String?, labels: StoreLabels = .default) async -> String? {
        let prevCatalog = services
        var list = prevCatalog
        if let originalName, let i = list.firstIndex(where: { $0.name == originalName }) {
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
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
        let saved = "\(labels.service.josa(.iGa)) 저장되었습니다."
        guard let originalName else { return "\(labels.service.josa(.iGa)) 추가되었습니다." }
        // 카탈로그는 저장됐다 — 예약 반영이 실패해도 서비스 저장은 성공으로 두고 따로 알린다(웹과 같다).
        do {
            let reservations = try await service.fetchReservations().reservations
            let updates = ServiceRename.reservationUpdates(
                reservations, originalName: originalName, updatedName: item.name,
                prevCatalog: prevCatalog, nextCatalog: list, today: KST.dayKey.string(from: Date()))
            try await service.updateReservations(updates)
            return updates.isEmpty ? saved : "\(saved) 예정된 예약 \(updates.count)건에 반영했습니다."
        } catch {
            actionError = "\(labels.service) 변경을 예약에 반영하지 못했습니다. 새로고침 후 다시 확인해 주세요."
            return saved
        }
    }

    /// 서비스 삭제 — 카탈로그에서만 제거(기존 예약의 서비스 문자열은 보존).
    func delete(_ name: String) async -> Bool {
        let list = services.filter { $0.name != name }
        do {
            state = .loaded(try await service.saveServices(list, categoryBaseColors: categoryColors))
            return true
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 카테고리 이름·색 수정 — 그 카테고리 서비스를 모두 옮기고 색 키도 옮긴다(예약은 건드리지 않는다 — 안드로이드와 같다).
    /// 오류 문구를 돌려준다(성공이면 nil).
    func updateCategory(_ original: String, name: String, color: String) async -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "카테고리명을 입력해 주세요." }
        if trimmed != original, categories.contains(trimmed) { return "\"\(trimmed)\" 카테고리는 이미 있습니다." }
        let list = services.map { s -> ServiceItem in
            var s = s
            if s.category == original { s.category = trimmed }
            return s
        }
        var colors = categoryColors
        colors[original] = nil
        colors[trimmed] = color
        do {
            state = .loaded(try await service.saveServices(list, categoryBaseColors: colors))
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func hex(_ category: String) -> String {
        categoryColors[category] ?? ServiceColor.categoryBaseHex(category)
    }
}

/// 서비스(시술) 관리 — 웹 설정 > `ServiceManageSection` 이식(추가/수정/삭제). 설정에서 push.
struct ServicesView: View {
    @Environment(SessionStore.self) private var session
    private var labels: StoreLabels { session.labels }
    @State private var viewModel = ServicesViewModel()
    @State private var activeSheet: ActiveSheet?
    @State private var toast: Toast?

    private enum ActiveSheet: Identifiable {
        case create
        case edit(ServiceItem)
        case category(String)
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let s): return "edit-\(s.name)"
            case .category(let c): return "category-\(c)"
            }
        }
    }

    // 설정에서 NavigationLink로 push되므로 자체 NavigationStack 없이 상위 스택을 상속.
    var body: some View {
        LoadableView(state: viewModel.state, loadingText: "\(labels.service) 불러오는 중…") { _ in
            if viewModel.services.isEmpty {
                ContentUnavailableView {
                    Label("\(labels.service) 없음", systemImage: "menucard")
                } description: {
                    Text("우측 상단 + 로 \(labels.service.josa(.eulReul)) 추가하세요.\n예약 등록 시 여기서 만든 \(labels.service.josa(.eulReul)) 선택합니다.")
                }
            } else {
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
                                    Task {
                                        if await viewModel.delete(item.name) {
                                            toast = Toast(text: "\"\(item.name)\" \(labels.service.josa(.iGa)) 삭제되었습니다.", kind: .info)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            ColorDot(color: viewModel.color(group.category), size: 8)
                            Text(group.category)
                            Spacer()
                            // 웹·안드로이드 카테고리 머리의 '수정' — 이름·색
                            Button("수정") { activeSheet = .category(group.category) }
                                .font(.caption)
                                .textCase(nil)
                                .accessibilityLabel("\(group.category) 카테고리 수정")
                        }
                    }
                    }
                }
            }
        }
        .navigationTitle(labels.service)
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
                ServiceFormView(existingCategories: viewModel.categories, existingNames: viewModel.services.map(\.name)) { item in
                    await finishSave(viewModel.save(item, originalName: nil, labels: labels))
                }
            case .edit(let item):
                ServiceFormView(editing: item, existingCategories: viewModel.categories, existingNames: viewModel.services.map(\.name)) { updated in
                    await finishSave(viewModel.save(updated, originalName: item.name, labels: labels))
                }
            case .category(let name):
                CategoryEditView(name: name, color: viewModel.hex(name)) { newName, color in
                    await viewModel.updateCategory(name, name: newName, color: color)
                }
            }
        }
        .toast($toast)
        .task { await viewModel.load() }
    }
}

private extension ServicesView {
    /// 저장 결과를 토스트로 — 예약 반영이 실패했으면 그 안내를 오류로 이어서 보인다.
    func finishSave(_ message: String?) -> Bool {
        guard let message else { return false }
        if let error = viewModel.actionError {
            toast = Toast(text: error, kind: .error)
            viewModel.actionError = nil
        } else {
            toast = Toast(text: message)
        }
        return true
    }
}

/// 카테고리 이름·색 수정 — 웹·안드로이드 카테고리 '수정'(이름 칸 + 메모 태그와 같은 색 8개).
private struct CategoryEditView: View {
    let onSave: (String, String) async -> String?
    @State private var name: String
    @State private var color: String
    @State private var error: String?
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    init(name: String, color: String, onSave: @escaping (String, String) async -> String?) {
        _name = State(initialValue: name)
        _color = State(initialValue: color)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("카테고리명") {
                    TextField("카테고리명", text: $name)
                }
                Section("색") {
                    HStack(spacing: 2) {
                        ForEach(MemoTagEditor.colors, id: \.hex) { option in
                            Button { color = option.hex } label: {
                                Circle()
                                    .fill(Color(hex: option.hex) ?? .gray)
                                    .frame(width: 24, height: 24)
                                    .overlay { if option.hex.caseInsensitiveCompare(color) == .orderedSame { Circle().strokeBorder(.primary, lineWidth: 2) } }
                                    .frame(width: 36, height: 36)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("색 \(option.name)")
                            .accessibilityAddTraits(option.hex.caseInsensitiveCompare(color) == .orderedSame ? .isSelected : [])
                        }
                    }
                }
                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(Color.dangerText) }
                }
            }
            .navigationTitle("카테고리 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        isSaving = true
                        Task {
                            error = await onSave(name, color)
                            isSaving = false
                            if error == nil { dismiss() }
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}

private struct ServiceRow: View {
    let item: ServiceItem

    var body: some View {
        HStack {
            Text(item.name).font(.tasBody)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(formatWon(item.price)).font(.footnote.weight(.medium))
                Text("\(item.durationMinutes)분").font(.caption2).foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack { ServicesView() }
}
