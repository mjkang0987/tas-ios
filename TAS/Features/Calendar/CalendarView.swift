import SwiftUI

/// 메인 캘린더 — 일/주/월/년 뷰. 웹의 `/day`·`/week`·`/month`·`/year`에 대응.
struct CalendarView: View {
    enum Mode: String, CaseIterable { case day = "일", week = "주", month = "월", year = "년" }

    @Environment(SessionStore.self) private var session
    @State private var viewModel = CalendarViewModel()
    @State private var selectedDate = Date()
    @State private var selectedAssigneeId: Int?
    @State private var mode: Mode = .day
    @State private var activeSheet: ActiveSheet?

    /// 매장 적립률(%) — 적립 기능이 켜졌을 때만, 아니면 0.
    private var pointRate: Int {
        guard session.currentStore?.usePointSystem == true,
              let p = session.currentStore?.pointSettings, p.enableServiceRate else { return 0 }
        return p.serviceRate
    }

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
                        onEdit: { activeSheet = .edit($0) },
                        history: viewModel.history(forReservation: reservation.id),
                        assigneeName: { viewModel.assignee($0)?.name ?? "미지정" },
                        pointRate: pointRate
                    )
                case .create:
                    ReservationCreateView(
                        service: TASService(),
                        customers: viewModel.customers,
                        assignees: viewModel.activeAssignees,
                        catalog: viewModel.serviceCatalog,
                        existingReservations: viewModel.allReservations,
                        pointRate: pointRate,
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
                        existingReservations: viewModel.allReservations,
                        pointRate: pointRate,
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
                .padding(.vertical, 6)
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
        .padding(.vertical, 6)
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

            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 44) }
                ForEach(1...daysInMonth, id: \.self) { day in
                    let date = cal.date(byAdding: .day, value: day - 1, to: firstOfMonth) ?? firstOfMonth
                    let key = KST.dayKey.string(from: date)
                    Button {
                        selectedDate = date        // 모드 전환 없이 선택만
                    } label: {
                        monthDayCell(day: day, summary: summaries[key],
                                     isToday: cal.isDateInToday(date),
                                     isSelected: cal.isDate(date, inSameDayAs: selectedDate))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Divider()

            selectedDayList   // 하단: 선택 날짜 예약 리스트
        }
    }

    private func monthDayCell(day: Int, summary: CalendarViewModel.PeriodSummary?, isToday: Bool, isSelected: Bool) -> some View {
        VStack(spacing: 2) {
            Text("\(day)")
                .font(.subheadline.weight(isSelected ? .bold : .regular))
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.accentColor : (isToday ? Color.accentColor.opacity(0.18) : Color.clear))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Circle())
            if let count = summary?.count, count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            } else {
                Text(" ").font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }

    /// 월 뷰 하단: 선택한 날짜의 예약 리스트.
    @ViewBuilder private var selectedDayList: some View {
        let items = viewModel.reservations(on: dateKey, assigneeId: selectedAssigneeId)
        let summary = viewModel.daySummary(on: dateKey, assigneeId: selectedAssigneeId)
        VStack(spacing: 0) {
            HStack {
                Text(selectedDayLabel).font(.footnote.weight(.semibold))
                Spacer()
                if summary.count > 0 {
                    Text("\(summary.count)건 · \(formatWon(summary.total))").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
            if items.isEmpty {
                Spacer()
                Text("\(selectedDayLabel) 예약이 없습니다.").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            } else {
                List(items) { reservationButton($0) }.listStyle(.plain)
            }
        }
    }

    private var selectedDayLabel: String {
        let cal = KST.calendar
        return "\(cal.component(.month, from: selectedDate))월 \(cal.component(.day, from: selectedDate))일"
    }

    // MARK: - 년(Year) 뷰

    private var yearColumns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 8), count: 3) }

    @ViewBuilder private var yearView: some View {
        let cal = KST.calendar
        let year = cal.component(.year, from: selectedDate)
        let selMonth = cal.component(.month, from: selectedDate)
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

            LazyVGrid(columns: yearColumns, spacing: 8) {
                ForEach(1...12, id: \.self) { m in
                    let key = String(format: "%04d-%02d", year, m)
                    Button {
                        if let d = cal.date(from: DateComponents(year: year, month: m, day: 1)) {
                            selectedDate = d       // 모드 전환 없이 선택만
                        }
                    } label: {
                        monthCard(month: m, summary: monthly[key], isSelected: m == selMonth)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Divider()

            selectedMonthList(year: year, month: selMonth)  // 하단: 선택 월 예약 리스트
        }
    }

    private func monthCard(month: Int, summary: CalendarViewModel.PeriodSummary?, isSelected: Bool) -> some View {
        VStack(spacing: 3) {
            Text("\(month)월").font(.subheadline.weight(.semibold))
            if let s = summary, s.count > 0 {
                Text("\(s.count)건").font(.caption2).foregroundStyle(.secondary)
                Text(formatWon(s.total)).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text("–").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
    }

    /// 년 뷰 하단: 선택한 월의 예약 리스트(날짜 포함).
    @ViewBuilder private func selectedMonthList(year: Int, month: Int) -> some View {
        let prefix = String(format: "%04d-%02d", year, month)
        let items = viewModel.reservations(inMonthPrefix: prefix, assigneeId: selectedAssigneeId)
        VStack(spacing: 0) {
            HStack {
                Text("\(month)월").font(.footnote.weight(.semibold))
                Spacer()
                Text("\(items.count)건").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
            if items.isEmpty {
                Spacer()
                Text("\(month)월 예약이 없습니다.").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            } else {
                List(items) { monthReservationButton($0) }.listStyle(.plain)
            }
        }
    }

    /// 월 리스트용 행(날짜 포함) — 탭 시 상세.
    private func monthReservationButton(_ r: Reservation) -> some View {
        Button {
            activeSheet = .detail(r)
        } label: {
            HStack(spacing: 10) {
                Text(shortDate(r.date)).font(.caption.weight(.semibold)).frame(width: 42, alignment: .leading).monospacedDigit()
                Text(r.startTime).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.customerName(r.customerId)).font(.subheadline.weight(.medium))
                    Text(r.service).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(state: r.displayState)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "2026-07-23" → "07.23".
    private func shortDate(_ dateKey: String) -> String {
        let p = dateKey.split(separator: "-")
        return p.count == 3 ? "\(p[1]).\(p[2])" : dateKey
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
            Text("\(count)건").font(.footnote.weight(.semibold))
            Spacer()
            Text("매출 \(formatWon(total))").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder private var dayList: some View {
        let items = viewModel.reservations(on: dateKey, assigneeId: selectedAssigneeId)
        let summary = viewModel.daySummary(on: dateKey, assigneeId: selectedAssigneeId)
        VStack(spacing: 0) {
            daySummaryHeader(count: summary.count, total: summary.total)
            if items.isEmpty {
                ContentUnavailableView("예약 없음", systemImage: "calendar", description: Text("\(dateKey) 예약이 없습니다."))
            } else {
                let range = timelineRange(for: items)
                DayTimelineView(
                    reservations: items,
                    startHour: range.0,
                    endHour: range.1,
                    customerName: { viewModel.customerName($0) },
                    color: { timelineColor($0) },
                    onTap: { activeSheet = .detail($0) }
                )
            }
        }
    }

    /// 타임라인 세로 범위(시) — 영업시간 기준 + 당일 예약을 포함하도록 확장.
    private func timelineRange(for items: [Reservation]) -> (Int, Int) {
        var startH = 9, endH = 21
        if let bh = session.currentStore?.businessHours {
            if let s = hourOf(bh.start) { startH = s }
            if let e = hourOf(bh.end) { endH = (minuteOf(bh.end) ?? 0) > 0 ? e + 1 : e }
        }
        for r in items {
            if let s = hourOf(r.startTime) { startH = min(startH, s) }
            if let e = hourOf(r.endTime) { endH = max(endH, (minuteOf(r.endTime) ?? 0) > 0 ? e + 1 : e) }
        }
        startH = max(0, min(startH, 23))
        endH = max(startH + 1, min(endH, 24))
        return (startH, endH)
    }

    /// 블록 색 — 취소·노쇼는 회색, 아니면 담당자 색 우선(없으면 서비스 색).
    private func timelineColor(_ r: Reservation) -> Color {
        if r.status == .cancelled || r.status == .noshow { return .gray }
        if let c = Color(hex: viewModel.assignee(r.assigneeId)?.color) { return c }
        return viewModel.serviceColor(r.service) ?? .accentColor
    }

    private func hourOf(_ hhmm: String) -> Int? { Int(hhmm.split(separator: ":").first ?? "") }
    private func minuteOf(_ hhmm: String) -> Int? {
        let p = hhmm.split(separator: ":")
        return p.count == 2 ? Int(p[1]) : nil
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(reservation.startTime).font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(reservation.endTime).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 44, alignment: .leading)

            ColorAccentBar(color: Color(hex: assignee?.color), height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(customerName).font(.subheadline.weight(.semibold))
                    if isNewCustomer { NewCustomerBadge() }
                }
                HStack(spacing: 5) {
                    if let serviceColor { ColorDot(color: serviceColor, size: 6) }
                    Text(reservation.service)
                    if let assignee { Text("· \(assignee.name)") }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            StatusBadge(state: reservation.displayState)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

#Preview {
    CalendarView()
        .environment(SessionStore())
}
