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
                        reservations: viewModel.reservations(for: customer.id),
                        serviceColorMap: viewModel.serviceColorMap,
                        onEdit: { activeSheet = .edit($0) },
                        pointsEnabled: session.currentStore?.usePointSystem ?? false,
                        pointSettings: session.currentStore?.pointSettings,
                        service: TASService(),
                        onChanged: { await viewModel.load() },
                        mergeCandidates: viewModel.allCustomers.filter { $0.id != customer.id },
                        reservationCounts: viewModel.reservationCounts
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
                List(items) { customer in
                    Button {
                        activeSheet = .detail(customer)
                    } label: {
                        CustomerRow(customer: customer)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .refreshable { await viewModel.load() }
            }
        }
    }
}

private struct CustomerRow: View {
    let customer: Customer

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(customer.name).font(.subheadline.weight(.medium))
                Text(customer.formattedTel).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let points = customer.points, points > 0 {
                Text("\(points.formatted())P")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}

#Preview {
    CustomersView()
        .environment(SessionStore())
}
