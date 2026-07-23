import SwiftUI
import Observation

@MainActor
@Observable
final class AssigneesViewModel {
    var state: Loadable<[Assignee]> = .idle

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    /// 저장/삭제 중 실패 메시지(폼·목록에서 표시).
    var actionError: String?

    /// 재직 우선 → 이름 순.
    var sorted: [Assignee] {
        (state.value ?? []).sorted { lhs, rhs in
            let l = lhs.status == .retired ? 1 : 0
            let r = rhs.status == .retired ? 1 : 0
            if l != r { return l < r }
            return lhs.name < rhs.name
        }
    }

    /// 다음 담당자 정수 id(현재 최대 +1).
    var nextId: Int { ((state.value?.map(\.id).max()) ?? 0) + 1 }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await service.fetchAssignees().assignees)
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// 담당자 추가/수정 — id로 upsert 후 전체 목록을 PUT(웹 일괄 저장 모델).
    /// 성공 시 true, 실패 시 actionError 설정 후 false.
    func save(_ assignee: Assignee) async -> Bool {
        var list = state.value ?? []
        if let i = list.firstIndex(where: { $0.id == assignee.id }) {
            list[i] = assignee
        } else {
            list.append(assignee)
        }
        do {
            let saved = try await service.saveAssignees(list)
            state = .loaded(saved)
            actionError = nil
            return true
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 담당자 삭제 — 예약은 보존, assigneeId만 분리(서버/로컬 동일).
    func delete(_ id: Int) async {
        do {
            try await service.deleteAssignee(id: id)
            await load()
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// 담당자(디자이너) 관리 — 웹 설정 > `designer` 탭 이식(추가/수정/삭제). 설정에서 push.
struct AssigneesView: View {
    @State private var viewModel = AssigneesViewModel()
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case create
        case edit(Assignee)
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let a): return "edit-\(a.id)"
            }
        }
    }

    var body: some View {
        LoadableView(state: viewModel.state, loadingText: "담당자 불러오는 중…") { _ in
            List {
                ForEach(viewModel.sorted) { assignee in
                    Button {
                        activeSheet = .edit(assignee)
                    } label: {
                        AssigneeRow(assignee: assignee)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("삭제", role: .destructive) {
                            Task { await viewModel.delete(assignee.id) }
                        }
                    }
                }
            }
        }
        .navigationTitle("담당자")
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
                AssigneeFormView(nextId: viewModel.nextId) { await viewModel.save($0) }
            case .edit(let assignee):
                AssigneeFormView(editing: assignee) { await viewModel.save($0) }
            }
        }
        .task { await viewModel.load() }
    }
}

private struct AssigneeRow: View {
    let assignee: Assignee

    private static let weekdayLabels = ["월", "화", "수", "목", "금", "토", "일"]

    var body: some View {
        HStack(spacing: 10) {
            ColorDot(color: Color(hex: assignee.color) ?? .gray, size: 9)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(assignee.name).font(.subheadline.weight(.medium))
                    if let status = assignee.status { AssigneeStatusText(status: status) }
                }
                Text(scheduleSummary).font(.caption2).foregroundStyle(.secondary)
                if let phone = assignee.phone, !phone.isEmpty {
                    Text(phone).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 1)
    }

    private var scheduleSummary: String {
        let enabled = zip(Self.weekdayLabels, assignee.schedule)
            .filter { $0.1.enabled }
        guard !enabled.isEmpty else { return "휴무" }
        let days = enabled.map(\.0).joined(separator: "·")
        if let first = enabled.first?.1 {
            return "\(days) \(first.start)–\(first.end)"
        }
        return days
    }
}

private struct AssigneeStatusText: View {
    let status: AssigneeStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .active: return .green
        case .leave: return .orange
        case .retired: return .gray
        }
    }
}
