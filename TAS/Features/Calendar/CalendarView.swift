import SwiftUI

/// 메인 캘린더 (일 단위) — 웹의 `/day` 뷰에 대응.
struct CalendarView: View {
    @State private var viewModel = CalendarViewModel()
    @State private var selectedDate = Date()
    @State private var selected: Reservation?

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
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("예약 불러오는 중…")
                case .failed(let message):
                    ContentUnavailableView("불러오지 못했습니다", systemImage: "exclamationmark.triangle", description: Text(message))
                case .loaded:
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
                    assignee: viewModel.assignee(reservation.assigneeId)
                )
            }
        }
        .task { await viewModel.load() }
    }

    private var dayList: some View {
        let items = viewModel.reservations(on: dateKey)
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
                            assignee: viewModel.assignee(reservation.assigneeId)
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

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reservation.startTime).font(.headline).monospacedDigit()
                Text(reservation.endTime).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 52, alignment: .leading)

            if let color = Color(hex: assignee?.color) {
                Capsule().fill(color).frame(width: 3, height: 34)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(customerName).font(.body.weight(.semibold))
                HStack(spacing: 6) {
                    Text(reservation.service)
                    if let assignee { Text("· \(assignee.name)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let status = reservation.status {
                StatusBadge(status: status)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct StatusBadge: View {
    let status: ReservationStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .active: return .blue
        case .completed: return .green
        case .cancelled: return .gray
        case .noshow: return .red
        case .requested: return .orange
        }
    }
}

#Preview {
    CalendarView()
}
