import Foundation

/// High-level, typed access to the takeaseat (TAS) data API.
/// Mirrors the endpoints documented in the `tas` repo (`index.md` §백엔드 API).
///
/// 게스트(오프라인) 모드에선 API 대신 `GuestStore`의 로컬 스냅샷을 읽고 쓴다
/// (웹 `if (shouldUseLocalDb()) { …localDb } else { fetch(/api/…) }`와 동일).
/// 화면/뷰모델은 이 타입만 거치므로 모드 분기를 몰라도 된다.
struct TASService {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    private var guest: GuestStore { .shared }

    // MARK: - Reservations — /api/reservations
    func fetchReservations() async throws -> ReservationsResponse {
        if guest.isActive { return guest.reservationsResponse }
        return try await client.get("api/reservations")
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
        if guest.isActive { return guest.customersResponse }
        return try await client.get("api/customers")
    }

    @discardableResult
    func upsertCustomer(_ customer: Customer) async throws -> Customer {
        try await client.post("api/customers", body: customer)
    }

    // MARK: - Services — /api/services
    func fetchServices() async throws -> ServicesResponse {
        if guest.isActive { return guest.servicesResponse }
        return try await client.get("api/services")
    }

    // MARK: - Assignees — /api/assignees
    func fetchAssignees() async throws -> AssigneesResponse {
        if guest.isActive { return guest.assigneesResponse }
        return try await client.get("api/assignees")
    }

    // MARK: - Store — /api/store
    func fetchStore() async throws -> Store {
        if guest.isActive { return guest.syntheticStore }
        return try await client.get("api/store")
    }

    // MARK: - Session / stores — /api/user/stores
    func fetchStores() async throws -> [Store] {
        if guest.isActive { return [guest.syntheticStore] }
        return try await client.get("api/user/stores")
    }

    // MARK: - Mobile auth — /api/mobile-auth/exchange
    /// 1회성 code + nonce를 access 토큰으로 교환한다.
    func exchangeMobileCode(code: String, nonce: String) async throws -> String {
        struct Body: Encodable { let code: String; let nonce: String }
        struct Response: Decodable { let accessToken: String; let expiresAt: Int }
        let response: Response = try await client.post("api/mobile-auth/exchange", body: Body(code: code, nonce: nonce))
        return response.accessToken
    }
}
