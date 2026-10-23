import SwiftUI

/// 매출 드릴다운 — 웹 `RevenueMetricModal` + `RevenueDailyDetailModal` 이식.
///
/// 매출 화면에서 **탭한 모든 지점**(KPI 5칸·추세 차트 막대·담당자별 행)이 이 하나를 재사용한다.
/// 무엇을 눌렀는지는 `RevenueViewModel.DetailKey`가 정하고, 목록은 여기서 매번 다시 만든다.
/// 목록에서 한 번 더 내려갈 수 있다 — 예약 → 예약 상세, 고객 → 고객 상세(웹과 동일).
struct RevenueDetailListView: View {
    /// 무엇을 탭했는지. 목록은 매 렌더마다 여기서 다시 계산한다 —
    /// 예약을 취소·삭제하고 돌아왔을 때 그 행이 남아 있으면 안 된다.
    let key: RevenueViewModel.DetailKey
    let viewModel: RevenueViewModel
    /// 상세에서 상태·결제가 바뀌면 매출을 다시 읽는다.
    var onChanged: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    /// 누른 예약·고객 — 상세는 `DetailSheet` 가 위로 끝없이 쌓는다(예약 → 고객 → 예약 …).
    @State private var route: DetailRoute?

    /// 웹 `EMPTY_TEXT`.
    private static let emptyText = "등록된 데이터가 없습니다"

    var body: some View {
        // 한 번만 계산해 제목·푸터·목록이 같은 스냅샷을 쓰게 한다.
        let layer = viewModel.layer(for: key)
        return NavigationStack {
            List {
                Section {
                    content(of: layer)
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
            .sheet(item: $route) { route in
                if let data = viewModel.detailData {
                    DetailSheet(route: route, data: data, reload: onChanged)
                }
            }
        }
    }

    @ViewBuilder private func content(of layer: RevenueViewModel.DetailLayer) -> some View {
        switch layer.content {
        case .reservations(let reservations):
            if reservations.isEmpty && layer.sales.isEmpty {
                Text(Self.emptyText).font(.footnote).foregroundStyle(Color.textSecondary)
            } else {
                ForEach(reservations) { reservation in
                    let customer = viewModel.customer(reservation.customerId)
                    let assignee = viewModel.assignee(reservation.assigneeId)
                    Button {
                        route = .reservation(reservation.id)
                    } label: {
                        ReservationInfoCard(
                            reservation: reservation,
                            serviceColorMap: viewModel.serviceColorMap,
                            customerName: customer?.name ?? "고객 미지정",
                            isNewCustomer: customer?.isNewCustomerVisit(on: reservation.date) ?? false,
                            onCustomerTap: customer == nil ? nil : { route = .customer(reservation.customerId) },
                            assigneeName: assignee?.name,
                            assigneeColor: Color(hex: assignee?.color),
                            showDate: true,
                            // 행 금액은 **예약가**다. 부분 결제가 있으면 결제완료 상세의 푸터 합계
                            // (실제 결제 금액 합)와 다를 수 있다 — 웹 ReservationInfoCard 도 같다.
                            showPrice: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // 충전 매출 — 예약이 아닌 판매(웹 `StyledSaleItem`). 고객명을 누르면 고객 상세.
            ForEach(layer.sales) { sale in
                Button {
                    route = .customer(sale.customerId)
                } label: {
                    SaleRow(sale: sale, customerName: viewModel.customer(sale.customerId)?.name)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.customer(sale.customerId) == nil)
            }

        case .customers(let visits):
            if visits.isEmpty {
                Text(Self.emptyText).font(.footnote).foregroundStyle(Color.textSecondary)
            } else {
                ForEach(visits) { visit in
                    let customer = viewModel.customer(visit.customerId)
                    Button {
                        route = .customer(visit.customerId)
                    } label: {
                        CustomerVisitRow(visit: visit, customer: customer)
                    }
                    .buttonStyle(.plain)
                    // 고객이 지워졌는데 예약만 남은 경우 — 열 상세가 없으니 누르지 못하게 한다.
                    .disabled(customer == nil)
                }
            }
        }
    }
}

/// 충전 한 건 — '적립금 충전' · 고객명 · 결제수단 / 금액.
private struct SaleRow: View {
    let sale: RevenueStats.StoreSale
    let customerName: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("적립금 충전").font(.tasBody.weight(.semibold))
                HStack(spacing: 6) {
                    Text(customerName ?? "고객 미지정").foregroundStyle(Color.linkText)
                    Text(sale.method?.rawValue ?? "결제수단 없음").foregroundStyle(Color.textSecondary)
                }
                .font(.caption)
            }
            Spacer()
            Text(formatWon(sale.amount)).font(.tasBody.weight(.semibold)).monospacedDigit()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityHint(customerName == nil ? "" : "고객 상세 열기")
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
                    .font(.tasBody.weight(.semibold))
                if let prev = visit.prevVisitDate,
                   let gap = RevenueStats.visitGapLabel(from: prev, to: visit.visitDate) {
                    ToneBadge(tone: .booked, text: gap)
                }
                Spacer(minLength: 0)
                Text(visit.visitDate)
                    .font(.caption2).foregroundStyle(Color.textSecondary).monospacedDigit()
            }

            WrapLayout(spacing: 10) {
                infoItem("연락처", customer.map(\.formattedTel).flatMap { $0.isEmpty ? nil : $0 } ?? "-")
                infoItem("적립금", formatWon(customer?.points ?? 0))
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
            Text(label).font(.caption2).foregroundStyle(Color.textSecondary)
            Text(value).font(.caption2.weight(.semibold)).monospacedDigit()
        }
    }
}
