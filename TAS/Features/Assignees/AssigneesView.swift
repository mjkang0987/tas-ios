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

    /// 재직 우선 → 이름 순.
    var sorted: [Assignee] {
        (state.value ?? []).sorted { lhs, rhs in
            let l = lhs.status == .retired ? 1 : 0
            let r = rhs.status == .retired ? 1 : 0
            if l != r { return l < r }
            return lhs.name < rhs.name
        }
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await service.fetchAssignees().assignees)
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

/// 담당자(디자이너) 목록 — 웹 설정 > `designer` 탭에 대응(읽기). 설정에서 push.
struct AssigneesView: View {
    @State private var viewModel = AssigneesViewModel()

    var body: some View {
        LoadableView(state: viewModel.state, loadingText: "담당자 불러오는 중…") { _ in
            List(viewModel.sorted) { AssigneeRow(assignee: $0) }
        }
        .navigationTitle("담당자")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }
}

private struct AssigneeRow: View {
    let assignee: Assignee

    private static let weekdayLabels = ["월", "화", "수", "목", "금", "토", "일"]

    var body: some View {
        HStack(spacing: 10) {
            ColorDot(color: Color(hex: assignee.color) ?? .gray, size: 10)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(assignee.name).font(.body.weight(.medium))
                    if let status = assignee.status { AssigneeStatusText(status: status) }
                }
                Text(scheduleSummary).font(.caption).foregroundStyle(.secondary)
                if let phone = assignee.phone, !phone.isEmpty {
                    Text(phone).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
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
