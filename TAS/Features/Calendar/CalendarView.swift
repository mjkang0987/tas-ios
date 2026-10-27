import SwiftUI

/// 메인 캘린더 — 일/주/월/년 뷰. 웹의 `/day`·`/week`·`/month`·`/year`에 대응.
struct CalendarView: View {
    enum Mode: String, CaseIterable { case day = "일", three = "3일", week = "주", month = "월", year = "년" }

    @Environment(SessionStore.self) private var session
    @Environment(ReminderScheduler.self) private var reminders
    @State private var viewModel = CalendarViewModel()
    @State private var selectedDate = Date()
    @State private var selectedAssigneeId: Int?
    @State private var mode: Mode = .day
    @State private var activeSheet: ActiveSheet?
    /// 알림 종의 예약 요청 — 툴바 버튼의 `.task` 는 안 돌 때가 있어(UIKit 바 버튼 호스팅) 캘린더가 들고 읽는다.
    @State private var bookingRequests = BookingRequestsViewModel()
    /// 월 뷰에서 앞뒤 달 날짜를 누르면 아래 목록만 그날로 — 달력은 보던 달 그대로(안드로이드 `listDateKey`). nil 이면 선택한 날.
    @State private var monthListDate: Date?
    private var listDate: Date { monthListDate ?? selectedDate }

    /// 매장 적립률(%) — 판정은 `Store.effectivePointRate` 한 곳에서만 한다.
    private var pointRate: Int { session.currentStore?.effectivePointRate ?? 0 }

    /// 예약 상세/추가 시트를 하나의 `.sheet(item:)`로 통합
    /// (같은 뷰에 `.sheet` 여러 개를 붙이면 SwiftUI에서 충돌해 안 뜨는 버그를 회피).
    /// 예약 변경·고객 상세는 상세 위에 쌓인다(`DetailSheet`).
    private enum ActiveSheet: Identifiable {
        case detail(Int)          // 예약 id
        case customer(Int)        // 고객 id — 예약 카드의 고객명(웹 `onCustomerClick`)
        case create
        case notifications
        var id: String {
            switch self {
            case .detail(let id): return "detail-\(id)"
            case .customer(let id): return "customer-\(id)"
            case .create: return "create"
            case .notifications: return "notifications"
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
                    // 웹 `CalendarDirection`·안드로이드 헤더의 '오늘' — 어느 뷰든 오늘이 든 칸으로 간다(늘 누를 수 있다)
                    Button("오늘") { selectedDate = Date() }
                    Button { shiftPeriod(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("이전")
                    Button { shiftPeriod(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("다음")
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .labelsHidden()
                }
                // 알림 종(웹 헤더와 같은 자리) — 곧 시작은 게스트도 보여 늘 둔다. 1분마다 다시 센다.
                ToolbarItem(placement: .topBarTrailing) {
                    TimelineView(.everyMinute) { context in
                        let soon = UpcomingReservations.compute(viewModel.allReservations, now: context.date).soon.count
                        let todo = showsBookingRequests ? bookingRequests.pendingCount : 0
                        let indicator = UpcomingReservations.bellIndicator(todo: todo, soon: soon)
                        NotificationBellButton(count: indicator.count, dot: indicator.dot) { activeSheet = .notifications }
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .detail(let id):
                    if let data = viewModel.detailData {
                        DetailSheet(route: .reservation(id), data: data, reload: { await viewModel.reload() })
                    }
                case .customer(let id):
                    if let data = viewModel.detailData {
                        DetailSheet(route: .customer(id), data: data, reload: { await viewModel.reload() })
                    }
                case .notifications:
                    NotificationCenterView(
                        requests: showsBookingRequests ? bookingRequests : nil,
                        reservations: viewModel.allReservations,
                        customersById: viewModel.state.value?.customersById ?? [:],
                        assigneesById: viewModel.state.value?.assigneesById ?? [:],
                        onApplied: { await viewModel.reload() },
                        // 시트를 상세로 바꿔 띄운다(같은 `.sheet(item:)` — 알림을 닫고 상세가 올라온다)
                        onOpen: { activeSheet = .detail($0) }
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
                }
            }
        }
        .task { await viewModel.load() }
        .task(id: showsBookingRequests) { if showsBookingRequests { await bookingRequests.load() } }
        // 날짜를 옮기거나(이전·다음·오늘·날짜 선택) 뷰를 바꾸면 앞뒤 달 목록 고르기는 풀린다
        .onChange(of: selectedDate) { _, _ in monthListDate = nil }
        .onChange(of: mode) { _, _ in monthListDate = nil }
        // 예약 알림을 눌러 들어오면 그 예약 상세 — 아직 불러오는 중이면 다 불러온 뒤에 연다
        .onChange(of: reminders.pendingReservationId, initial: true) { _, _ in openPendingReminder() }
        .onChange(of: viewModel.state.value?.reservations.count) { _, _ in openPendingReminder() }
    }

    private func openPendingReminder() {
        guard let id = reminders.pendingReservationId, let loaded = viewModel.state.value else { return }
        reminders.pendingReservationId = nil
        // 그사이 지워진 예약이면 아무것도 열지 않는다
        guard let reservation = loaded.reservations.first(where: { $0.id == id }) else { return }
        if let day = KST.dayKey.date(from: reservation.date) { selectedDate = day }
        activeSheet = .detail(reservation.id)
    }

    // MARK: - 담당자 필터 바 (공용 FilterChip)

    /// 웹 헤더 둘째 줄 — '전체보기' 고르기(네이티브 select) · '+ 예약'(보라 채움).
    /// '+ 예약'은 웹에선 첫 줄이지만 휴대폰 툴바엔 오늘·이전·다음·날짜로 자리가 없어 ⋯ 안으로 숨는다 — 이 줄 오른쪽에 둔다.
    private var assigneeFilterBar: some View {
        let assignees = viewModel.assignees
        return HStack {
            if !assignees.isEmpty {
                Picker(session.labels.assignee, selection: $selectedAssigneeId) {
                    Text("전체보기").tag(Int?.none)
                    ForEach(assignees) { assignee in
                        Text(assignee.name).tag(Int?.some(assignee.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.textPrimary)
            }
            Spacer(minLength: 0)
            Button {
                activeSheet = .create
            } label: {
                Label("예약", systemImage: "plus").font(.tasBody.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandFill)
            .disabled(viewModel.state.value == nil)
        }
        .padding(.horizontal, 8)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
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
        let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
        let month = cal.component(.month, from: firstOfMonth)

        VStack(spacing: 8) {
            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(Array(KST.calendarWeekdayLabels.enumerated()), id: \.offset) { i, s in
                    Text(s)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(i == 0 || i == 6 ? Color.textSecondary : Color.textPrimary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)

            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(Self.monthGridDates(firstOfMonth), id: \.self) { date in
                    let key = KST.dayKey.string(from: date)
                    monthDayCell(date: date, key: key,
                                 inMonth: cal.component(.month, from: date) == month,
                                 isToday: cal.isDateInToday(date),
                                 isSelected: cal.isDate(date, inSameDayAs: listDate))
                        .storeClosed(closedKind(key))
                }
            }
            .padding(.horizontal, 12)

            Divider()

            selectedDayList   // 하단: 선택 날짜 예약 리스트
        }
    }

    /// 달력 칸 날짜 — 1일이 든 주의 일요일부터 말일이 든 주의 토요일까지(4~6주). 앞뒤 달 날짜도 채운다(웹 `Days`·안드로이드 `monthGrid`).
    static func monthGridDates(_ firstOfMonth: Date) -> [Date] {
        let cal = KST.calendar
        guard let days = cal.range(of: .day, in: .month, for: firstOfMonth)?.count,
              let last = cal.date(byAdding: .day, value: days - 1, to: firstOfMonth),
              let start = cal.dateInterval(of: .weekOfYear, for: firstOfMonth)?.start,
              let endWeek = cal.dateInterval(of: .weekOfYear, for: last)?.start else { return [] }
        let count = (cal.dateComponents([.day], from: start, to: endWeek).day ?? 0) + 7
        return (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    /// 칸 하나 — 웹 `Num`·`ReservationList`(모바일 이름 1개): 예약 1건이면 고객명 태그(누르면 그 예약), 2건 이상이면 건수.
    /// 앞뒤 달 날짜는 'M/D' 흐린 글자 — 누르면 아래 목록만 그날로.
    private func monthDayCell(date: Date, key: String, inMonth: Bool, isToday: Bool, isSelected: Bool) -> some View {
        let cal = KST.calendar
        let items = viewModel.reservations(on: key, assigneeId: selectedAssigneeId)
        let day = cal.component(.day, from: date)
        let month = cal.component(.month, from: date)
        let single = items.count == 1 ? items.first : nil
        return Button {
            if inMonth { selectedDate = date; monthListDate = nil } else { monthListDate = date }
        } label: {
            VStack(spacing: 2) {
                Text(inMonth ? "\(day)" : "\(month)/\(day)")
                    .font(.tasBody.weight(isSelected ? .bold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, inMonth ? 0 : 4)
                    .frame(minWidth: 28, minHeight: 28)
                    .background(isSelected ? Color.brandFill : (isToday ? Color.accentColor.opacity(0.18) : Color.clear), in: Capsule())
                    .foregroundStyle(isSelected ? Color.white : (inMonth ? Color.textPrimary : Color.textSecondary))
                if items.count > 1 {
                    Text("\(items.count)").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
                } else if let single {
                    // 자리만 잡는다 — 이름 태그는 따로 누르는 버튼이라 아래 overlay 로 얹는다
                    monthNameTag(single).hidden()
                } else {
                    Text(" ").font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(month)월 \(day)일" + (items.isEmpty ? "" : ", 예약 \(items.count)건"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay(alignment: .bottom) {
            if let single {
                Button { activeSheet = .detail(single.id) } label: { monthNameTag(single) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(viewModel.customerName(single.customerId)) 예약" + (single.isInactive ? ", \(single.isNoshow ? "노쇼" : "취소")" : ""))
                    .accessibilityHint("예약 상세 열기")
            }
        }
    }

    /// 칸 안 고객명 태그 — 담당자 색 옅은 바탕·테두리·왼쪽 띠. 취소·노쇼는 회색 + 빗금 + 가로줄(타임라인 블록과 같은 규칙).
    private func monthNameTag(_ r: Reservation) -> some View {
        let color = Color(hex: viewModel.assignee(r.assigneeId)?.color) ?? .secondary
        let inactive = r.isInactive
        return Text(viewModel.customerName(r.customerId))
            .font(.caption2)
            .strikethrough(inactive)
            .foregroundStyle(inactive ? Color.textSecondary : Color.textPrimary)
            .lineLimit(1)
            .padding(.leading, 5).padding(.trailing, 2).padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    inactive ? Color(.secondarySystemBackground) : color.opacity(0.07)
                    if inactive { HatchPattern(noshow: r.isNoshow) }
                }
            }
            .overlay(alignment: .leading) { Rectangle().fill(inactive ? Color(.separator) : color).frame(width: 3) }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(inactive ? Color(.separator) : color.opacity(0.4), lineWidth: 1) }
    }

    /// 월 뷰 하단: 선택한 날짜의 예약 리스트.
    @ViewBuilder private var selectedDayList: some View {
        let listKey = KST.dayKey.string(from: listDate)
        let items = viewModel.reservations(on: listKey, assigneeId: selectedAssigneeId)
        let summary = viewModel.daySummary(on: listKey, assigneeId: selectedAssigneeId)
        VStack(spacing: 0) {
            HStack {
                Text(selectedDayLabel).font(.footnote.weight(.semibold))
                Spacer()
                if summary.count > 0 {
                    Text("\(summary.count)건 · \(formatWon(summary.total))").font(.caption).foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
            if items.isEmpty {
                Spacer()
                Text("\(selectedDayLabel) 예약이 없습니다.").font(.footnote).foregroundStyle(Color.textSecondary)
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
        return "\(cal.component(.month, from: listDate))월 \(cal.component(.day, from: listDate))일"
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
                    // 웹 `Year` StyledMonthDetail·안드로이드 — 그 달 월 뷰로(오늘이 그 달이면 오늘, 아니면 1일)
                    .overlay(alignment: .bottom) {
                        Button("자세히") { openMonth(year: year, month: m) }
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 24)
                            .contentShape(Capsule())
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(m)월 월 보기")
                    }
                }
            }
            .padding(.horizontal, 12)

            Divider()

            selectedMonthList(year: year, month: selMonth)  // 하단: 선택 월 예약 리스트
        }
    }

    private func monthCard(month: Int, summary: CalendarViewModel.PeriodSummary?, isSelected: Bool) -> some View {
        VStack(spacing: 3) {
            Text("\(month)월").font(.tasBody.weight(.semibold))
            if let s = summary, s.count > 0 {
                Text("\(s.count)건").font(.caption2).foregroundStyle(Color.textSecondary)
                Text(formatWon(s.total)).font(.caption2).foregroundStyle(Color.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text("–").font(.caption2).foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 24)   // 아래 '자세히' 자리
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
                    Text("\(summary.count)건 · \(formatWon(summary.total))").font(.caption).foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
            if items.isEmpty {
                Spacer()
                Text("\(month)월 예약이 없습니다.").font(.footnote).foregroundStyle(Color.textSecondary)
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
            activeSheet = .detail(r.id)
        } label: {
            // 손으로 그린 행이라 혼자 카드 디자인 밖에 있었다 — 공용 카드로 합친다.
            ReservationInfoCard(
                reservation: r,
                serviceColorMap: viewModel.serviceColorMap,
                customerName: viewModel.customerName(r.customerId),
                isNewCustomer: viewModel.isNewCustomer(r),
                onCustomerTap: { activeSheet = .customer(r.customerId) },
                assigneeName: assignee?.name,
                assigneeColor: Color(hex: assignee?.color),
                // 날짜는 섹션 머리줄이 말한다 — 카드에 또 적으면 같은 말이 두 번이다.
                showPrice: true
            )
        }
        .buttonStyle(.plain)
    }

    private func openMonth(year: Int, month: Int) {
        let cal = KST.calendar
        let today = Date()
        let inThatMonth = cal.component(.year, from: today) == year && cal.component(.month, from: today) == month
        selectedDate = inThatMonth ? today : (cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? selectedDate)
        mode = .month
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
            activeSheet = .detail(reservation.id)
        } label: {
            ReservationInfoCard(
                reservation: reservation,
                serviceColorMap: viewModel.serviceColorMap,
                customerName: viewModel.customerName(reservation.customerId),
                isNewCustomer: viewModel.isNewCustomer(reservation),
                onCustomerTap: { activeSheet = .customer(reservation.customerId) },
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
            Text("매출 \(formatWon(total))").font(.footnote).foregroundStyle(Color.textSecondary)
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
                    onTap: { activeSheet = .detail($0.id) },
                    isNewCustomer: { viewModel.isNewCustomer($0) },
                    isToday: dateKey == KST.dayKey.string(from: Date())
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
            onTap: { activeSheet = .detail($0.id) },
            onSelectDay: { key in
                if let day = KST.dayKey.date(from: key) { selectedDate = day; mode = .day }
            }
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
