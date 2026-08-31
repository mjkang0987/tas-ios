import SwiftUI

/// 매출 드릴다운 — 웹 `RevenueMetricModal` + `RevenueDailyDetailModal` 이식.
///
/// 매출 화면에서 **탭한 모든 지점**(KPI 5칸·추세 차트 막대·담당자별 행)이 이 하나를 재사용한다.
/// 무엇을 눌렀는지는 `RevenueViewModel.DetailLayer`가 이미 정해서 넘겨준다.
/// 목록에서 한 번 더 내려갈 수 있다 — 예약 → 예약 상세, 고객 → 고객 상세(웹과 동일).
struct RevenueDetailListView: View {
    let layer: RevenueViewModel.DetailLayer
    let viewModel: RevenueViewModel
    /// 매장 적립률(%) — 예약 상세에서 결제하면 자동 적립된다.
    var pointRate: Int = 0
    /// 고객 상세의 적립금 조정·충전 노출 조건(웹 매장 기능 토글).
    var pointsEnabled: Bool = false
    var pointSettings: PointSettings? = nil
    var service: TASService = TASService()
    /// 상세에서 상태·결제가 바뀌면 매출을 다시 읽는다.
    var onChanged: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var selectedReservation: Reservation?
    @State private var selectedCustomer: Customer?

    /// 웹 `EMPTY_TEXT`.
    private static let emptyText = "등록된 데이터가 없습니다"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    content
                } header: {
                    if let subtitle = layer.subtitle {
                        Text(subtitle).textCase(nil)
                    }
                } footer: {
                    Text(layer.summary).font(.footnote.weight(.semibold))
                }
            }
            .navigationTitle(layer.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .sheet(item: $selectedReservation) { reservation in
                ReservationDetailView(
                    reservation: reservation,
                    customer: viewModel.customer(reservation.customerId),
                    assignee: viewModel.assignee(reservation.assigneeId),
                    serviceColorMap: viewModel.serviceColorMap,
                    service: service,
                    onChanged: { await onChanged() },
                    assigneeName: { viewModel.assignee($0)?.name ?? "미지정" },
                    pointRate: pointRate
                )
            }
            .sheet(item: $selectedCustomer) { customer in
                CustomerDetailView(
                    customer: customer,
                    stats: viewModel.customerStats(customer.id),
                    reservationGroups: viewModel.customerGroups(customer.id),
                    serviceColorMap: viewModel.serviceColorMap,
                    pointsEnabled: pointsEnabled,
                    pointSettings: pointSettings,
                    service: service,
                    onChanged: { await onChanged() },
                    assigneesById: viewModel.assigneesById,
                    pointRate: pointRate
                )
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch layer.content {
        case .reservations(let reservations):
            if reservations.isEmpty {
                Text(Self.emptyText).font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(reservations) { reservation in
                    Button {
                        selectedReservation = reservation
                    } label: {
                        ReservationInfoCard(
                            reservation: reservation,
                            serviceColorMap: viewModel.serviceColorMap,
                            customerName: viewModel.customer(reservation.customerId)?.name ?? "고객 미지정",
                            assigneeName: viewModel.assignee(reservation.assigneeId)?.name,
                            assigneeColor: Color(hex: viewModel.assignee(reservation.assigneeId)?.color),
                            showDate: true,
                            showPrice: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

        case .customers(let visits):
            if visits.isEmpty {
                Text(Self.emptyText).font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(visits) { visit in
                    Button {
                        selectedCustomer = viewModel.customer(visit.customerId)
                    } label: {
                        CustomerVisitRow(visit: visit, customer: viewModel.customer(visit.customerId))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.customer(visit.customerId) == nil)
                }
            }
        }
    }
}

/// 신규·재방문 고객 한 명 — 웹 메트릭 모달의 고객 카드와 같은 정보.
private struct CustomerVisitRow: View {
    let visit: RevenueStats.CustomerVisit
    let customer: Customer?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // 이전 방문이 없으면 신규 — 웹도 같은 기준으로 'N' 배지를 단다.
                if visit.prevVisitDate == nil { NewCustomerBadge() }
                Text(customer?.name ?? "고객 #\(visit.customerId)")
                    .font(.subheadline.weight(.semibold))
                if let prev = visit.prevVisitDate,
                   let gap = RevenueStats.visitGapLabel(from: prev, to: visit.visitDate) {
                    ToneBadge(tone: .booked, text: gap)
                }
                Spacer(minLength: 0)
                Text(visit.visitDate)
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }

            WrapLayout(spacing: 10) {
                infoItem("연락처", customer.map(\.formattedTel).flatMap { $0.isEmpty ? nil : $0 } ?? "-")
                infoItem("적립금", "\((customer?.points ?? 0).formatted())P")
                infoItem("최근 방문일", visit.visitDate)
                if let prev = visit.prevVisitDate {
                    infoItem("이전 방문", prev)
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private func infoItem(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption2.weight(.semibold)).monospacedDigit()
        }
    }
}
