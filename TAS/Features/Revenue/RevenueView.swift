import SwiftUI
import Observation
import Charts

@MainActor
@Observable
final class RevenueViewModel {
    /// 집계 기간 — 월 단위 / 연 단위.
    enum Period: String, CaseIterable {
        case month = "월"
        case year = "년"
    }

    /// 웹 KPI 그리드(`RevenueKpiGrid`)의 5칸.
    enum MetricKey: String, CaseIterable, Identifiable {
        case sales, count, new, returning, paid
        var id: String { rawValue }

        var label: String {
            switch self {
            case .sales: return "총 매출"
            case .count: return "예약 건수"
            case .new: return "신규 고객 수"
            case .returning: return "재방문 고객 수"
            case .paid: return "결제완료"
            }
        }

        var detailTitle: String {
            switch self {
            case .sales: return "총 매출 상세"
            case .count: return "예약 건수 상세"
            case .new: return "신규 고객 상세"
            case .returning: return "재방문 고객 상세"
            case .paid: return "결제완료 상세"
            }
        }
    }

    /// **무엇을 탭했는지**. 목록 자체가 아니라 이 키를 들고 있어야
    /// 상세에서 예약을 취소·삭제한 뒤에도 목록이 다시 계산된다(탭 시점 스냅샷이면 남는다).
    enum DetailKey: Identifiable, Hashable {
        case metric(MetricKey)
        case assignee(Int?)
        /// 추세 차트의 한 칸 — 월 보기는 일(1…말일), 연 보기는 월(1…12).
        case trend(Int)

        var id: String {
            switch self {
            case .metric(let key): return "metric-\(key.rawValue)"
            case .assignee(let id): return "assignee-\(id.map(String.init) ?? "none")"
            case .trend(let index): return "trend-\(index)"
            }
        }
    }

    /// 탭한 영역이 열어 보여줄 목록 — 웹 `RevenueMetricModal` / `RevenueDailyDetailModal`.
    struct DetailLayer {
        enum Content {
            case reservations([Reservation])
            case customers([RevenueStats.CustomerVisit])
        }

        let title: String
        var subtitle: String? = nil
        /// 푸터 요약("12건 · 1,200,000원").
        let summary: String
        let content: Content
    }

    struct Data {
        var reservations: [Reservation]
        var assigneesById: [Int: Assignee]
        var customersById: [Int: Customer] = [:]
        var servicePriceByName: [String: Int]
        /// 서비스명 → hex. 드릴다운 목록의 시술 칩 색.
        var serviceColorMap: [String: String] = [:]
        /// 집계 기준이 된 매장 기준(KST) 날짜.
        var today: String = KST.dayKey.string(from: Date())
    }

    /// 추세 차트 한 점 — index는 일(1…말일) 또는 월(1…12).
    struct TrendPoint: Identifiable {
        let index: Int
        let total: Int
        var id: Int { index }
    }

    /// 한 번 훑어 만든 기간 집계 — KPI와 드릴다운이 같은 값을 쓰게 한 곳에서 만든다.
    struct Metrics {
        var total = 0
        var count = 0
        var paidTotal = 0
        var paidReservations: [Reservation] = []
        var newCustomers: [RevenueStats.CustomerVisit] = []
        var returningCustomers: [RevenueStats.CustomerVisit] = []
    }

    var state: Loadable<Data> = .idle
    var selectedDate = Date()
    var mode: RevenueStats.FilterMode = .completed
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

    /// 금액 — 웹 resolvePrice(price 우선, 없으면 카탈로그가).
    private func amount(_ r: Reservation, _ data: Data) -> Int {
        r.price ?? data.servicePriceByName[r.service] ?? 0
    }

    func amount(_ r: Reservation) -> Int {
        guard let data = state.value else { return r.price ?? 0 }
        return amount(r, data)
    }

    /// 기간과 무관한 전체 대상 예약 — 첫 방문일 판정에 쓴다.
    private var allTargets: [Reservation] {
        (state.value?.reservations ?? []).filter { RevenueStats.isTarget($0, mode: mode) }
    }

    /// 집계 기간 안의 대상 예약(날짜·시작시간 오름차순).
    var periodTargets: [Reservation] {
        let prefix = periodPrefix
        return RevenueStats.sortedChronologically(allTargets.filter { $0.date.hasPrefix(prefix) })
    }

    var metrics: Metrics {
        guard state.value != nil else { return Metrics() }
        let targets = periodTargets
        let visits = RevenueStats.customerVisits(periodTargets: targets, allTargets: allTargets)

        var result = Metrics()
        result.total = targets.reduce(0) { $0 + amount($1) }
        result.count = targets.count
        result.paidTotal = RevenueStats.paidTotal(targets) { self.amount($0) }
        result.paidReservations = targets.filter { RevenueStats.isPaidTarget($0) }
        result.newCustomers = visits.new
        result.returningCustomers = visits.returning
        return result
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
        guard state.value != nil else { return [] }
        let targets = periodTargets
        switch period {
        case .month:
            let days = daysInSelectedMonth
            var totals = Array(repeating: 0, count: days + 1)   // 1-indexed
            for r in targets {
                if let day = Self.datePart(r.date, at: 2), day >= 1, day <= days {
                    totals[day] += amount(r)
                }
            }
            return (1...days).map { TrendPoint(index: $0, total: totals[$0]) }
        case .year:
            var totals = Array(repeating: 0, count: 13)         // 1…12
            for r in targets {
                if let m = Self.datePart(r.date, at: 1), m >= 1, m <= 12 {
                    totals[m] += amount(r)
                }
            }
            return (1...12).map { TrendPoint(index: $0, total: totals[$0]) }
        }
    }

    private var daysInSelectedMonth: Int {
        let cal = KST.calendar
        let comps = cal.dateComponents([.year, .month], from: selectedDate)
        let first = cal.date(from: comps) ?? selectedDate
        return cal.range(of: .day, in: .month, for: first)?.count ?? 30
    }

    /// "YYYY-MM-DD"의 index번째 조각(0=년, 1=월, 2=일).
    private static func datePart(_ date: String, at index: Int) -> Int? {
        let parts = date.split(separator: "-")
        guard parts.count == 3 else { return nil }
        return Int(parts[index])
    }

    // MARK: - 드릴다운 목록 구성 (웹 RevenueMetricModal)

    /// 키 → 목록. **볼 때마다 다시 계산한다** — 상세에서 예약이 바뀌면 목록도 따라 바뀌어야 한다.
    func layer(for key: DetailKey) -> DetailLayer {
        switch key {
        case .metric(let metric): return metricLayer(metric)
        case .assignee(let assigneeId): return assigneeLayer(assigneeId: assigneeId)
        case .trend(let index): return trendLayer(index: index)
        }
    }

    /// 추세 차트에서 탭한 칸이 열 만한 것이 있는지 — 빈 날은 열지 않는다.
    /// (차트 탭 좌표가 축 밖으로 튀는 경우도 여기서 걸러진다.)
    func trendKey(index: Int) -> DetailKey? {
        guard let dateKey = trendDateKey(index: index) else { return nil }
        guard periodTargets.contains(where: { $0.date.hasPrefix(dateKey) }) else { return nil }
        return .trend(index)
    }

    func metricLayer(_ key: MetricKey) -> DetailLayer {
        let m = metrics
        switch key {
        case .sales:
            return DetailLayer(
                title: key.detailTitle,
                summary: Self.summary(count: m.count, total: m.total),
                content: .reservations(periodTargets)
            )
        case .count:
            return DetailLayer(
                title: key.detailTitle,
                summary: "\(m.count)건",
                content: .reservations(periodTargets)
            )
        case .new:
            return DetailLayer(
                title: key.detailTitle,
                subtitle: mode == .completed
                    ? "선택 기간 안에서 첫 예약완료가 발생한 고객 목록"
                    : "선택 기간 안에서 첫 예약이 발생한 고객 목록",
                summary: "\(m.newCustomers.count)명",
                content: .customers(m.newCustomers)
            )
        case .returning:
            return DetailLayer(
                title: key.detailTitle,
                subtitle: mode == .completed
                    ? "선택 기간 내 예약완료가 있고, 그 이전 예약완료 이력이 있는 고객 목록"
                    : "선택 기간 내 예약이 있고, 그 이전 예약 이력이 있는 고객 목록",
                summary: "\(m.returningCustomers.count)명",
                content: .customers(m.returningCustomers)
            )
        case .paid:
            return DetailLayer(
                title: key.detailTitle,
                summary: Self.summary(count: m.paidReservations.count, total: m.paidTotal),
                content: .reservations(m.paidReservations)
            )
        }
    }

    /// 담당자별 행 탭 — 웹 차트의 담당자 막대 클릭(`kind: 'assignee'`).
    func assigneeLayer(assigneeId: Int?) -> DetailLayer {
        let items = periodTargets.filter { $0.assigneeId == assigneeId }
        let name = assigneeId.flatMap { state.value?.assigneesById[$0]?.name } ?? "미지정"
        return DetailLayer(
            title: "\(name) 매출 상세",
            summary: Self.summary(count: items.count, total: items.reduce(0) { $0 + amount($1) }),
            content: .reservations(items)
        )
    }

    /// 추세 차트 막대 탭 — 웹 차트의 날짜 점 클릭(`kind: 'date'`).
    /// 월 보기는 그 날짜, 연 보기는 그 달의 예약을 연다.
    func trendLayer(index: Int) -> DetailLayer {
        let dateKey = trendDateKey(index: index)
        let items = dateKey.map { key in periodTargets.filter { $0.date.hasPrefix(key) } } ?? []
        return DetailLayer(
            title: "\(dateKey ?? periodLabel) 매출 상세",
            summary: Self.summary(count: items.count, total: items.reduce(0) { $0 + amount($1) }),
            content: .reservations(items)
        )
    }

    /// 추세 차트의 index번째 칸이 가리키는 날짜 프리픽스("YYYY-MM-DD" 또는 "YYYY-MM").
    /// 축 범위를 벗어나면 nil.
    private func trendDateKey(index: Int) -> String? {
        let upperBound = period == .month ? daysInSelectedMonth : 12
        guard index >= 1, index <= upperBound else { return nil }
        return "\(periodPrefix)-\(String(format: "%02d", index))"
    }

    /// 웹 모달 푸터와 같은 형식.
    private static func summary(count: Int, total: Int) -> String {
        "\(count)건 · \(formatWon(total))"
    }

    // MARK: - 드릴다운에서 쓰는 해석기

    func assignee(_ id: Int?) -> Assignee? { id.flatMap { state.value?.assigneesById[$0] } }
    var assigneesById: [Int: Assignee] { state.value?.assigneesById ?? [:] }
    func customer(_ id: Int) -> Customer? { state.value?.customersById[id] }
    var serviceColorMap: [String: String] { state.value?.serviceColorMap ?? [:] }
    var today: String { state.value?.today ?? KST.dayKey.string(from: Date()) }

    /// 고객 상세로 내려갈 때 필요한 그 고객의 예약(상태 무관 — 고객 화면과 같은 기준).
    func reservations(ofCustomer id: Int) -> [Reservation] {
        (state.value?.reservations ?? []).filter { $0.customerId == id }
    }

    func customerStats(_ id: Int) -> CustomerStats.Summary {
        CustomerStats.summarize(reservations(ofCustomer: id), today: today)
    }

    func customerGroups(_ id: Int) -> [CustomerStats.Group] {
        CustomerStats.groups(reservations(ofCustomer: id), today: today)
    }

    func load() async {
        state = .loading
        do {
            async let reservations = service.fetchReservations()
            async let assignees = service.fetchAssignees()
            async let services = service.fetchServices()
            async let customers = service.fetchCustomers()
            let (res, asg, svc, cus) = try await (reservations, assignees, services, customers)

            let assigneesById = Dictionary(asg.assignees.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let customersById = Dictionary(cus.customers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var prices: [String: Int] = [:]
            for item in svc.services { prices[item.name] = item.price }

            state = .loaded(Data(
                reservations: res.reservations,
                assigneesById: assigneesById,
                customersById: customersById,
                servicePriceByName: prices,
                serviceColorMap: ServiceColor.buildServiceColorMap(
                    catalog: svc.services,
                    storeMap: svc.categoryBaseColors
                ),
                today: KST.dayKey.string(from: Date())
            ))
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

/// 매출 요약 — 웹 설정 > `revenue` 탭에 대응. 월/년 단위 + KPI + 추세 차트 + 담당자별.
/// 웹처럼 **집계된 숫자를 누르면 그 근거가 되는 예약/고객 목록**이 열린다.
struct RevenueView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel = RevenueViewModel()
    /// 열려 있는 드릴다운이 **무엇인지**만 들고 있는다 — 목록 자체를 들면
    /// 상세에서 예약을 취소·삭제해도 그 행이 그대로 남는다.
    @State private var detailKey: RevenueViewModel.DetailKey?

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
                        ForEach(RevenueStats.FilterMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                metricSection

                Section(viewModel.period == .month ? "일별 매출" : "월별 매출") {
                    RevenueTrendChart(
                        points: viewModel.trend,
                        unitLabel: viewModel.period == .month ? "일" : "월",
                        onSelect: { index in detailKey = viewModel.trendKey(index: index) }
                    )
                    .frame(height: 180)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }

                let byAssignee = viewModel.byAssignee
                if !byAssignee.isEmpty {
                    Section("담당자별") {
                        ForEach(Array(byAssignee.enumerated()), id: \.offset) { item in
                            Button {
                                detailKey = .assignee(item.element.assignee?.id)
                            } label: {
                                AssigneeRevenueRow(row: item.element)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("매출")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detailKey) { key in
            RevenueDetailListView(
                key: key,
                viewModel: viewModel,
                pointRate: session.currentStore?.effectivePointRate ?? 0,
                pointsEnabled: session.currentStore?.usePointSystem ?? false,
                pointSettings: session.currentStore?.pointSettings,
                onChanged: { await viewModel.load() }
            )
        }
        .task { await viewModel.load() }
    }

    /// 웹 `RevenueKpiGrid` — 5칸 모두 탭하면 근거 목록이 열린다.
    private var metricSection: some View {
        let metrics = viewModel.metrics
        return Section("합계") {
            metricRow(.sales, value: formatWon(metrics.total))
            metricRow(.count, value: "\(metrics.count)건")
            metricRow(.new, value: "\(metrics.newCustomers.count)명")
            metricRow(.returning, value: "\(metrics.returningCustomers.count)명")
            metricRow(.paid, value: formatWon(metrics.paidTotal))
        }
    }

    private func metricRow(_ key: RevenueViewModel.MetricKey, value: String) -> some View {
        Button {
            detailKey = .metric(key)
        } label: {
            HStack {
                Text(key.label)
                Spacer()
                Text(value).foregroundStyle(.secondary).monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("\(key.label) 상세 목록 열기")
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
/// 막대를 탭하면 그 날(달)의 예약 목록을 연다 — 웹 차트 점 클릭에 대응.
private struct RevenueTrendChart: View {
    let points: [RevenueViewModel.TrendPoint]
    let unitLabel: String
    let onSelect: (Int) -> Void

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
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let x = location.x - geometry[plotFrame].origin.x
                            guard let raw: Double = proxy.value(atX: x) else { return }
                            onSelect(Int(raw.rounded()))
                        }
                }
            }
            .accessibilityLabel("\(unitLabel)별 매출 추세. 막대를 탭하면 상세 목록이 열립니다.")
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
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
