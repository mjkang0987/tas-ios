import Foundation
import Observation

@MainActor
@Observable
final class CustomersViewModel {
    var state: Loadable<[Customer]> = .idle
    var searchText = ""

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    var filtered: [Customer] {
        let all = (state.value ?? []).sorted { $0.name < $1.name }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        let digits = query.filter(\.isNumber)
        return all.filter { customer in
            customer.name.localizedCaseInsensitiveContains(query)
                || (!digits.isEmpty && customer.tel.contains(digits))
        }
    }

    func load() async {
        state = .loading
        do {
            let response = try await service.fetchCustomers()
            state = .loaded(response.customers)
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
