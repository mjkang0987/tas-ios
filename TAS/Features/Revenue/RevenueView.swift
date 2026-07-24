import SwiftUI
import Observation
import Charts

@MainActor
@Observable
final class RevenueViewModel {
    enum Mode: String, CaseIterable {
        case completed = "완료"
        case booked = "예약"
    }

    /// 집계 기간 — 월 단위 / 연 단위.
    enum Period: String, CaseIterable {
        case month = "월"
        case year = "년"
    }

    struct Data {
        var reservations: [Reservation]
        var assigneesById: [Int: Assignee]
        var servicePriceByName: [String: Int]
    }

    /// 추세 차트 한 점 — index는 일(1…말일) 또는 월(1…12).
    struct TrendPoint: Identifiable {
        let index: Int
        let total: Int
        var id: Int { index }
    }

    var state: Loadable<Data> = .idle
    var selectedDate = Date()
    var mode: Mode = .completed
    var period: Period = .month

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    // MARK: - 기간 라벨·이동

    var periodLabel: String {
        switch period {
        case .month: return KST.monthLabel.string(from: selectedDate)
        case .year: return "\(KST.calendar.component(.year, from: selectedDate))년"
        }
    }

    /// date("YYYY-MM-DD") 필터용 프리픽스 — 월="YYYY-MM", 연="YYYY".
    private var periodPrefix: String {
        switch period {
        case .month: return KST.monthKey.string(from: selectedDate)
        case .year: return String(format: "%04d", KST.calendar.component(.year, from: selectedDate))
        }
    }

    func shift(_ delta: Int) {
        let component: Calendar.Component = period == .month ? .month : .year
        if let d = KST.calendar.date(byAdding: component, value: delta, to: selectedDate) {
            selectedDate = d
        }
    }

    // MARK: - 집계

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

    private var periodTargets: [Reservation] {
        guard let data = state.value else { return [] }
        let prefix = periodPrefix
        return data.reservations.filter { $0.date.hasPrefix(prefix) && isTarget($0) }
    }

    var summary: (total: Int, count: Int) {
        guard let data = state.value else { return (0, 0) }
        let items = periodTargets
        return (items.reduce(0) { $0 + amount($1, data) }, items.count)
    }

    var byAssignee: [(assignee: Assignee?, total: Int, count: Int)] {
        guard let data = state.value else { return [] }
        var groups: [Int?: (total: Int, count: Int)] = [:]
        for r in periodTargets {
            let cur = groups[r.assigneeId] ?? (0, 0)
            groups[r.assigneeId] = (cur.total + amount(r, data), cur.count + 1)
        }
        return groups
            .map { key, val in (key.flatMap { data.assigneesById[$0] }, val.total, val.count) }
            .sorted { $0.1 > $1.1 }
    }

    /// 추세: 월=일별(1…말일), 연=월별(1…12). 값이 0인 구간도 포함해 축이 전체 기간을 덮게 한다.
    var trend: [TrendPoint] {
        guard let data = state.value else { return [] }
        switch period {
        case .month:
            let cal = KST.calendar
            let comps = cal.dateComponents([.year, .month], from: selectedDate)
            let first = cal.date(from: comps) ?? selectedDate
            let days = cal.range(of: .day, in: .month, for: first)?.count ?? 30
            var totals = Array(repeating: 0, count: days + 1)   // 1-indexed
            for r in periodTargets {
                let parts = r.date.split(separator: "-")
                if parts.count == 3, let day = Int(parts[2]), day >= 1, day <= days {
                    totals[day] += amount(r, data)
                }
            }
            return (1...days).map { TrendPoint(index: $0, total: totals[$0]) }
        case .year:
            var totals = Array(repeating: 0, count: 13)         // 1…12
            for r in periodTargets {
                let parts = r.date.split(separator: "-")
                if parts.count == 3, let m = Int(parts[1]), m >= 1, m <= 12 {
                    totals[m] += amount(r, data)
                }
            }
            return (1...12).map { TrendPoint(index: $0, total: totals[$0]) }
        }
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

/// 매출 요약 — 웹 설정 > `revenue` 탭에 대응(읽기). 월/년 단위 + 추세 차트 + 담당자별.
struct RevenueView: View {
    @State private var viewModel = RevenueViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel
        return LoadableView(state: viewModel.state, loadingText: "매출 불러오는 중…") { _ in
            List {
                Section {
                    Picker("기간", selection: $viewModel.period) {
                        ForEach(RevenueViewModel.Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    periodNav
                    Picker("기준", selection: $viewModel.mode) {
                        ForEach(RevenueViewModel.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("합계") {
                    LabeledContent("매출", value: formatWon(viewModel.summary.total))
                    LabeledContent("건수", value: "\(viewModel.summary.count)건")
                }

                Section(viewModel.period == .month ? "일별 매출" : "월별 매출") {
                    RevenueTrendChart(
                        points: viewModel.trend,
                        unitLabel: viewModel.period == .month ? "일" : "월"
                    )
                    .frame(height: 180)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
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

    private var periodNav: some View {
        HStack {
            Button { viewModel.shift(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(viewModel.periodLabel).font(.headline).monospacedDigit()
            Spacer()
            Button { viewModel.shift(1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.borderless)
    }
}

/// 매출 추세 막대 차트(단일 시리즈, accent color). 월=일별 / 연=월별.
private struct RevenueTrendChart: View {
    let points: [RevenueViewModel.TrendPoint]
    let unitLabel: String

    var body: some View {
        if points.isEmpty || points.allSatisfy({ $0.total == 0 }) {
            Text("매출 없음")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            Chart(points) { point in
                BarMark(
                    x: .value(unitLabel, point.index),
                    y: .value("매출", point.total)
                )
                .foregroundStyle(Color.accentColor.gradient)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let i = value.as(Int.self) { Text("\(i)") }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let won = value.as(Int.self) { Text(Self.compact(won)) }
                    }
                }
            }
        }
    }

    /// 축 라벨용 금액 축약(만 단위).
    private static func compact(_ won: Int) -> String {
        won >= 10_000 ? "\(won / 10_000)만" : "\(won)"
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
