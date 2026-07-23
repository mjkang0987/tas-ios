import SwiftUI

/// 메인 캘린더 — 일/주/월/년 뷰. 웹의 `/day`·`/week`·`/month`·`/year`에 대응.
struct CalendarView: View {
    enum Mode: String, CaseIterable { case day = "일", week = "주", month = "월", year = "년" }

    @State private var viewModel = CalendarViewModel()
    @State private var selectedDate = Date()
    @State private var selectedAssigneeId: Int?
    @State private var mode: Mode = .day
    @State private var activeSheet: ActiveSheet?

    /// 예약 상세/추가 시트를 하나의 `.sheet(item:)`로 통합
    /// (같은 뷰에 `.sheet` 여러 개를 붙이면 SwiftUI에서 충돌해 안 뜨는 버그를 회피).
    private enum ActiveSheet: Identifiable {
        case detail(Reservation)
        case create
        case edit(Reservation)
        var id: String {
            switch self {
            case .detail(let r): return "detail-\(r.id)"
            case .create: return "create"
            case .edit(let r): return "edit-\(r.id)"
            }
        }
    }

    private var dateKey: String { KST.dayKey.string(from: selectedDate) }

    var body: some View {
        NavigationStack {
            LoadableView(state: viewModel.state, loadingText: "예약 불러오는 중…") { _ in
                VStack(spacing: 0) {
                    modePicker
                    assigneeFilterBar
                    switch mode {
                    case .day: dayList
                    case .week: weekList
                    case .month: monthView
                    case .year: yearView
                    }
                }
            }
            .navigationTitle("캘린더")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .labelsHidden()
                }
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
                case .detail(let reservation):
                    ReservationDetailView(
                        reservation: reservation,
                        customer: viewModel.customer(reservation.customerId),
                        assignee: viewModel.assignee(reservation.assigneeId),
                        serviceColor: viewModel.serviceColor(reservation.service),
                        isNewCustomer: viewModel.isNewCustomer(reservation),
                        service: TASService(),
                        onChanged: { await viewModel.reload() },
                        onEdit: { activeSheet = .edit($0) }
                    )
                case .create:
                    ReservationCreateView(
                        service: TASService(),
                        customers: viewModel.customers,
                        assignees: viewModel.activeAssignees,
                        catalog: viewModel.serviceCatalog,
                        initialDate: selectedDate,
                        nextReservationId: viewModel.nextReservationId,
                        nextCustomerId: viewModel.nextCustomerId,
                        onSaved: { Task { await viewModel.reload() } }
                    )
                case .edit(let reservation):
                    ReservationCreateView(
                        service: TASService(),
                        customers: viewModel.customers,
                        assignees: viewModel.activeAssignees,
                        catalog: viewModel.serviceCatalog,
                        initialDate: selectedDate,
                        nextReservationId: viewModel.nextReservationId,
                        nextCustomerId: viewModel.nextCustomerId,
                        editing: reservation,
                        onSaved: { Task { await viewModel.reload() } }
                    )
                }
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - 담당자 필터 바 (공용 FilterChip)

    @ViewBuilder private var assigneeFilterBar: some View {
        let assignees = viewModel.assignees
        if !assignees.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(label: "전체", isSelected: selectedAssigneeId == nil) {
                        selectedAssigneeId = nil
                    }
                    ForEach(assignees) { assignee in
                        FilterChip(
                            label: assignee.name,
                            color: Color(hex: assignee.color),
                            isSelected: selectedAssigneeId == assignee.id
                        ) {
                            selectedAssigneeId = assignee.id
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - 뷰 모드 선택 (일/주/월/년)

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - 월(Month) 뷰

    private static let weekdaySymbols = ["월", "화", "수", "목", "금", "토", "일"]
    private var gridColumns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 4), count: 7) }

    @ViewBuilder private var monthView: some View {
        let cal = KST.calendar
        let comps = cal.dateComponents([.year, .month], from: selectedDate)
        let firstOfMonth = cal.date(from: comps) ?? selectedDate
        let monthPrefix = KST.monthKey.string(from: firstOfMonth)
        let summaries = viewModel.dailySummaries(monthPrefix: monthPrefix, assigneeId: selectedAssigneeId)
        let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        let weekday = cal.component(.weekday, from: firstOfMonth)   // 1=일…7=토
        let leading = (weekday - cal.firstWeekday + 7) % 7           // 월요일 시작 오프셋
        let monthTotal = summaries.values.reduce(into: (count: 0, total: 0)) { $0.count += $1.count; $0.total += $1.total }

        VStack(spacing: 8) {
            periodHeader(
                title: KST.monthLabel.string(from: firstOfMonth),
                subtitle: monthTotal.count > 0 ? "\(monthTotal.count)건 · \(formatWon(monthTotal.total))" : "예약 없음",
                onPrev: { shiftMonth(-1) },
                onNext: { shiftMonth(1) }
            )

            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { i, s in
                    Text(s)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(i >= 5 ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)

            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 4) {
                    ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 52) }
                    ForEach(1...daysInMonth, id: \.self) { day in
                        let date = cal.date(byAdding: .day, value: day - 1, to: firstOfMonth) ?? firstOfMonth
                        let key = KST.dayKey.string(from: date)
                        Button {
                            selectedDate = date
                            mode = .day
                        } label: {
                            monthDayCell(day: day, summary: summaries[key], isToday: cal.isDateInToday(date))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    private func monthDayCell(day: Int, summary: CalendarViewModel.PeriodSummary?, isToday: Bool) -> some View {
        VStack(spacing: 3) {
            Text("\(day)")
                .font(.callout)
                .frame(width: 30, height: 30)
                .background(isToday ? Color.accentColor : Color.clear)
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .clipShape(Circle())
            if let count = summary?.count, count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            } else {
                Text(" ").font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
    }

    // MARK: - 년(Year) 뷰

    @ViewBuilder private var yearView: some View {
        let cal = KST.calendar
        let year = cal.component(.year, from: selectedDate)
        let yearPrefix = String(format: "%04d", year)
        let monthly = viewModel.monthlySummaries(yearPrefix: yearPrefix, assigneeId: selectedAssigneeId)
        let yearTotal = monthly.values.reduce(into: (count: 0, total: 0)) { $0.count += $1.count; $0.total += $1.total }

        VStack(spacing: 8) {
            periodHeader(
                title: "\(year)년",
                subtitle: yearTotal.count > 0 ? "\(yearTotal.count)건 · \(formatWon(yearTotal.total))" : "예약 없음",
                onPrev: { shiftYear(-1) },
                onNext: { shiftYear(1) }
            )

            List {
                ForEach(1...12, id: \.self) { m in
                    let key = String(format: "%04d-%02d", year, m)
                    let summary = monthly[key]
                    Button {
                        if let d = cal.date(from: DateComponents(year: year, month: m, day: 1)) {
                            selectedDate = d
                            mode = .month
                        }
                    } label: {
                        monthSummaryRow(month: m, summary: summary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
        }
    }

    private func monthSummaryRow(month: Int, summary: CalendarViewModel.PeriodSummary?) -> some View {
        HStack {
            Text("\(month)월").font(.body.weight(.medium)).frame(width: 44, alignment: .leading)
            Spacer()
            if let summary, summary.count > 0 {
                Text("\(summary.count)건").font(.subheadline).foregroundStyle(.secondary)
                Text(formatWon(summary.total)).font(.subheadline.weight(.medium)).frame(minWidth: 90, alignment: .trailing)
            } else {
                Text("예약 없음").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: - 기간 이동 헤더 (월/년 공용)

    private func periodHeader(title: String, subtitle: String, onPrev: @escaping () -> Void, onNext: @escaping () -> Void) -> some View {
        HStack {
            Button(action: onPrev) { Image(systemName: "chevron.left") }
            Spacer()
            VStack(spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onNext) { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func shiftMonth(_ delta: Int) {
        if let d = KST.calendar.date(byAdding: .month, value: delta, to: selectedDate) { selectedDate = d }
    }
    private func shiftYear(_ delta: Int) {
        if let d = KST.calendar.date(byAdding: .year, value: delta, to: selectedDate) { selectedDate = d }
    }

    /// 예약 행 버튼 — 일/주 뷰 공용.
    private func reservationButton(_ reservation: Reservation) -> some View {
        Button {
            activeSheet = .detail(reservation)
        } label: {
            ReservationRow(
                reservation: reservation,
                customerName: viewModel.customerName(reservation.customerId),
                assignee: viewModel.assignee(reservation.assigneeId),
                serviceColor: viewModel.serviceColor(reservation.service),
                isNewCustomer: viewModel.isNewCustomer(reservation)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 일(Day) 뷰

    private func daySummaryHeader(count: Int, total: Int) -> some View {
        HStack {
            Text("\(count)건").font(.subheadline.weight(.semibold))
            Spacer()
            Text("매출 \(formatWon(total))").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder private var dayList: some View {
        let items = viewModel.reservations(on: dateKey, assigneeId: selectedAssigneeId)
        if items.isEmpty {
            ContentUnavailableView("예약 없음", systemImage: "calendar", description: Text("\(dateKey) 예약이 없습니다."))
        } else {
            let summary = viewModel.daySummary(on: dateKey, assigneeId: selectedAssigneeId)
            VStack(spacing: 0) {
                daySummaryHeader(count: summary.count, total: summary.total)
                List(items) { reservationButton($0) }
                    .listStyle(.plain)
                    .refreshable { await viewModel.load() }
            }
        }
    }

    // MARK: - 주(Week) 뷰

    /// 선택 날짜가 속한 주(월~일)의 날짜 키 배열(KST).
    private var weekDayKeys: [String] {
        let cal = KST.calendar
        guard let interval = cal.dateInterval(of: .weekOfYear, for: selectedDate) else { return [] }
        return (0..<7).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: interval.start)
                .map { KST.dayKey.string(from: $0) }
        }
    }

    private static let weekdayLabels = ["월", "화", "수", "목", "금", "토", "일"]

    private var weekList: some View {
        List {
            ForEach(Array(weekDayKeys.enumerated()), id: \.element) { index, key in
                let items = viewModel.reservations(on: key, assigneeId: selectedAssigneeId)
                let summary = viewModel.daySummary(on: key, assigneeId: selectedAssigneeId)
                Section {
                    if items.isEmpty {
                        Text("예약 없음").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { reservationButton($0) }
                    }
                } header: {
                    HStack {
                        Text(weekdayHeader(key, index: index)).font(.subheadline.weight(.semibold))
                        Spacer()
                        if summary.count > 0 {
                            Text("\(summary.count)건 · \(formatWon(summary.total))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await viewModel.load() }
    }

    /// "MM.dd 요일" 헤더.
    private func weekdayHeader(_ key: String, index: Int) -> String {
        let parts = key.split(separator: "-")
        let label = index < Self.weekdayLabels.count ? Self.weekdayLabels[index] : ""
        guard parts.count == 3 else { return label }
        return "\(parts[1]).\(parts[2]) \(label)"
    }
}

private struct ReservationRow: View {
    let reservation: Reservation
    let customerName: String
    let assignee: Assignee?
    let serviceColor: Color?
    let isNewCustomer: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reservation.startTime).font(.headline).monospacedDigit()
                Text(reservation.endTime).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 52, alignment: .leading)

            ColorAccentBar(color: Color(hex: assignee?.color), height: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(customerName).font(.body.weight(.semibold))
                    if isNewCustomer { NewCustomerBadge() }
                }
                HStack(spacing: 6) {
                    if let serviceColor { ColorDot(color: serviceColor, size: 7) }
                    Text(reservation.service)
                    if let assignee { Text("· \(assignee.name)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            StatusBadge(state: reservation.displayState)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    CalendarView()
}
