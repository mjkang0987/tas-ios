import SwiftUI
import Observation
import Charts

@MainActor
@Observable
final class RevenueViewModel {
    /// 집계 기간 — 월 단위 / 연 단위 / 직접 고른 기간(웹·안드로이드 `RevenueFilters` 의 시작일·종료일).
    enum Period: String, CaseIterable {
        case month = "월"
        case year = "년"
        case range = "기간"
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
        /// 추세 차트의 한 칸 — 월 보기는 일(1…말일), 연 보기는 월(1…12), 기간 보기는 시작일부터 n번째 날.
        case trend(Int)
        /// 일별 목록의 한 날("YYYY-MM-DD") — 웹 `RevenueDailyList` 의 날짜 행.
        case day(String)

        var id: String {
            switch self {
            case .metric(let key): return "metric-\(key.rawValue)"
            case .assignee(let id): return "assignee-\(id.map(String.init) ?? "none")"
            case .trend(let index): return "trend-\(index)"
            case .day(let key): return "day-\(key)"
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
        /// 그 칸에 든 충전 매출 — 예약 목록 아래에 따로 보인다(웹 `StyledSaleItem`).
        var sales: [RevenueStats.StoreSale] = []
    }

    /// 일별 목록 한 줄 — 예약 또는 충전이 있는 날만.
    struct DayRow: Identifiable {
        let date: String
        let count: Int          // 예약 건수(충전은 안 센다 — 웹과 같다)
        let total: Int          // 예약 매출 + 충전
        var id: String { date }
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
        /// 총 매출 중 충전 매출 — '회원권·충전 n원 포함'.
        var salesTotal = 0
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
    /// 담당자 필터 — nil 이면 전체(웹 `RevenueFilters` 담당자 칩).
    var assigneeId: Int?
    /// '기간' 보기의 시작·종료(시작이 더 늦어도 그대로 두고 계산만 앞뒤를 바꾼다 — 웹과 같다). 기본 이번 달 1일 ~ 오늘.
    var rangeStart: Date = KST.calendar.date(from: KST.calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    var rangeEnd = Date()

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    // MARK: - 기간 라벨·이동

    var periodLabel: String {
        switch period {
        case .month: return KST.monthLabel.string(from: selectedDate)
        case .year: return "\(KST.calendar.component(.year, from: selectedDate))년"
        case .range: return "\(bounds.from) ~ \(bounds.to)"
        }
    }

    /// date("YYYY-MM-DD") 필터용 프리픽스 — 월="YYYY-MM", 연="YYYY". 기간 보기엔 없다.
    private var periodPrefix: String {
        switch period {
        case .month: return KST.monthKey.string(from: selectedDate)
        case .year, .range: return String(format: "%04d", KST.calendar.component(.year, from: selectedDate))
        }
    }

    /// 집계 날짜 범위(양 끝 포함) — 날짜 키 문자열 비교로 거른다.
    var bounds: (from: String, to: String) {
        switch period {
        case .month: return ("\(periodPrefix)-01", "\(periodPrefix)-31")
        case .year: return ("\(periodPrefix)-01-01", "\(periodPrefix)-12-31")
        case .range:
            let a = KST.dayKey.string(from: rangeStart), b = KST.dayKey.string(from: rangeEnd)
            return (min(a, b), max(a, b))
        }
    }

    func shift(_ delta: Int) {
        switch period {
        case .range:
            (rangeStart, rangeEnd) = RevenueStats.moveRange(rangeStart, rangeEnd, forward: delta > 0, today: Date())
        case .month, .year:
            let component: Calendar.Component = period == .month ? .month : .year
            if let d = KST.calendar.date(byAdding: component, value: delta, to: selectedDate) {
                selectedDate = d
            }
        }
    }

    func applyQuick(_ q: RevenueStats.QuickRange) {
        (rangeStart, rangeEnd) = RevenueStats.quickRange(q, today: Date())
    }

    /// 날짜를 직접 고른 뒤 — 365일을 넘으면 당긴다.
    func clampRange() {
        let (s, e) = RevenueStats.clampRange(rangeStart, rangeEnd)
        if s != rangeStart { rangeStart = s }
        if e != rangeEnd { rangeEnd = e }
    }

    var quickRange: RevenueStats.QuickRange? { RevenueStats.quickRangeOf(rangeStart, rangeEnd, today: Date()) }

    /// 필터 칩용 담당자(이름 순 — 캘린더 필터와 같다).
    var assignees: [Assignee] { (state.value?.assigneesById.values).map { $0.sorted { $0.name < $1.name } } ?? [] }

    // MARK: - 집계

    /// 예약 매출 — 웹 `resolveRevenue`(예약가 또는 서비스별 가격 합 − 할인·적립금·회원권 결제분).
    func amount(_ r: Reservation) -> Int {
        RevenueStats.revenue(r, price: RevenueStats.price(r, priceByName: state.value?.servicePriceByName ?? [:]))
    }

    /// 기간과 무관한 전체 대상 예약 — 첫 방문일 판정에 쓴다. 담당자를 고르면 그 담당자 예약만(웹 `isRevenueTarget`).
    private var allTargets: [Reservation] {
        (state.value?.reservations ?? []).filter {
            RevenueStats.isTarget($0, mode: mode) && (assigneeId == nil || $0.assigneeId == assigneeId)
        }
    }

    /// 기간 안 충전 매출 — 담당자가 없는 매출이라 담당자를 고르면 뺀다(웹과 같다).
    var periodSales: [RevenueStats.StoreSale] {
        guard assigneeId == nil, let data = state.value else { return [] }
        let (from, to) = bounds
        return RevenueStats.storeSales(Array(data.customersById.values))
            .filter { $0.date >= from && $0.date <= to }
            .sorted { $0.date < $1.date }
    }

    /// 집계 기간 안의 대상 예약(날짜·시작시간 오름차순).
    var periodTargets: [Reservation] { targetsInPeriod(of: allTargets) }

    /// 이름을 프로퍼티와 겹치지 않게 둔다 — 같은 이름이면 재귀 호출로 읽힌다.
    private func targetsInPeriod(of all: [Reservation]) -> [Reservation] {
        let (from, to) = bounds
        return RevenueStats.sortedChronologically(all.filter { $0.date >= from && $0.date <= to })
    }

    var metrics: Metrics {
        guard state.value != nil else { return Metrics() }
        // 전체 대상은 한 번만 훑는다 — `periodTargets`가 다시 훑게 두면 렌더마다 두 배로 돈다.
        let all = allTargets
        let targets = targetsInPeriod(of: all)
        let visits = RevenueStats.customerVisits(periodTargets: targets, allTargets: all)

        let sales = periodSales
        var result = Metrics()
        result.salesTotal = sales.reduce(0) { $0 + $1.amount }
        result.total = targets.reduce(0) { $0 + amount($1) } + result.salesTotal
        result.count = targets.count
        // 충전은 결제수단이 있는 것만 결제완료로 친다(웹 `if (sale.method)`)
        result.paidTotal = RevenueStats.paidTotal(targets) { self.amount($0) }
            + sales.filter { $0.method != nil }.reduce(0) { $0 + $1.amount }
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
            groups[r.assigneeId] = (cur.total + amount(r), cur.count + 1)
        }
        return groups
            .map { key, val in (key.flatMap { data.assigneesById[$0] }, val.total, val.count) }
            .sorted { $0.1 > $1.1 }
    }

    /// 추세: 월=일별(1…말일), 연=월별(1…12), 기간=시작일부터 하루씩. 값이 0인 구간도 포함해 축이 전체 기간을 덮게 한다.
    /// 충전 매출도 그 날(달)에 더한다.
    var trend: [TrendPoint] {
        guard state.value != nil else { return [] }
        let count = trendCount
        var totals = Array(repeating: 0, count: count + 1)   // 1-indexed
        func add(_ date: String, _ value: Int) {
            if let i = trendIndex(of: date), i >= 1, i <= count { totals[i] += value }
        }
        for r in periodTargets { add(r.date, amount(r)) }
        for sale in periodSales { add(sale.date, sale.amount) }
        return (1...max(count, 1)).map { TrendPoint(index: $0, total: totals.indices.contains($0) ? totals[$0] : 0) }
    }

    /// 차트 칸 수 — 월: 말일, 연: 12, 기간: 일수.
    private var trendCount: Int {
        switch period {
        case .month: return daysInSelectedMonth
        case .year: return 12
        case .range:
            let (from, to) = bounds
            guard let a = KST.dayKey.date(from: from), let b = KST.dayKey.date(from: to) else { return 1 }
            return RevenueStats.days(from: a, to: b) + 1
        }
    }

    /// 날짜("YYYY-MM-DD") → 차트 칸 번호.
    private func trendIndex(of date: String) -> Int? {
        switch period {
        case .month: return Self.datePart(date, at: 2)
        case .year: return Self.datePart(date, at: 1)
        case .range:
            guard let a = KST.dayKey.date(from: bounds.from), let d = KST.dayKey.date(from: date) else { return nil }
            return RevenueStats.days(from: a, to: d) + 1
        }
    }

    /// 일별 목록 — 예약이나 충전이 있는 날만, 최신 날짜부터(웹 `RevenueDailyList`).
    var dailyRows: [DayRow] {
        var byDate: [String: (count: Int, total: Int)] = [:]
        for r in periodTargets {
            let cur = byDate[r.date] ?? (0, 0)
            byDate[r.date] = (cur.count + 1, cur.total + amount(r))
        }
        for sale in periodSales {
            let cur = byDate[sale.date] ?? (0, 0)
            byDate[sale.date] = (cur.count, cur.total + sale.amount)
        }
        return byDate.map { DayRow(date: $0.key, count: $0.value.count, total: $0.value.total) }
            .sorted { $0.date > $1.date }
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
        case .day(let key): return dayLayer(key)
        }
    }

    /// 추세 차트에서 탭한 칸이 열 만한 것이 있는지 — 빈 날은 열지 않는다.
    /// (차트 탭 좌표가 축 밖으로 튀는 경우도 여기서 걸러진다.)
    func trendKey(index: Int) -> DetailKey? {
        guard let dateKey = trendDateKey(index: index) else { return nil }
        // 있는지만 보면 되므로 정렬까지 돌지 않는다.
        guard allTargets.contains(where: { $0.date.hasPrefix(dateKey) })
                || periodSales.contains(where: { $0.date.hasPrefix(dateKey) }) else { return nil }
        return .trend(index)
    }

    func metricLayer(_ key: MetricKey) -> DetailLayer {
        let m = metrics
        switch key {
        case .sales:
            return DetailLayer(
                title: key.detailTitle,
                summary: Self.summary(count: m.count, total: m.total),
                content: .reservations(periodTargets),
                sales: periodSales
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
                content: .reservations(m.paidReservations),
                sales: periodSales.filter { $0.method != nil }
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
        guard let dateKey = trendDateKey(index: index) else {
            return DetailLayer(title: "\(periodLabel) 매출 상세", summary: Self.summary(count: 0, total: 0), content: .reservations([]))
        }
        return dayLayer(dateKey)
    }

    /// 한 날(또는 연 보기의 한 달) — 그 칸의 예약 + 충전. 추세 막대·일별 목록이 같이 쓴다.
    func dayLayer(_ dateKey: String) -> DetailLayer {
        let items = periodTargets.filter { $0.date.hasPrefix(dateKey) }
        let sales = periodSales.filter { $0.date.hasPrefix(dateKey) }
        let total = items.reduce(0) { $0 + amount($1) } + sales.reduce(0) { $0 + $1.amount }
        return DetailLayer(
            title: "\(dateKey) 매출 상세",
            summary: Self.summary(count: items.count, total: total),
            content: .reservations(items),
            sales: sales
        )
    }

    /// 추세 차트의 index번째 칸이 가리키는 날짜 프리픽스("YYYY-MM-DD" 또는 "YYYY-MM").
    /// 축 범위를 벗어나면 nil.
    private func trendDateKey(index: Int) -> String? {
        guard index >= 1, index <= trendCount else { return nil }
        switch period {
        case .month, .year: return "\(periodPrefix)-\(String(format: "%02d", index))"
        case .range:
            guard let from = KST.dayKey.date(from: bounds.from),
                  let d = KST.calendar.date(byAdding: .day, value: index - 1, to: from) else { return nil }
            return KST.dayKey.string(from: d)
        }
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

    /// 상세 레이어(`DetailSheet`)에 넘길 데이터 — 마지막으로 불러온 값(다시 불러오는 동안에도 남긴다).
    private(set) var detailData: DetailData?
    var today: String { state.value?.today ?? KST.dayKey.string(from: Date()) }

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
            let serviceColorMap = ServiceColor.buildServiceColorMap(catalog: svc.services, storeMap: svc.categoryBaseColors)

            state = .loaded(Data(
                reservations: res.reservations,
                assigneesById: assigneesById,
                customersById: customersById,
                servicePriceByName: prices,
                serviceColorMap: serviceColorMap,
                today: KST.dayKey.string(from: Date())
            ))
            detailData = DetailData(reservations: res.reservations, customersById: customersById, assigneesById: assigneesById,
                                    services: svc.services, serviceColorMap: serviceColorMap, history: res.history ?? [])
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

    // 탭 루트라 자기 NavigationStack 을 갖는다(다른 탭 루트 CalendarView·CustomersView·
    // SettingsView 와 같은 형태). 예전엔 설정에서 push 되던 화면이라 부모 스택에 얹혀 있었다.
    var body: some View {
        NavigationStack { content }
            // 다른 탭 루트(CalendarView·CustomersView)와 같이 스택 **바깥**에 붙인다.
            // 안쪽에 두면 나중에 push 목적지가 생겼을 때 루트가 사라지며 task 가 취소된다.
            .task { await viewModel.load() }
    }

    private var content: some View {
        @Bindable var viewModel = viewModel
        return LoadableView(state: viewModel.state, loadingText: "매출 불러오는 중…") { _ in
            List {
                Section {
                    Picker("기간", selection: $viewModel.period) {
                        ForEach(RevenueViewModel.Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if viewModel.period == .range { rangeControls } else { periodNav }
                    Picker("기준", selection: $viewModel.mode) {
                        ForEach(RevenueStats.FilterMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    assigneeChips
                }

                metricSection

                Section(viewModel.period == .year ? "월별 매출" : "일별 매출") {
                    RevenueTrendChart(
                        points: viewModel.trend,
                        unitLabel: viewModel.period == .year ? "월" : "일",
                        label: trendLabel,
                        onSelect: { index in detailKey = viewModel.trendKey(index: index) }
                    )
                    .frame(height: 180)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }

                // 웹·안드로이드 `RevenueDailyList` — 예약·충전이 있는 날만, 최신부터. 누르면 그날 예약·충전 목록.
                Section("일별 목록") {
                    let rows = viewModel.dailyRows
                    if rows.isEmpty {
                        Text("등록된 데이터가 없습니다").font(.footnote).foregroundStyle(Color.textSecondary)
                    }
                    ForEach(rows) { row in
                        Button { detailKey = .day(row.date) } label: { DailyRevenueRow(row: row) }
                            .buttonStyle(.plain)
                            .accessibilityHint("그날 매출 상세 열기")
                    }
                }

                let byAssignee = viewModel.byAssignee
                if !byAssignee.isEmpty {
                    Section("\(session.labels.assignee)별") {
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
        // 탭 루트라 @State 뷰모델이 앱 수명 내내 산다 — 로드가 실패하면 .task 가 다시 돌지
        // 않아 앱을 껐다 켜야 복구된다. 다른 탭 루트 둘과 같이 당겨서 새로고침을 연다.
        .refreshable { await viewModel.load() }
        .navigationTitle("매출")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detailKey) { key in
            RevenueDetailListView(
                key: key,
                viewModel: viewModel,
                onChanged: { await viewModel.load() }
            )
        }
    }

    /// 웹 `RevenueKpiGrid` — 5칸 모두 탭하면 근거 목록이 열린다.
    private var metricSection: some View {
        let metrics = viewModel.metrics
        return Section("합계") {
            metricRow(.sales, value: formatWon(metrics.total),
                      note: metrics.salesTotal > 0 ? "회원권·충전 \(formatWon(metrics.salesTotal)) 포함" : nil)
            metricRow(.count, value: "\(metrics.count)건")
            metricRow(.new, value: "\(metrics.newCustomers.count)명")
            metricRow(.returning, value: "\(metrics.returningCustomers.count)명")
            metricRow(.paid, value: formatWon(metrics.paidTotal))
        }
    }

    private func metricRow(_ key: RevenueViewModel.MetricKey, value: String, note: String? = nil) -> some View {
        Button {
            detailKey = .metric(key)
        } label: {
            HStack {
                Text(key.label)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value).foregroundStyle(Color.textSecondary).monospacedDigit()
                    if let note { Text(note).font(.caption2).foregroundStyle(Color.textSecondary) }
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("\(key.label) 상세 목록 열기")
    }

    /// '기간' — 빠른 선택(오늘·7일·30일) + 시작일·종료일 + 앞뒤 이동(웹 `RevenueFilters`).
    @ViewBuilder private var rangeControls: some View {
        @Bindable var viewModel = viewModel
        HStack(spacing: 8) {
            ForEach(RevenueStats.QuickRange.allCases, id: \.self) { q in
                FilterChip(label: q.rawValue, isSelected: viewModel.quickRange == q) { viewModel.applyQuick(q) }
            }
        }
        HStack(spacing: 4) {
            Button { viewModel.shift(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("이전 기간")
            DatePicker("시작일", selection: $viewModel.rangeStart, displayedComponents: .date).labelsHidden()
            Text("~").foregroundStyle(Color.textSecondary)
            DatePicker("종료일", selection: $viewModel.rangeEnd, displayedComponents: .date).labelsHidden()
            Spacer(minLength: 0)
            Button { viewModel.shift(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("다음 기간")
        }
        .buttonStyle(.borderless)
        .onChange(of: viewModel.rangeStart) { _, _ in viewModel.clampRange() }
        .onChange(of: viewModel.rangeEnd) { _, _ in viewModel.clampRange() }
    }

    /// 담당자 필터 — 전체 + 담당자(캘린더 필터와 같은 칩).
    @ViewBuilder private var assigneeChips: some View {
        let assignees = viewModel.assignees
        if !assignees.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(label: "전체", isSelected: viewModel.assigneeId == nil) { viewModel.assigneeId = nil }
                    ForEach(assignees) { a in
                        FilterChip(label: a.name, color: Color(hex: a.color), isSelected: viewModel.assigneeId == a.id) {
                            viewModel.assigneeId = a.id
                        }
                    }
                }
            }
        }
    }

    /// 차트 칸 이름 — 기간 보기는 실제 날짜(M/d), 아니면 숫자.
    private func trendLabel(_ index: Int) -> String {
        guard viewModel.period == .range,
              let from = KST.dayKey.date(from: viewModel.bounds.from),
              let d = KST.calendar.date(byAdding: .day, value: index - 1, to: from) else { return "\(index)" }
        let c = KST.calendar.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    private var periodNav: some View {
        HStack {
            Button { viewModel.shift(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(viewModel.periodLabel).font(.tasTitle).monospacedDigit()
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
    var label: (Int) -> String = { "\($0)" }
    let onSelect: (Int) -> Void

    var body: some View {
        if points.isEmpty || points.allSatisfy({ $0.total == 0 }) {
            Text("매출 없음")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            Chart(points) { point in
                BarMark(
                    x: .value(unitLabel, point.index),
                    y: .value("매출", point.total)
                )
                .foregroundStyle(Color.accentColor.gradient)
                // 막대마다 접근성 요소를 만들어 VoiceOver 로 값을 읽을 수 있게 한다.
                // (탭으로 여는 상세는 아직 제스처 전용이다 — plan.md P7 잔여 작업)
                .accessibilityLabel(label(point.index) == "\(point.index)" ? "\(point.index)\(unitLabel)" : label(point.index))
                .accessibilityValue(formatWon(point.total))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let i = value.as(Int.self) { Text(label(i)) }
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
        }
    }

    /// 축 라벨용 금액 축약(만 단위).
    private static func compact(_ won: Int) -> String {
        won >= 10_000 ? "\(won / 10_000)만" : "\(won)"
    }
}

/// 일별 목록 한 줄 — 날짜(요일) · 건수 · 금액.
private struct DailyRevenueRow: View {
    let row: RevenueViewModel.DayRow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateLabel).font(.tasBody.weight(.semibold))
                Text(yearLabel).font(.caption2).foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Text("\(row.count)건").font(.caption).foregroundStyle(Color.textSecondary)
            Text(formatWon(row.total)).font(.tasBody.weight(.semibold)).monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .contentShape(Rectangle())
    }

    /// "10월 20일"
    private var dateLabel: String {
        let p = row.date.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return row.date }
        return "\(m)월 \(d)일"
    }

    /// "2026년 (화)"
    private var yearLabel: String {
        guard let date = KST.dayKey.date(from: row.date) else { return "" }
        let weekday = KST.calendarWeekdayLabels[KST.calendar.component(.weekday, from: date) - 1]
        return "\(KST.calendar.component(.year, from: date))년 (\(weekday))"
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
                Text(formatWon(row.total)).font(.tasBody.weight(.semibold))
                Text("\(row.count)건").font(.caption2).foregroundStyle(Color.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .contentShape(Rectangle())
    }
}
