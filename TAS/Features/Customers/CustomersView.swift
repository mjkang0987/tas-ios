import SwiftUI

/// 고객 주소록 — 웹의 `/address` 화면에 대응.
struct CustomersView: View {
    @State private var viewModel = CustomersViewModel()
    @State private var selected: Customer?

    var body: some View {
        NavigationStack {
            LoadableView(state: viewModel.state, loadingText: "고객 불러오는 중…") { _ in
                list
            }
            .navigationTitle("고객")
            .searchable(text: $viewModel.searchText, prompt: "이름 또는 전화번호")
            .sheet(item: $selected) { customer in
                CustomerDetailView(
                    customer: customer,
                    stats: viewModel.stats(for: customer.id),
                    reservations: viewModel.reservations(for: customer.id)
                )
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
                        selected = customer
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
            VStack(alignment: .leading, spacing: 3) {
                Text(customer.name).font(.body.weight(.medium))
                Text(customer.formattedTel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let points = customer.points, points > 0 {
                Text("\(points.formatted())P")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

#Preview {
    CustomersView()
}
