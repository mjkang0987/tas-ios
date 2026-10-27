import SwiftUI

/// 고객 상세 — 웹 `overlays/CustomerDetail`·안드로이드 `CustomerDetailSheet` 순서:
/// 연락처·적립금·노쇼 / 고객 메모 / 적립금 이력(최근 1건 + 더보기) / 예약 내역(5건씩).
struct CustomerDetailView: View {
    let customer: Customer
    var stats: CustomerStats.Summary = .empty
    /// 이 고객의 예약(순서 무관) — 웹처럼 날짜·시작 시간 오름차순으로 보여 준다.
    var reservations: [Reservation] = []
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
    /// 담당자 id → 담당자. 예약 이력 행의 이름·색에 쓴다.
    var assigneesById: [Int: Assignee] = [:]
    /// 예약을 누르면 그 예약 상세 — 상세는 `DetailSheet` 가 위에 쌓는다(웹 `/address` 의 `onReservationClick`).
    var onReservationTap: (Reservation) -> Void = { _ in }

    /// 웹 `PAGE_SIZE` — 예약 내역을 5건씩 더 보여 준다.
    private static let pageSize = 5
    /// 웹 `EMPTY_TEXT`.
    private static let emptyText = "등록된 데이터가 없습니다"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showPointAdjust = false
    @State private var showPointRecharge = false
    @State private var showMerge = false
    @State private var visibleCount = pageSize

    /// 웹은 최신 이력부터.
    private var histories: [PointHistoryEntry] { (customer.pointHistories ?? []).reversed() }

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section { infoRows }
                    section { memoSection }
                    section { pointHistorySection }
                    reservationSection.padding(.vertical, 10)
                }
                .padding(.horizontal, 14) // 웹 --modal-body-padding 좌우 14
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .reportsSheetHeight(content: contentHeight)
            .navigationTitle(customer.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 웹 머리의 버튼 줄에 없는 합치기는 "…" 메뉴로(지시자 2026-10-23)
                if !mergeCandidates.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("다른 고객과 합치기", systemImage: "arrow.triangle.merge") { showMerge = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("더보기")
                    }
                }
                if let onEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        // dismiss() 없이 상위 sheet(item:) 값만 .edit로 바꿔 시트를 교체.
                        Button("수정") { onEdit(customer) }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("닫기")
                }
            }
            .sheet(isPresented: $showPointAdjust) {
                PointAdjustView(
                    customer: customer,
                    service: service,
                    // 상세는 닫지 않는다 — 다시 읽은 잔액으로 다시 그린다
                    onCompleted: { await onChanged() }
                )
            }
            .sheet(isPresented: $showPointRecharge) {
                PointRechargeView(
                    customer: customer,
                    rules: pointSettings?.rechargeRules ?? [],
                    service: service,
                    // 상세는 닫지 않는다 — 다시 읽은 잔액으로 다시 그린다
                    onCompleted: { await onChanged() }
                )
            }
            .sheet(isPresented: $showMerge) {
                CustomerMergePicker(
                    source: customer,
                    candidates: mergeCandidates,
                    reservationCounts: reservationCounts,
                    service: service,
                    // 합치면 이 고객이 사라진다 — 먼저 닫아 '삭제된 고객입니다'가 비치지 않게
                    onCompleted: { dismiss(); await onChanged() }
                )
            }
        }
    }

    // MARK: - 칸

    /// 웹 `StyledCustomerContent` 한 칸 — 위아래 여백 + 아래 옅은 선.
    private func section<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        // 웹 StyledCustomerContent — 위아래 8, 칸 안 간격 8, 아래 옅은 선
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.dividerLine).frame(height: 1) }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.tasBody.weight(.bold)).foregroundStyle(Color.textPrimary).accessibilityAddTraits(.isHeader)
    }

    private var empty: some View {
        Text(Self.emptyText)
            .font(.tasMedium).foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity).padding(.vertical, 6)
    }

    /// 연락처·적립금·노쇼(웹 `StyledInfoList`). 방문 통계·첫 방문 줄은 웹에 없어 뺐다(지시자 2026-10-27).
    private var infoRows: some View {
        // 웹 StyledInfoList — 13 글자, 줄 간격 4, 이름 칸 고정 폭
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                label("연락처")
                if customer.formattedTel.isEmpty { Text("-") } else { TelLink(customer: customer) }
            }
            GridRow { label("적립금"); Text(formatWon(customer.points ?? 0)) }
            GridRow {
                label("노쇼")
                // 웹 StyledNoshowCount — 있으면 노쇼 색 굵게
                Text("\(stats.noshow)회")
                    .fontWeight(stats.noshow > 0 ? .bold : .regular)
                    .foregroundStyle(stats.noshow > 0 ? CustomerStats.EffectiveStatus.noshow.tone.foreground : .primary)
            }
        }
        .font(.tasMedium)
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(Color.textSecondary).gridColumnAlignment(.leading)
    }

    /// 고객 메모 — 웹 `CustomerMemoTagSection` 보기 모드. 추가·삭제는 "수정"(웹·안드로이드와 같다).
    @ViewBuilder private var memoSection: some View {
        title("고객 메모")
        if let tags = customer.memoTags, !tags.isEmpty {
            WrapLayout(spacing: 6) { ForEach(Array(tags.enumerated()), id: \.offset) { MemoTagPill(tag: $0.element) } }
        } else {
            empty
        }
    }

    /// 적립금 이력 — 최근 1건 + 더보기(전체). 예약에서 생긴 이력은 누르면 그 예약.
    @ViewBuilder private var pointHistorySection: some View {
        HStack(spacing: 8) {
            title("적립금 이력 (\(histories.count))")
            Spacer(minLength: 0)
            if histories.count > 1 {
                NavigationLink("더보기") { allHistories }
                    .font(.tasMedium.weight(.semibold))
                    // 누르는 자리는 44, 줄 높이는 글자만큼(제목 줄이 불어나지 않게)
                    .padding(.vertical, 12).contentShape(Rectangle()).padding(.vertical, -12)
                    .accessibilityHint("적립금 이력 전체 보기")
            }
        }
        if let latest = histories.first {
            historyRow(latest)
        } else {
            empty
        }
        if pointsEnabled {
            // 큰 글자에서는 두 버튼을 나란히 두면 글자가 잘린다 — 왼쪽에서 위아래로
            let large = typeSize.isAccessibilitySize
            let buttons = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 8))
            buttons {
                if !large { Spacer(minLength: 0) }
                Button("적립금 조정") { showPointAdjust = true }.buttonStyle(.action())
                if pointSettings?.enableRecharge == true {
                    Button("적립금 충전") { showPointRecharge = true }.buttonStyle(.action())
                }
            }
        }
    }

    private var allHistories: some View {
        List(histories) { historyRow($0) }
            .navigationTitle("적립금 이력 (\(histories.count))")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func historyRow(_ entry: PointHistoryEntry) -> some View {
        if let id = entry.relatedReservationId, let reservation = reservations.first(where: { $0.id == id }) {
            Button { onReservationTap(reservation) } label: { PointHistoryRow(entry: entry) }
                .buttonStyle(.plain)
                .accessibilityHint("예약 상세 열기")
        } else {
            PointHistoryRow(entry: entry)
        }
    }

    /// 예약 내역 — 5건씩 더보기(웹 `CustomerReservationCards`).
    @ViewBuilder private var reservationSection: some View {
        let list = RevenueStats.sortedChronologically(reservations) // 웹: 오래된 것부터
        let today = KST.dayKey.string(from: Date())
        VStack(alignment: .leading, spacing: 8) {
            title("예약 내역 (\(list.count))")
            if list.isEmpty { empty }
            ForEach(list.prefix(visibleCount)) { reservation in
                let rowAssignee = reservation.assigneeId.flatMap { assigneesById[$0] }
                Button {
                    onReservationTap(reservation)
                } label: {
                    ReservationInfoCard(
                        reservation: reservation,
                        serviceColorMap: serviceColorMap,
                        assigneeName: rowAssignee?.name,
                        assigneeColor: Color(hex: rowAssignee?.color),
                        showDate: true,
                        showPrice: true,
                        // 날짜로 판정한 상태로 덮는다 — `displayState`는 날짜를 몰라 지난 예약도 '예약'으로 그린다.
                        statusOverride: CustomerStats.effectiveStatus(reservation, today: today)
                    )
                }
                .buttonStyle(.plain)
            }
            if list.count > visibleCount {
                Button("더보기") { visibleCount += Self.pageSize }
                    .buttonStyle(.action())
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("예약 내역 더 보기")
            }
        }
    }
}

/// 적립금 이력 한 줄 — 고객 상세·고객 명단 펼친 행이 같이 쓴다.
struct PointHistoryRow: View {
    let entry: PointHistoryEntry

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.type.label).font(.tasMedium)
                Text(entry.description).font(.tasSmall).foregroundStyle(Color.textSecondary)
                Text(KST.timestampLabel(entry.createdAt)).font(.tasXSmall).foregroundStyle(Color.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(signed(entry.delta))
                    .font(.tasMedium.weight(.semibold))
                    .foregroundStyle(entry.delta >= 0 ? Color.blueText : Color.dangerText)
                Text("잔액 \(formatWon(entry.balance))").font(.tasXSmall).foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func signed(_ value: Int) -> String {
        (value >= 0 ? "+" : "") + formatWon(value)
    }
}
