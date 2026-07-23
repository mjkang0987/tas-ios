import SwiftUI

/// 메인 캘린더 (일 단위) — 웹의 `/day` 뷰에 대응.
struct CalendarView: View {
    @State private var viewModel = CalendarViewModel()
    @State private var selectedDate = Date()
    @State private var selected: Reservation?
    @State private var selectedAssigneeId: Int?

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var dateKey: String { Self.keyFormatter.string(from: selectedDate) }

    var body: some View {
        NavigationStack {
            LoadableView(state: viewModel.state, loadingText: "예약 불러오는 중…") { _ in
                VStack(spacing: 0) {
                    assigneeFilterBar
                    dayList
                }
            }
            .navigationTitle("캘린더")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .labelsHidden()
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

    /// 담당자 필터 바(담당자가 있을 때만). 공용 FilterChip 재사용.
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

    private var dayList: some View {
        let items = viewModel.reservations(on: dateKey, assigneeId: selectedAssigneeId)
        return Group {
            if items.isEmpty {
                ContentUnavailableView("예약 없음", systemImage: "calendar", description: Text("\(dateKey) 예약이 없습니다."))
            } else {
                List(items) { reservation in
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
                .listStyle(.plain)
                .refreshable { await viewModel.load() }
            }
        }
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
