import SwiftUI

/// 메인 캘린더 (일 단위) — 웹의 `/day` 뷰에 대응하는 스켈레톤.
struct CalendarView: View {
    @State private var viewModel = CalendarViewModel()
    @State private var selectedDate = Date()

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
        }
        .task { await viewModel.load() }
    }

    private var dayList: some View {
        let items = viewModel.reservations(on: dateKey)
        return Group {
            if items.isEmpty {
                ContentUnavailableView("예약 없음", systemImage: "calendar", description: Text("\(dateKey) 예약이 없습니다."))
            } else {
                List(items) { ReservationRow(reservation: $0) }
                    .listStyle(.plain)
                    .refreshable { await viewModel.load() }
            }
        }
    }
}

private struct ReservationRow: View {
    let reservation: Reservation

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reservation.startTime).font(.headline).monospacedDigit()
                Text(reservation.endTime).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(reservation.service).font(.body.weight(.medium))
                if let price = reservation.price {
                    Text("\(price.formatted())원").font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let status = reservation.status {
                Text(status.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor(status).opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor(status))
            }
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ status: ReservationStatus) -> Color {
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
