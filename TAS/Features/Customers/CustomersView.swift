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
        case detail(DetailRoute)  // 고객 상세 · 펼친 행의 예약 상세
        case create
        var id: String {
            switch self {
            case .detail(let route): return "detail-\(route)"
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
                                rechargeRules: session.currentStore?.pointSettings?.rechargeRules ?? [],
                                onSave: { updated in
                                    try await TASService().updateCustomer(updated)
                                    await viewModel.load()
                                },
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
    @Environment(SessionStore.self) private var session
    private var labels: StoreLabels { session.labels }
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
                Text("최근 \(labels.service)").font(.caption2).foregroundStyle(.secondary)
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

/// 펼친 행 — 웹 `AddressCustomerTags`(메모 태그 바로 추가·삭제) · `AddressCustomerRecharge`(충전 + 최근 적립금 이력) ·
/// `AddressCustomerReservations`(상태별 예약). 바꾸면 바로 저장하고 목록을 다시 읽는다(웹과 같다).
private struct CustomerExpandedContent: View {
    let customer: Customer
    let groups: [CustomerStats.Group]
    let serviceColorMap: [String: String]
    let assigneesById: [Int: Assignee]
    let canRecharge: Bool
    let rechargeRules: [RechargeRule]
    let onSave: (Customer) async throws -> Void
    let onReservationTap: (Reservation) -> Void

    /// 편집 중인 태그 — 저장 뒤 다시 읽기 전에 또 더해도 앞의 것이 사라지지 않게 화면 쪽 사본으로 고친다. nil 이면 보기.
    @State private var draftTags: [CustomerMemoTag]?
    @State private var tagText = ""
    @State private var tagColor = MemoTagEditor.colors[0].hex
    /// 충전 금액 — 규칙 번호, nil 이면 직접 입력.
    @State private var ruleIndex: Int? = 0
    @State private var customAmount = 0
    @State private var paymentMethod: PaymentMethod = .card
    @State private var isSaving = false
    @State private var error: String?

    private var histories: [PointHistoryEntry] { (customer.pointHistories ?? []).reversed() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            memoTags
            if canRecharge { recharge }
            if let latest = histories.first {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("적립금 이력 (\(histories.count))")
                    if let id = latest.relatedReservationId, let reservation = groups.flatMap(\.items).first(where: { $0.id == id }) {
                        Button { onReservationTap(reservation) } label: { PointHistoryRow(entry: latest) }
                            .buttonStyle(.plain)
                            .accessibilityHint("예약 상세 열기")
                    } else {
                        PointHistoryRow(entry: latest)
                    }
                }
            }
            if let error, draftTags == nil {
                Text(error).font(.footnote).foregroundStyle(Color.dangerText)
            }
            reservations
        }
        .disabled(isSaving)
        .padding(.bottom, 4)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
    }

    // MARK: 메모 태그

    @ViewBuilder private var memoTags: some View {
        if let draft = draftTags {
            MemoTagEditor(
                tags: draft,
                text: $tagText,
                color: $tagColor,
                error: error,
                onAdd: {
                    let result = MemoTagEditor.adding(tagText, color: tagColor, to: draft)
                    error = result.error
                    guard result.error == nil, result.tags.count != draft.count else { return }
                    tagText = ""
                    saveTags(result.tags)
                },
                onRemove: { tag in saveTags(draft.filter { $0.text != tag.text }) },
                onDone: { draftTags = nil; tagText = ""; error = nil }
            )
        } else {
            let tags = customer.memoTags ?? []
            HStack(alignment: .top, spacing: 8) {
                if tags.isEmpty {
                    Text("메모 없음").font(.footnote).foregroundStyle(.secondary)
                } else {
                    WrapLayout(spacing: 6) { ForEach(Array(tags.enumerated()), id: \.offset) { MemoTagPill(tag: $0.element) } }
                }
                Spacer(minLength: 0)
                Button(tags.isEmpty ? "추가" : "수정") { draftTags = tags; error = nil }
                    .buttonStyle(.action())
                    .accessibilityLabel(tags.isEmpty ? "메모 태그 추가" : "메모 태그 수정")
            }
        }
    }

    private func saveTags(_ tags: [CustomerMemoTag]) {
        draftTags = tags
        var updated = customer
        updated.memoTags = tags
        save(updated)
    }

    // MARK: 충전

    private var recharge: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("적립금 충전")
                Spacer(minLength: 0)
                Text("현재 잔액 \(formatWon(customer.points ?? 0))").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Picker("충전 금액 선택", selection: $ruleIndex) {
                    ForEach(Array(rechargeRules.enumerated()), id: \.offset) { index, rule in
                        Text("\(formatWon(rule.baseAmount)) + \(formatWon(rule.bonusAmount))").tag(Optional(index))
                    }
                    Text("직접입력").tag(Int?.none)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Picker("충전 결제수단", selection: $paymentMethod) {
                    ForEach(PaymentMethod.received, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden() // 이름은 낭독기만 — 화면엔 고른 값만(웹 select 와 같다)
                Spacer(minLength: 0)
                Button("충전", action: charge).buttonStyle(.action(.primary))
            }
            if ruleIndex == nil {
                TextField("충전금액", value: $customAmount, format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("직접 입력 충전금액")
            }
        }
        // 매장 규칙이 줄어 고른 번호가 없어지면 첫 규칙(없으면 직접입력)으로
        .onAppear { if let i = ruleIndex, !rechargeRules.indices.contains(i) { ruleIndex = rechargeRules.isEmpty ? nil : 0 } }
    }

    private func charge() {
        let rule = ruleIndex.flatMap { rechargeRules.indices.contains($0) ? rechargeRules[$0] : nil }
        guard let updated = PointRecharge.charged(customer, rule: rule, custom: customAmount, method: paymentMethod,
                                                  now: ISO8601DateFormatter().string(from: Date()), id: UUID().uuidString) else {
            error = "충전 금액을 입력해주세요."; return
        }
        customAmount = 0
        save(updated)
    }

    private func save(_ updated: Customer) {
        isSaving = true
        Task {
            do { try await onSave(updated); error = nil } catch {
                self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isSaving = false
        }
    }

    // MARK: 예약

    @ViewBuilder private var reservations: some View {
        if groups.isEmpty {
            Text("등록된 데이터가 없습니다").font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        ForEach(groups) { group in
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("\(group.status.label) (\(group.items.count))")
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
}

#Preview {
    CustomersView()
        .environment(SessionStore())
}
