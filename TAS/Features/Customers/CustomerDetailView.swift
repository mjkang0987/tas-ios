import SwiftUI

/// 고객 상세 (읽기) — 웹 `/address` 상세에 대응하는 스켈레톤.
struct CustomerDetailView: View {
    let customer: Customer
    var stats: CustomerStats.Summary = .empty
    /// 웹처럼 예약/완료/취소/노쇼로 묶인 최근 예약(빈 그룹은 빠져 있다).
    var reservationGroups: [CustomerStats.Group] = []
    /// 서비스명 → hex(웹 `SERVICE_COLOR_MAP`). 예약 이력의 시술 칩 색.
    let serviceColorMap: [String: String]
    /// "수정" 탭 시 편집 폼을 여는 콜백(제공되지 않으면 수정 버튼 숨김).
    var onEdit: ((Customer) -> Void)? = nil
    /// 매장이 적립금 기능을 쓰면 "적립금 조정" 노출.
    var pointsEnabled: Bool = false
    /// 매장 적립금 설정 — 선불 충전이 켜져 있으면 "적립금 충전"도 노출(충전 규칙 사용).
    var pointSettings: PointSettings? = nil
    var service: TASService = TASService()
    /// 적립금 조정 저장 후 상위 리로드 + 상세 닫기.
    var onChanged: () async -> Void = {}
    /// 병합 대상 후보(이 고객 제외). 비어있지 않으면 "합치기" 노출.
    var mergeCandidates: [Customer] = []
    /// 고객 id → 예약 건수. 병합 대상 선택 시 판단 근거로 쓴다.
    var reservationCounts: [Int: Int] = [:]
    /// 담당자 id → 담당자. 예약 이력 행의 이름·색, 예약 상세에 쓴다.
    var assigneesById: [Int: Assignee] = [:]
    /// 매장 적립률(%) — 예약 상세에서 결제하면 자동 적립된다(`Store.effectivePointRate`).
    var pointRate: Int = 0

    @Environment(\.dismiss) private var dismiss
    @State private var showPointAdjust = false
    @State private var showPointRecharge = false
    @State private var showMerge = false
    /// 탭한 예약 — 웹 `/address`의 예약 카드 클릭(`onReservationClick`)과 같다.
    @State private var selectedReservation: Reservation?

    var body: some View {
        NavigationStack {
            List {
                Section("기본 정보") {
                    LabeledContent("이름", value: customer.name)
                    LabeledContent("연락처", value: customer.formattedTel)
                    if let points = customer.points {
                        LabeledContent("적립금", value: "\(points.formatted())P")
                    }
                    if let first = customer.firstVisitDate, !first.isEmpty {
                        LabeledContent("첫 방문", value: first)
                    }
                    if pointsEnabled {
                        Button("적립금 조정") { showPointAdjust = true }
                    }
                    if pointsEnabled, pointSettings?.enableRecharge == true {
                        Button("적립금 충전") { showPointRecharge = true }
                    }
                    if !mergeCandidates.isEmpty {
                        Button("다른 고객과 합치기") { showMerge = true }
                    }
                }

                if stats.total > 0 {
                    Section("방문 통계") {
                        HStack {
                            // 웹과 같은 4버킷 — 상태 없는 지난 예약은 '완료'로 친다.
                            let buckets = CustomerStats.EffectiveStatus.allCases
                            ForEach(Array(buckets.indices), id: \.self) { index in
                                if index > 0 { Divider() }
                                statCell(buckets[index], stats.count(buckets[index]))
                            }
                        }
                    }
                }

                if let tags = customer.memoTags, !tags.isEmpty {
                    Section("메모 태그") {
                        FlowTags(tags: tags)
                    }
                }

                if let histories = customer.pointHistories, !histories.isEmpty {
                    Section("적립금 이력") {
                        ForEach(histories) { PointHistoryRow(entry: $0) }
                    }
                }

                // 웹은 예약/완료/취소/노쇼 그룹마다 건수를 달고 나눠 보여준다.
                ForEach(reservationGroups) { group in
                    Section("\(group.status.label) (\(group.items.count))") {
                        ForEach(group.items.prefix(10)) { reservation in
                            let rowAssignee = assignee(reservation.assigneeId)
                            Button {
                                selectedReservation = reservation
                            } label: {
                                ReservationInfoCard(
                                    reservation: reservation,
                                    serviceColorMap: serviceColorMap,
                                    assigneeName: rowAssignee?.name,
                                    assigneeColor: Color(hex: rowAssignee?.color),
                                    showDate: true,
                                    showPrice: true,
                                    // 그룹이 판정한 유효 상태로 덮는다. `displayState`는 날짜를 몰라
                                    // '완료' 그룹 안에서도 파란 '예약' 배지를 그려버린다.
                                    statusOverride: group.status
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        if group.items.count > 10 {
                            Text("외 \(group.items.count - 10)건")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(customer.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        // dismiss() 없이 상위 sheet(item:) 값만 .edit로 바꿔 시트를 교체.
                        Button("수정") { onEdit(customer) }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .sheet(isPresented: $showPointAdjust) {
                PointAdjustView(
                    customer: customer,
                    service: service,
                    onCompleted: { await onChanged(); dismiss() }
                )
            }
            .sheet(isPresented: $showPointRecharge) {
                PointRechargeView(
                    customer: customer,
                    rules: pointSettings?.rechargeRules ?? [],
                    service: service,
                    onCompleted: { await onChanged(); dismiss() }
                )
            }
            .sheet(item: $selectedReservation) { reservation in
                ReservationDetailView(
                    reservation: reservation,
                    customer: customer,
                    assignee: assignee(reservation.assigneeId),
                    serviceColorMap: serviceColorMap,
                    isNewCustomer: customer.isNewCustomerVisit(on: reservation.date),
                    service: service,
                    // 상태·결제가 바뀌면 상위를 다시 읽되 고객 상세는 닫지 않는다.
                    onChanged: { await onChanged() },
                    assigneeName: { [assigneesById] id in id.flatMap { assigneesById[$0] }?.name ?? "미지정" },
                    pointRate: pointRate
                )
            }
            .sheet(isPresented: $showMerge) {
                CustomerMergePicker(
                    source: customer,
                    candidates: mergeCandidates,
                    reservationCounts: reservationCounts,
                    service: service,
                    onCompleted: { await onChanged(); dismiss() }
                )
            }
        }
    }

    private func assignee(_ id: Int?) -> Assignee? { id.flatMap { assigneesById[$0] } }

    private func statCell(_ status: CustomerStats.EffectiveStatus, _ count: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.weight(.bold))
                .foregroundStyle(status.tone.foreground)
                .monospacedDigit()
            Text(status.label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FlowTags: View {
    let tags: [CustomerMemoTag]

    var body: some View {
        // 단순 래핑 없이 세로 나열(간단 스켈레톤). 필요 시 Layout으로 개선.
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { item in
                let tag = item.element
                HStack(spacing: 6) {
                    ColorDot(color: Color(hex: tag.color) ?? .gray, size: 10)
                    Text(tag.text)
                }
            }
        }
    }
}

private struct PointHistoryRow: View {
    let entry: PointHistoryEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.type.label).font(.subheadline)
                Text(entry.description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(signed(entry.delta))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(entry.delta >= 0 ? Color.blue : Color.red)
                Text("잔액 \(entry.balance.formatted())P").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func signed(_ value: Int) -> String {
        (value >= 0 ? "+" : "") + "\(value.formatted())P"
    }
}
