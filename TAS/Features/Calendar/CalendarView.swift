import SwiftUI

/// 메인 캘린더 — 일/주 뷰. 웹의 `/day`·`/week`에 대응.
struct CalendarView: View {
    enum Mode: String, CaseIterable { case day = "일", week = "주" }

    @State private var viewModel = CalendarViewModel()
    @State private var selectedDate = Date()
    @State private var selected: Reservation?
    @State private var selectedAssigneeId: Int?
    @State private var mode: Mode = .day

    static let kst = TimeZone(identifier: "Asia/Seoul")!

    static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = kst
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static var kstCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = kst
        cal.firstWeekday = 2 // 월요일 시작(웹 WEEKDAY_LABELS)
        return cal
    }

    private var dateKey: String { Self.keyFormatter.string(from: selectedDate) }

    var body: some View {
        NavigationStack {
            LoadableView(state: viewModel.state, loadingText: "예약 불러오는 중…") { _ in
                VStack(spacing: 0) {
                    assigneeFilterBar
                    switch mode {
                    case .day: dayList
                    case .week: weekList
                    }
                }
            }
            .navigationTitle("캘린더")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .labelsHidden()
                }
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
            .sheet(item: $selected) { reservation in
                ReservationDetailView(
                    reservation: reservation,
                    customer: viewModel.customer(reservation.customerId),
                    assignee: viewModel.assignee(reservation.assigneeId),
                    serviceColor: viewModel.serviceColor(reservation.service),
                    isNewCustomer: viewModel.isNewCustomer(reservation)
                )
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

    /// 예약 행 버튼 — 일/주 뷰 공용.
    private func reservationButton(_ reservation: Reservation) -> some View {
        Button {
            selected = reservation
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
        let cal = Self.kstCalendar
        guard let interval = cal.dateInterval(of: .weekOfYear, for: selectedDate) else { return [] }
        return (0..<7).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: interval.start)
                .map { Self.keyFormatter.string(from: $0) }
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
