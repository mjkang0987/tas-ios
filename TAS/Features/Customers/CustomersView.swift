import SwiftUI

/// 고객 주소록 — 웹의 `/address` 화면에 대응하는 스켈레톤.
struct CustomersView: View {
    @State private var viewModel = CustomersViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("고객 불러오는 중…")
                case .failed(let message):
                    ContentUnavailableView("불러오지 못했습니다", systemImage: "exclamationmark.triangle", description: Text(message))
                case .loaded:
                    list
                }
            }
            .navigationTitle("고객")
            .searchable(text: $viewModel.searchText, prompt: "이름 또는 전화번호")
        }
        .task { await viewModel.load() }
    }

    private var list: some View {
        let items = viewModel.filtered
        return Group {
            if items.isEmpty {
                ContentUnavailableView.search
            } else {
                List(items) { CustomerRow(customer: $0) }
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
    }
}

#Preview {
    CustomersView()
}
