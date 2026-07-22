import Foundation

/// High-level, typed access to the takeaseat (TAS) data API.
/// Mirrors the endpoints documented in the `tas` repo (`index.md` §백엔드 API).
struct TASService {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    // MARK: - Reservations — /api/reservations
    func fetchReservations() async throws -> ReservationsResponse {
        try await client.get("api/reservations")
    }

    @discardableResult
    func createReservation(_ reservation: Reservation) async throws -> Reservation {
        try await client.post("api/reservations", body: reservation)
    }

    @discardableResult
    func updateReservation(_ reservation: Reservation) async throws -> Reservation {
        try await client.put("api/reservations", body: reservation)
    }

    // MARK: - Customers — /api/customers
    func fetchCustomers() async throws -> CustomersResponse {
        try await client.get("api/customers")
    }

    @discardableResult
    func upsertCustomer(_ customer: Customer) async throws -> Customer {
        try await client.post("api/customers", body: customer)
    }

    // MARK: - Services — /api/services
    func fetchServices() async throws -> ServicesResponse {
        try await client.get("api/services")
    }

    // MARK: - Assignees — /api/assignees
    func fetchAssignees() async throws -> AssigneesResponse {
        try await client.get("api/assignees")
    }

    // MARK: - Store — /api/store
    func fetchStore() async throws -> Store {
        try await client.get("api/store")
    }

    // MARK: - Session / stores — /api/user/stores
    func fetchStores() async throws -> [Store] {
        try await client.get("api/user/stores")
    }
}
