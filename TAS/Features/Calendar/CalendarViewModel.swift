import Foundation
import Observation

@MainActor
@Observable
final class CalendarViewModel {
    var state: Loadable<[Reservation]> = .idle

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    /// Reservations for the given day key ("YYYY-MM-DD"), sorted by start time.
    func reservations(on dateKey: String) -> [Reservation] {
        (state.value ?? [])
            .filter { $0.date == dateKey }
            .sorted { $0.startTime < $1.startTime }
    }

    func load() async {
        state = .loading
        do {
            let response = try await service.fetchReservations()
            state = .loaded(response.reservations)
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
