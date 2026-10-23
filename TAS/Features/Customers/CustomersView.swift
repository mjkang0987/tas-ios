import SwiftUI

/// 고객 주소록 — 웹의 `/address` 화면에 대응.
struct CustomersView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel = CustomersViewModel()
    @State private var activeSheet: ActiveSheet?
    /// 펼친 행(웹 `AddressCustomerRow` 의 open) — 여럿을 같이 펼칠 수 있다.
    @State private var openIds: Set<Int> = []

    /// 상세/등록 시트를 하나의 `.sheet(item:)`으로 통합(다중 sheet 충돌 회피).
    /// 고객 수정·예약 상세는 상세 위에 쌓인다(`DetailSheet`).
    private enum ActiveSheet: Identifiable {
        case detail(DetailRoute)  // 고객 상세 · 펼친 행의 예약 상세 · 메모 '수정'(고객 수정 폼)
        case recharge(Int)        // 고객 id — 펼친 행의 '적립금 충전'
        case create
        var id: String {
            switch self {
            case .detail(let route): return "detail-\(route)"
            case .recharge(let id): return "recharge-\(id)"
            case .create: return "create"
            }
        }
    }

    var body: some View {
        NavigationStack {
            LoadableView(state: viewModel.state, loadingText: "고객 불러오는 중…") { _ in
                list
            }
            .navigationTitle("고객")
            .searchable(text: $viewModel.searchText, prompt: "이름 또는 전화번호")
            .toolbar {
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
                case .detail(let route):
                    if let data = viewModel.detailData {
                        DetailSheet(route: route, data: data, reload: { await viewModel.load() })
                    }
                case .recharge(let id):
                    if let customer = viewModel.state.value?.customers.first(where: { $0.id == id }) {
                        PointRechargeView(
                            customer: customer,
                            rules: session.currentStore?.pointSettings?.rechargeRules ?? [],
                            onCompleted: { await viewModel.load() }
                        )
                    }
                case .create:
                    CustomerFormView(
                        service: TASService(),
                        nextCustomerId: viewModel.nextCustomerId,
                        onSaved: { await viewModel.load() }
                    )
                }
            }
        }
        .task { await viewModel.load() }
    }

    private var list: some View {
        let result = viewModel.filterResult
        let items = result.customers
        return Group {
            if items.isEmpty {
                ContentUnavailableView.search
            } else {
                let stats = viewModel.statsByCustomer
                let query = viewModel.trimmedSearchQuery
                let data = viewModel.state.value
                // 적립금 충전은 매장이 적립금·충전을 둘 다 켰을 때만(웹 `enableRecharge`).
                let canRecharge = session.currentStore?.usePointSystem == true
                    && session.currentStore?.pointSettings?.enableRecharge == true
                List(items) { customer in
                    let isOpen = openIds.contains(customer.id)
                    VStack(alignment: .leading, spacing: 12) {
                        CustomerRow(
                            customer: customer,
                            stats: stats[customer.id] ?? .empty,
                            serviceColorMap: viewModel.serviceColorMap,
                            searchQuery: query,
                            matchedMemoTags: result.matchedMemoTags[customer.id] ?? [],
                            isOpen: isOpen,
                            onNameTap: { activeSheet = .detail(.customer(customer.id)) },
                            onToggle: {
                                if isOpen { openIds.remove(customer.id) } else { openIds.insert(customer.id) }
                            }
                        )
                        if isOpen {
                            CustomerExpandedContent(
                                customer: customer,
                                groups: CustomerStats.groups(data?.reservationsByCustomer[customer.id] ?? [], today: data?.today ?? ""),
                                serviceColorMap: viewModel.serviceColorMap,
                                assigneesById: data?.assigneesById ?? [:],
                                canRecharge: canRecharge,
                                onEditTags: { activeSheet = .detail(.editCustomer(customer.id)) },
                                onRecharge: { activeSheet = .recharge(customer.id) },
                                onReservationTap: { activeSheet = .detail(.reservation($0.id)) }
                            )
                        }
                    }
                    // 웹: 펼친 행은 아래 선을 굵게 — 목록 구분선 대신 펼침 상태를 알린다
                    .listRowSeparatorTint(isOpen ? .primary : nil)
                }
                .listStyle(.plain)
                .refreshable { await viewModel.load() }
            }
        }
    }
}

/// 고객 목록 행 — 웹 `AddressCustomerSummary`가 접힌 상태에서 보여주는 것과 같은 정보:
/// 이름·연락처 / 최근 서비스 / 적립금 + 상태별 건수.
/// 웹·안드로이드처럼 **이름을 누르면 고객 상세**, 행의 나머지(·오른쪽 화살표)를 누르면 펼친다.
private struct CustomerRow: View {
    let customer: Customer
    let stats: CustomerStats.Summary
    let serviceColorMap: [String: String]
    /// 트림된 실제 검색어(없으면 하이라이트 없음).
    var searchQuery: String = ""
    /// 이 검색어로 매치된 메모 태그 — 이름/전화가 아니라 메모 때문에 뜬 결과의 근거로 보여준다.
    var matchedMemoTags: [CustomerMemoTag] = []
    var isOpen = false
    var onNameTap: () -> Void = {}
    var onToggle: () -> Void = {}

    private var nameMatchRange: Range<String.Index>? {
        guard !searchQuery.isEmpty else { return nil }
        return SearchHighlight.matchRange(in: customer.name, query: searchQuery, caseInsensitive: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Button(action: onNameTap) {
                    highlightedText(customer.name, range: nameMatchRange)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.linkText)
                }
                .buttonStyle(.plain)
                .accessibilityHint("고객 상세 열기")
                Text(customer.formattedTel).font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                // 적립금은 웹처럼 라벨과 함께 항상 보인다(0도) — 없다가 생기면 행 높이가 흔들린다.
                // 단위는 앱 전체가 쓰는 P로 맞춘다(상세·병합·조정 화면 모두 P).
                Text("적립금").font(.caption2).foregroundStyle(.secondary)
                Text(formatWon(customer.points ?? 0))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .monospacedDigit()
                // 웹 StyledArrow — 펼치면 아래로. 글자 줄 높이는 그대로, 누르는 영역만 44로 넓힌다.
                Button(action: onToggle) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle().inset(by: -10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(customer.name) 예약 내역")
                .accessibilityValue(isOpen ? "펼침" : "접힘")
            }

            if !matchedMemoTags.isEmpty {
                // 색 점 자체가 "이 메모 때문에 걸렸다"는 근거라 글자 안에 다시 마킹을 얹지 않는다
                // (상세 화면 `FlowTags`와 같은 표시 방식 재사용, 컨텍스트만 목록 행).
                // 태그가 여럿이거나 길면 한 줄로는 잘리므로 상태 배지와 같은 WrapLayout으로 줄바꿈한다.
                WrapLayout(spacing: 8) {
                    ForEach(Array(matchedMemoTags.enumerated()), id: \.offset) { item in
                        HStack(spacing: 4) {
                            ColorDot(color: Color(hex: item.element.color) ?? .gray, size: 8)
                            // WrapLayout은 한 줄 높이로 측정하고 폭만 잘라 배치한다 — lineLimit(1)이
                            // 없으면 폭보다 긴 태그가 두 줄로 감싸이면서 레이아웃이 어긋난다.
                            Text(item.element.text).lineLimit(1)
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text("최근 서비스").font(.caption2).foregroundStyle(.secondary)
                if let recent = stats.recentService {
                    ServiceChipList(service: recent, colorMap: serviceColorMap, wraps: false)
                } else {
                    Text("-").font(.caption2).foregroundStyle(.tertiary)
                }
            }

            // 건수 0인 상태도 웹처럼 전부 노출한다 — 행마다 배지 개수가 달라지면 훑기 어렵다.
            // 좁은 폭·큰 글자에서 배지가 줄어들면 숫자가 잘리므로(웹은 flex-shrink: 0) 줄을 바꾼다.
            WrapLayout(spacing: 4) {
                ForEach(CustomerStats.EffectiveStatus.summaryOrder, id: \.self) { status in
                    StatusCountBadge(status: status, count: stats.count(status))
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        // 이름 버튼 밖 아무 데나 눌러도 펼친다(웹 행 클릭). 낭독기는 오른쪽 화살표 버튼으로.
        .onTapGesture(perform: onToggle)
    }
}

/// 펼친 행 — 웹 `AddressCustomerTags`(메모 태그) · `AddressCustomerRecharge`(충전) · `AddressCustomerReservations`(상태별 예약).
/// 메모 태그 바로 추가·삭제와 충전 칸은 아직 — '수정'·'적립금 충전'이 기존 화면을 연다.
private struct CustomerExpandedContent: View {
    let customer: Customer
    let groups: [CustomerStats.Group]
    let serviceColorMap: [String: String]
    let assigneesById: [Int: Assignee]
    let canRecharge: Bool
    let onEditTags: () -> Void
    let onRecharge: () -> Void
    let onReservationTap: (Reservation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                if let tags = customer.memoTags, !tags.isEmpty {
                    WrapLayout(spacing: 6) { ForEach(Array(tags.enumerated()), id: \.offset) { MemoTagPill(tag: $0.element) } }
                } else {
                    Text("메모 없음").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(customer.memoTags?.isEmpty == false ? "수정" : "추가", action: onEditTags)
                    .buttonStyle(.action())
                    .accessibilityLabel(customer.memoTags?.isEmpty == false ? "메모 태그 수정" : "메모 태그 추가")
            }

            if canRecharge {
                HStack {
                    Text("현재 잔액 \(formatWon(customer.points ?? 0))").font(.footnote).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("적립금 충전", action: onRecharge).buttonStyle(.action())
                }
            }

            if groups.isEmpty {
                Text("등록된 데이터가 없습니다").font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(group.status.label) (\(group.items.count))")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.items) { reservation in
                        let assignee = reservation.assigneeId.flatMap { assigneesById[$0] }
                        Button { onReservationTap(reservation) } label: {
                            ReservationInfoCard(
                                reservation: reservation,
                                serviceColorMap: serviceColorMap,
                                assigneeName: assignee?.name,
                                assigneeColor: Color(hex: assignee?.color),
                                showDate: true,
                                showPrice: true,
                                statusOverride: group.status
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }
}

#Preview {
    CustomersView()
        .environment(SessionStore())
}
