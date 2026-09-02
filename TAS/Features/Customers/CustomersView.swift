import SwiftUI

/// 고객 주소록 — 웹의 `/address` 화면에 대응.
struct CustomersView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel = CustomersViewModel()
    @State private var activeSheet: ActiveSheet?

    /// 상세/등록/수정 시트를 하나의 `.sheet(item:)`으로 통합(다중 sheet 충돌 회피).
    private enum ActiveSheet: Identifiable {
        case detail(Customer)
        case create
        case edit(Customer)
        var id: String {
            switch self {
            case .detail(let c): return "detail-\(c.id)"
            case .create: return "create"
            case .edit(let c): return "edit-\(c.id)"
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
                case .detail(let customer):
                    CustomerDetailView(
                        customer: customer,
                        stats: viewModel.stats(for: customer.id),
                        reservationGroups: viewModel.reservationGroups(for: customer.id),
                        serviceColorMap: viewModel.serviceColorMap,
                        onEdit: { activeSheet = .edit($0) },
                        pointsEnabled: session.currentStore?.usePointSystem ?? false,
                        pointSettings: session.currentStore?.pointSettings,
                        service: TASService(),
                        onChanged: { await viewModel.load() },
                        mergeCandidates: viewModel.allCustomers.filter { $0.id != customer.id },
                        reservationCounts: viewModel.reservationCounts,
                        assigneesById: viewModel.assigneesById,
                        pointRate: session.currentStore?.effectivePointRate ?? 0
                    )
                case .create:
                    CustomerFormView(
                        service: TASService(),
                        nextCustomerId: viewModel.nextCustomerId,
                        onSaved: { await viewModel.load() }
                    )
                case .edit(let customer):
                    CustomerFormView(
                        service: TASService(),
                        editing: customer,
                        onSaved: { await viewModel.load() }
                    )
                }
            }
        }
        .task { await viewModel.load() }
    }

    private var list: some View {
        let items = viewModel.filtered
        return Group {
            if items.isEmpty {
                ContentUnavailableView.search
            } else {
                let stats = viewModel.statsByCustomer
                let query = viewModel.searchText.trimmingCharacters(in: .whitespaces)
                List(items) { customer in
                    Button {
                        activeSheet = .detail(customer)
                    } label: {
                        CustomerRow(
                            customer: customer,
                            stats: stats[customer.id] ?? .empty,
                            serviceColorMap: viewModel.serviceColorMap,
                            searchQuery: query,
                            matchedMemoTags: viewModel.matchedMemoTags(for: customer)
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

/// 고객 목록 행 — 웹 `AddressCustomerSummary`가 접힌 상태에서 보여주는 것과 같은 정보:
/// 이름·연락처 / 최근 서비스 / 적립금 + 상태별 건수.
private struct CustomerRow: View {
    let customer: Customer
    let stats: CustomerStats.Summary
    let serviceColorMap: [String: String]
    /// 트림된 실제 검색어(없으면 하이라이트 없음).
    var searchQuery: String = ""
    /// 이 검색어로 매치된 메모 태그 — 이름/전화가 아니라 메모 때문에 뜬 결과의 근거로 보여준다.
    var matchedMemoTags: [CustomerMemoTag] = []

    private var nameMatchRange: Range<String.Index>? {
        guard !searchQuery.isEmpty else { return nil }
        return SearchHighlight.matchRange(in: customer.name, query: searchQuery, caseInsensitive: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                highlightedText(customer.name, range: nameMatchRange).font(.subheadline.weight(.medium))
                Text(customer.formattedTel).font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                // 적립금은 웹처럼 라벨과 함께 항상 보인다(0도) — 없다가 생기면 행 높이가 흔들린다.
                // 단위는 앱 전체가 쓰는 P로 맞춘다(상세·병합·조정 화면 모두 P).
                Text("적립금").font(.caption2).foregroundStyle(.secondary)
                Text("\((customer.points ?? 0).formatted())P")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .monospacedDigit()
            }

            if !matchedMemoTags.isEmpty {
                // 색 점 자체가 "이 메모 때문에 걸렸다"는 근거라 글자 안에 다시 마킹을 얹지 않는다
                // (상세 화면 `FlowTags`와 같은 표시 방식 재사용, 컨텍스트만 목록 행).
                HStack(spacing: 8) {
                    ForEach(Array(matchedMemoTags.enumerated()), id: \.offset) { item in
                        HStack(spacing: 4) {
                            ColorDot(color: Color(hex: item.element.color) ?? .gray, size: 8)
                            Text(item.element.text)
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text("최근 시술").font(.caption2).foregroundStyle(.secondary)
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
    }
}

#Preview {
    CustomersView()
        .environment(SessionStore())
}
