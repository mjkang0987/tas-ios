import SwiftUI
import Observation

@MainActor
@Observable
final class ServicesViewModel {
    var state: Loadable<[ServiceItem]> = .idle

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    /// Services grouped by category, category order preserved by first appearance.
    var grouped: [(category: String, items: [ServiceItem])] {
        let items = state.value ?? []
        var order: [String] = []
        var buckets: [String: [ServiceItem]] = [:]
        for item in items {
            if buckets[item.category] == nil { order.append(item.category) }
            buckets[item.category, default: []].append(item)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    func load() async {
        state = .loading
        do {
            let response = try await service.fetchServices()
            state = .loaded(response.services)
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

/// 서비스(시술) 카탈로그 — 웹의 설정 > `service` 탭에 대응.
struct ServicesView: View {
    @State private var viewModel = ServicesViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("서비스 불러오는 중…")
                case .failed(let message):
                    ContentUnavailableView("불러오지 못했습니다", systemImage: "exclamationmark.triangle", description: Text(message))
                case .loaded:
                    List {
                        ForEach(viewModel.grouped, id: \.category) { group in
                            Section(group.category) {
                                ForEach(group.items) { ServiceRow(item: $0) }
                            }
                        }
                    }
                    .refreshable { await viewModel.load() }
                }
            }
            .navigationTitle("서비스")
        }
        .task { await viewModel.load() }
    }
}

private struct ServiceRow: View {
    let item: ServiceItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.body.weight(.medium))
                Text("\(item.durationMinutes)분").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(item.price.formatted())원").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ServicesView()
}
