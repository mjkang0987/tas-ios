import SwiftUI
import Observation

@MainActor
@Observable
final class RevenueViewModel {
    enum Mode: String, CaseIterable {
        case completed = "완료"
        case booked = "예약"
    }

    struct Data {
        var reservations: [Reservation]
        var assigneesById: [Int: Assignee]
        var servicePriceByName: [String: Int]
    }

    var state: Loadable<Data> = .idle
    var selectedMonth = Date()
    var mode: Mode = .completed

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    var monthLabel: String { KST.monthLabel.string(from: selectedMonth) }
    private var monthPrefix: String { KST.monthKey.string(from: selectedMonth) }

    func shiftMonth(_ delta: Int) {
        if let d = KST.calendar.date(byAdding: .month, value: delta, to: selectedMonth) {
            selectedMonth = d
        }
    }

    /// 매출 대상 판정 — 웹 revenue.ts.
    private func isTarget(_ r: Reservation) -> Bool {
        switch mode {
        case .completed:
            return r.status == .completed
        case .booked:
            return r.status != .cancelled && r.status != .noshow && r.status != .requested
        }
    }

    /// 금액 — 웹 resolvePrice(price 우선, 없으면 카탈로그가).
    private func amount(_ r: Reservation, _ data: Data) -> Int {
        r.price ?? data.servicePriceByName[r.service] ?? 0
    }

    private var monthTargets: [Reservation] {
        guard let data = state.value else { return [] }
        let prefix = monthPrefix
        return data.reservations.filter { $0.date.hasPrefix(prefix) && isTarget($0) }
    }

    var summary: (total: Int, count: Int) {
        guard let data = state.value else { return (0, 0) }
        let items = monthTargets
        return (items.reduce(0) { $0 + amount($1, data) }, items.count)
    }

    var byAssignee: [(assignee: Assignee?, total: Int, count: Int)] {
        guard let data = state.value else { return [] }
        var groups: [Int?: (total: Int, count: Int)] = [:]
        for r in monthTargets {
            let cur = groups[r.assigneeId] ?? (0, 0)
            groups[r.assigneeId] = (cur.total + amount(r, data), cur.count + 1)
        }
        return groups
            .map { key, val in (key.flatMap { data.assigneesById[$0] }, val.total, val.count) }
            .sorted { $0.1 > $1.1 }
    }

    func load() async {
        state = .loading
        do {
            async let reservations = service.fetchReservations()
            async let assignees = service.fetchAssignees()
            async let services = service.fetchServices()
            let (res, asg, svc) = try await (reservations, assignees, services)

            let assigneesById = Dictionary(asg.assignees.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var prices: [String: Int] = [:]
            for item in svc.services { prices[item.name] = item.price }

            state = .loaded(Data(reservations: res.reservations, assigneesById: assigneesById, servicePriceByName: prices))
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

/// 매출 요약 — 웹 설정 > `revenue` 탭에 대응(읽기). 월 단위 + 담당자별.
struct RevenueView: View {
    @State private var viewModel = RevenueViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel
        return LoadableView(state: viewModel.state, loadingText: "매출 불러오는 중…") { _ in
            List {
                Section {
                    monthNav
                    Picker("기준", selection: $viewModel.mode) {
                        ForEach(RevenueViewModel.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("합계") {
                    LabeledContent("매출", value: formatWon(viewModel.summary.total))
                    LabeledContent("건수", value: "\(viewModel.summary.count)건")
                }

                if !viewModel.byAssignee.isEmpty {
                    Section("담당자별") {
                        ForEach(Array(viewModel.byAssignee.enumerated()), id: \.offset) { item in
                            AssigneeRevenueRow(row: item.element)
                        }
                    }
                }
            }
        }
        .navigationTitle("매출")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    private var monthNav: some View {
        HStack {
            Button { viewModel.shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(viewModel.monthLabel).font(.headline).monospacedDigit()
            Spacer()
            Button { viewModel.shiftMonth(1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.borderless)
    }
}

private struct AssigneeRevenueRow: View {
    let row: (assignee: Assignee?, total: Int, count: Int)

    var body: some View {
        HStack {
            ColorDot(color: Color(hex: row.assignee?.color) ?? .gray)
            Text(row.assignee?.name ?? "미지정")
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatWon(row.total)).font(.subheadline.weight(.semibold))
                Text("\(row.count)건").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
