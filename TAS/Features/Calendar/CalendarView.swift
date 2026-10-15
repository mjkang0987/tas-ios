import SwiftUI

/// 메인 캘린더 — 일/주/월/년 뷰. 웹의 `/day`·`/week`·`/month`·`/year`에 대응.
struct CalendarView: View {
    enum Mode: String, CaseIterable { case day = "일", three = "3일", week = "주", month = "월", year = "년" }

    @Environment(SessionStore.self) private var session
    @State private var viewModel = CalendarViewModel()
    @State private var selectedDate = Date()
    @State private var selectedAssigneeId: Int?
    @State private var mode: Mode = .day
    @State private var activeSheet: ActiveSheet?

    /// 매장 적립률(%) — 판정은 `Store.effectivePointRate` 한 곳에서만 한다.
    private var pointRate: Int { session.currentStore?.effectivePointRate ?? 0 }

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

    /// 해당 날짜의 휴무 종류(임시 휴업일 / 정기 휴무). 매장 정보가 없으면 nil.
    private func closedKind(_ key: String) -> StoreClosedKind? {
        session.currentStore?.closedKind(on: key)
    }

    /// 요청함은 공개 예약 페이지에서만 생기므로 온라인예약을 켠 **로그인** 매장에서만 노출한다
    /// (웹 `BookingRequestNotification`의 `useOnlineBooking` 게이트 + 게스트 서버기능 차단 규칙).
    private var showsBookingRequests: Bool {
        !session.isGuest && session.currentStore?.useOnlineBooking == true
    }

    var body: some View {
        NavigationStack {
            LoadableView(state: viewModel.state, loadingText: "예약 불러오는 중…") { _ in
                VStack(spacing: 0) {
                    modePicker
                    assigneeFilterBar
                    switch mode {
                    case .day: dayList
                    case .three: threeList
                    case .week: weekList
                    case .month: monthView
                    case .year: yearView
                    }
                }
            }
            // 큰 제목을 두지 않는다 — 하단 탭바가 이미 '캘린더'라고 말하고 있어 같은 말이
            // 두 번이고, 달력이 세로를 많이 쓰는 화면이라 그 높이가 아깝다.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 웹 헤더처럼 좌우 이동을 날짜 왼쪽에 둔다 — 뷰마다 따로 머리줄을 두면
                // 같은 조작이 화면마다 다른 자리에 있고 세로도 그만큼 먹는다.
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { shiftPeriod(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("이전")
                    Button { shiftPeriod(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("다음")
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .labelsHidden()
                }
                // 고객이 보낸 예약 신청·변경·취소 요청함(웹 헤더 벨과 같은 자리).
                if showsBookingRequests {
                    ToolbarItem(placement: .topBarTrailing) {
                        BookingRequestsButton(onApplied: { await viewModel.reload() })
                    }
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
                        serviceColorMap: viewModel.serviceColorMap,
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
                        serviceColorMap: viewModel.serviceColorMap,
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
                        serviceColorMap: viewModel.serviceColorMap,
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

        VStack(spacing: 8) {
            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(Array(KST.weekdayLabels.enumerated()), id: \.offset) { i, s in
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
                            .storeClosed(closedKind(key))
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
                List(items) { r in
                    reservationButton(r)
                        // 카드가 테두리로 제 경계를 긋는다 — 행 구분선까지 두면 선이 두 겹이다.
                        .listRowSeparator(.hidden)
                        // 카드 간격은 웹(2px)에 맞추되, 좌우는 iOS 표준 16pt 를 지킨다 —
                        // 8pt 까지 좁히면 카드 왼쪽에서 시작하는 스와이프가 시스템 뒤로가기와 겹친다.
                        .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
                }
                .listStyle(.plain)
                // 머리줄(날짜·건수) 과 첫 카드가 붙어 보인다 — 콘텐츠 상단만 띄운다.
                // 행 간격(listRowInsets)을 키우면 카드 사이까지 벌어진다.
                .contentMargins(.top, 10, for: .scrollContent)
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

        VStack(spacing: 8) {
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

    /// 날짜별 묶음 — 웹 목록의 `grouped` 와 같은 규칙(날짜 오름차순, 그 안은 시작시간 순).
    private struct DateGroup: Identifiable {
        let date: String
        let items: [Reservation]
        var id: String { date }
    }

    /// "2026-07-23" → "7월 23일". 머리줄에 ISO 키를 그대로 보여주지 않는다
    /// (화면의 다른 날짜 표기 `selectedDayLabel` 과 같은 모양).
    private func dayLabel(_ dateKey: String) -> String {
        let p = dateKey.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return dateKey }
        return "\(m)월 \(d)일"
    }

    private func groupedByDate(_ items: [Reservation]) -> [DateGroup] {
        Dictionary(grouping: items, by: \.date)
            .map { DateGroup(date: $0.key, items: $0.value.sorted { $0.startTime < $1.startTime }) }
            .sorted { $0.date < $1.date }
    }

    /// 년 뷰 하단: 선택한 월의 예약 리스트(날짜 포함).
    @ViewBuilder private func selectedMonthList(year: Int, month: Int) -> some View {
        let prefix = String(format: "%04d-%02d", year, month)
        let items = viewModel.reservations(inMonthPrefix: prefix, assigneeId: selectedAssigneeId)
        let summary = viewModel.monthlySummaries(yearPrefix: String(format: "%04d", year), assigneeId: selectedAssigneeId)[prefix]
        VStack(spacing: 0) {
            HStack {
                Text("\(month)월").font(.footnote.weight(.semibold))
                Spacer()
                // 월 뷰의 같은 자리(선택일 머리줄)는 금액까지 보여준다 — 여기만 건수뿐이면 어긋난다.
                if let summary, summary.count > 0 {
                    Text("\(summary.count)건 · \(formatWon(summary.total))").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
            if items.isEmpty {
                Spacer()
                Text("\(month)월 예약이 없습니다.").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            } else {
                // 한 달치를 한 줄로 쌓으면 스크롤 중 지금 보는 게 며칠 건인지 잃는다.
                // 웹은 날짜 머리줄을 sticky 로 붙인다 — .plain 리스트의 Section 헤더가 같은 동작이다.
                List {
                    ForEach(groupedByDate(items), id: \.date) { group in
                        Section {
                            ForEach(group.items) { r in
                                monthReservationButton(r)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
                            }
                        } header: {
                            // 붙어 있는 동안 밑으로 지나가는 카드가 글자에 비친다 — 바탕을 깔아 가린다.
                            // (웹 StyledDateTitle 도 같은 이유로 배경을 둔다.)
                            Text("\(dayLabel(group.date)) · \(group.items.count)건")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 16)
                                .background(Color(.systemBackground))
                        }
                        .listRowInsets(EdgeInsets())
                    }
                }
                .listStyle(.plain)
                .contentMargins(.top, 10, for: .scrollContent)
            }
        }
    }

    /// 월 리스트용 행(날짜 포함) — 탭 시 상세.
    private func monthReservationButton(_ r: Reservation) -> some View {
        let assignee = viewModel.assignee(r.assigneeId)
        return Button {
            activeSheet = .detail(r)
        } label: {
            // 손으로 그린 행이라 혼자 카드 디자인 밖에 있었다 — 공용 카드로 합친다.
            ReservationInfoCard(
                reservation: r,
                serviceColorMap: viewModel.serviceColorMap,
                customerName: viewModel.customerName(r.customerId),
                isNewCustomer: viewModel.isNewCustomer(r),
                assigneeName: assignee?.name,
                assigneeColor: Color(hex: assignee?.color),
                // 날짜는 섹션 머리줄이 말한다 — 카드에 또 적으면 같은 말이 두 번이다.
                showPrice: true
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 기간 이동 헤더 (월/년 공용)

    /// 보고 있는 뷰의 한 칸만큼 움직인다 — 웹 헤더의 좌우 버튼과 같은 규칙.
    private func shiftPeriod(_ step: Int) {
        let cal = KST.calendar
        let moved: Date?
        switch mode {
        case .day:   moved = cal.date(byAdding: .day, value: step, to: selectedDate)
        case .three: moved = cal.date(byAdding: .day, value: 3 * step, to: selectedDate)
        case .week:  moved = cal.date(byAdding: .weekOfYear, value: step, to: selectedDate)
        case .month: moved = cal.date(byAdding: .month, value: step, to: selectedDate)
        case .year:  moved = cal.date(byAdding: .year, value: step, to: selectedDate)
        }
        if let moved { selectedDate = moved }
    }

    /// 예약 행 버튼 — 일/주 뷰 공용.
    private func reservationButton(_ reservation: Reservation) -> some View {
        let assignee = viewModel.assignee(reservation.assigneeId)
        return Button {
            activeSheet = .detail(reservation)
        } label: {
            ReservationInfoCard(
                reservation: reservation,
                serviceColorMap: viewModel.serviceColorMap,
                customerName: viewModel.customerName(reservation.customerId),
                isNewCustomer: viewModel.isNewCustomer(reservation),
                assigneeName: assignee?.name,
                assigneeColor: Color(hex: assignee?.color),
                // 웹 목록 카드는 금액까지 보여준다(ReservationListSection 의 showPrice).
                showPrice: true
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
        // 가로로 꽉 찬 바라 모서리를 둥글리지 않는다(0). 휴무면 틴트가 회색 배경 위를 덮는다.
        .storeClosed(closedKind(dateKey), cornerRadius: 0)
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
                    serviceColorMap: viewModel.serviceColorMap,
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

    /// 3일 뷰가 그리는 날짜 — 기준일부터 3일(웹 `weekDates.ts` 와 같은 규칙).
    private var threeDayKeys: [String] {
        let cal = KST.calendar
        return (0..<3).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: selectedDate)
                .map { KST.dayKey.string(from: $0) }
        }
    }

    private var weekList: some View { timelineList(weekDayKeys) }
    private var threeList: some View { timelineList(threeDayKeys) }

    /// 날짜 칼럼 타임라인. 주·3일이 일수만 다르고 나머지가 같아 한 곳으로 묶는다.
    private func timelineList(_ keys: [String]) -> some View {
        let items = keys.flatMap { viewModel.reservations(on: $0, assigneeId: selectedAssigneeId) }
        // 시간축 범위는 주 전체로 한 번만 잡는다 — 날마다 다르면 칼럼끼리 눈금이 어긋난다.
        let range = timelineRange(for: items)
        return DayColumnsTimelineView(
            dayKeys: keys,
            todayKey: KST.dayKey.string(from: Date()),
            startHour: range.0,
            endHour: range.1,
            reservations: { viewModel.reservations(on: $0, assigneeId: selectedAssigneeId) },
            header: { key, _ in weekdayHeader(key) },
            closedKind: { closedKind($0) },
            customerName: { viewModel.customerName($0) },
            color: { timelineColor($0) },
            onTap: { activeSheet = .detail($0) }
        )
        .refreshable { await viewModel.load() }
    }

    /// "MM.dd 요일" 헤더. 요일은 칼럼 순서가 아니라 날짜에서 낸다 —
    /// 3일 뷰는 기준일부터 시작해 index 와 요일이 어긋난다.
    private func weekdayHeader(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let date = KST.dayKey.date(from: key) else { return "" }
        return "\(parts[1]).\(parts[2]) \(KST.weekdayLabel(for: date))"
    }
}

#Preview {
    CalendarView()
        .environment(SessionStore())
}
