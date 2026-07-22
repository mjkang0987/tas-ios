import SwiftUI
import Observation

@MainActor
@Observable
final class ServicesViewModel {
    struct Data {
        var services: [ServiceItem]
        var categoryBaseColors: [String: String]
    }

    var state: Loadable<Data> = .idle

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    /// 카테고리별 그룹(첫 등장 순서 유지).
    var grouped: [(category: String, items: [ServiceItem])] {
        let items = state.value?.services ?? []
        var order: [String] = []
        var buckets: [String: [ServiceItem]] = [:]
        for item in items {
            if buckets[item.category] == nil { order.append(item.category) }
            buckets[item.category, default: []].append(item)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    /// 카테고리 색 — 매장 커스텀 우선(웹 getCategoryBaseColor).
    func color(for category: String) -> Color {
        ServiceColor.categoryColor(category, storeMap: state.value?.categoryBaseColors ?? [:])
    }

    func load() async {
        state = .loading
        do {
            let response = try await service.fetchServices()
            state = .loaded(Data(services: response.services, categoryBaseColors: response.categoryBaseColors))
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
            LoadableView(state: viewModel.state, loadingText: "서비스 불러오는 중…") { _ in
                List {
                    ForEach(viewModel.grouped, id: \.category) { group in
                        Section {
                            ForEach(group.items) { item in
                                ServiceRow(item: item, color: viewModel.color(for: group.category))
                            }
                        } header: {
                            HStack(spacing: 6) {
                                ColorDot(color: viewModel.color(for: group.category))
                                Text(group.category)
                            }
                        }
                    }
                }
                .refreshable { await viewModel.load() }
            }
            .navigationTitle("서비스")
        }
        .task { await viewModel.load() }
    }
}

private struct ServiceRow: View {
    let item: ServiceItem
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            ColorAccentBar(color: color, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.body.weight(.medium))
                Text("\(item.durationMinutes)분").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatWon(item.price)).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ServicesView()
}
