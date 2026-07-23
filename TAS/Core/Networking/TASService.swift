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

    /// 예약 생성 — POST /api/reservations (body=Reservation, 응답 `{reservation}`).
    @discardableResult
    func createReservation(_ reservation: Reservation) async throws -> Reservation {
        if guest.isActive { return guest.createReservation(reservation) }
        let env: ReservationEnvelope = try await client.post("api/reservations", body: reservation)
        return env.reservation
    }

    /// 예약 수정 — PUT /api/reservations (body=`{prev, updated}`, 응답 `{reservation, historyEntry}`).
    @discardableResult
    func updateReservation(prev: Reservation, updated: Reservation) async throws -> Reservation {
        if guest.isActive { return guest.updateReservation(prev: prev, updated: updated) }
        struct Body: Encodable { let prev: Reservation; let updated: Reservation }
        let env: ReservationUpdateEnvelope = try await client.put("api/reservations", body: Body(prev: prev, updated: updated))
        return env.reservation
    }

    /// 예약 상태 변경(취소/노쇼/복원) — PATCH /api/reservations (body=`{id, status, reason?}`).
    @discardableResult
    func setReservationStatus(id: Int, status: ReservationStatus, reason: String? = nil) async throws -> Reservation {
        if guest.isActive {
            guard let r = guest.setReservationStatus(id: id, status: status) else { throw APIError.notFound }
            return r
        }
        struct Body: Encodable { let id: Int; let status: ReservationStatus; let reason: String? }
        let env: ReservationUpdateEnvelope = try await client.patch("api/reservations", body: Body(id: id, status: status, reason: reason))
        return env.reservation
    }

    /// 예약 영구 삭제 — DELETE /api/reservations (body=`{id}`, manager 권한).
    func deleteReservation(id: Int) async throws {
        if guest.isActive { guest.deleteReservation(id: id); return }
        struct Body: Encodable { let id: Int }
        let _: OkResponse = try await client.delete("api/reservations", body: Body(id: id))
    }

    // MARK: - Customers — /api/customers
    func fetchCustomers() async throws -> CustomersResponse {
        if guest.isActive { return guest.customersResponse }
        return try await client.get("api/customers")
    }

    /// 고객 등록/수정 — POST /api/customers (body=`{customer}`, 응답 `{ok, id}`).
    @discardableResult
    func upsertCustomer(_ customer: Customer) async throws -> Customer {
        if guest.isActive { return guest.upsertCustomer(customer) }
        struct Body: Encodable { let customer: Customer }
        let _: CustomerUpsertResponse = try await client.post("api/customers", body: Body(customer: customer))
        return customer
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

// MARK: - Write response envelopes

/// POST /api/reservations 응답.
struct ReservationEnvelope: Decodable {
    var reservation: Reservation
}

/// PUT/PATCH /api/reservations 응답.
struct ReservationUpdateEnvelope: Decodable {
    var reservation: Reservation
    var historyEntry: ReservationHistoryEntry?
}

/// `{ ok: true }` 형태 응답.
struct OkResponse: Decodable {
    var ok: Bool
}

/// POST /api/customers 응답(`{ ok, id }`).
struct CustomerUpsertResponse: Decodable {
    var ok: Bool
    var id: Int
}
