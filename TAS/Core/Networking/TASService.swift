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

    /// 고객 병합 — POST /api/customers/merge (body=`{sourceIds, targetId}`).
    @discardableResult
    func mergeCustomers(sourceId: Int, targetId: Int) async throws -> Bool {
        if guest.isActive { return guest.mergeCustomers(sourceId: sourceId, targetId: targetId) }
        struct Body: Encodable { let sourceIds: [Int]; let targetId: Int }
        struct Resp: Decodable { let merged: Bool? }
        let resp: Resp = try await client.post("api/customers/merge", body: Body(sourceIds: [sourceId], targetId: targetId))
        return resp.merged ?? true
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

    /// 담당자 목록 전체 저장 — PUT /api/assignees (body=`{assignees}`, 응답 `{assignees}`).
    /// 웹과 동일한 일괄 교체 모델(추가·수정 모두 전체 배열을 보낸다).
    @discardableResult
    func saveAssignees(_ assignees: [Assignee]) async throws -> [Assignee] {
        if guest.isActive { return guest.saveAssignees(assignees) }
        struct Body: Encodable { let assignees: [Assignee] }
        let env: AssigneesResponse = try await client.put("api/assignees", body: Body(assignees: assignees))
        return env.assignees
    }

    /// 담당자 삭제 — DELETE /api/assignees (body=`{id}`). 예약은 보존, assigneeId만 분리.
    func deleteAssignee(id: Int) async throws {
        if guest.isActive { guest.deleteAssignee(id: id); return }
        struct Body: Encodable { let id: Int }
        let _: OkResponse = try await client.delete("api/assignees", body: Body(id: id))
    }

    /// 담당자 병합 — POST /api/assignees/merge (body=`{sourceId, targetId}`). 예약은 target으로 이동.
    @discardableResult
    func mergeAssignees(sourceId: Int, targetId: Int) async throws -> Bool {
        if guest.isActive { return guest.mergeAssignees(sourceId: sourceId, targetId: targetId) }
        struct Body: Encodable { let sourceId: Int; let targetId: Int }
        struct Resp: Decodable { let merged: Bool? }
        let resp: Resp = try await client.post("api/assignees/merge", body: Body(sourceId: sourceId, targetId: targetId))
        return resp.merged ?? true
    }

    /// 서비스 카탈로그 + 카테고리 색 저장 — PUT /api/services (body=`{services, categoryBaseColors}`).
    @discardableResult
    func saveServices(_ services: [ServiceItem], categoryBaseColors: [String: String]) async throws -> ServicesResponse {
        if guest.isActive { return guest.saveServices(services, categoryBaseColors: categoryBaseColors) }
        struct Body: Encodable { let services: [ServiceItem]; let categoryBaseColors: [String: String] }
        return try await client.put("api/services", body: Body(services: services, categoryBaseColors: categoryBaseColors))
    }

    // MARK: - Notices — /api/notices
    func fetchNotices() async throws -> NoticesResponse {
        if guest.isActive { return guest.noticesResponse }
        return try await client.get("api/notices")
    }

    /// 공지 생성 — POST /api/notices (응답=생성된 공지).
    @discardableResult
    func createNotice(_ notice: StoreNotice) async throws -> StoreNotice {
        if guest.isActive { return guest.createNotice(notice) }
        struct Body: Encodable {
            let category: NoticeCategory; let title: String; let body: String
            let visible: Bool; let pinned: Bool
        }
        return try await client.post("api/notices", body: Body(
            category: notice.category, title: notice.title, body: notice.body,
            visible: notice.visible, pinned: notice.pinned))
    }

    /// 공지 수정 — PUT /api/notices (body에 id 포함, 응답 `{ok}`).
    @discardableResult
    func updateNotice(_ notice: StoreNotice) async throws -> StoreNotice {
        if guest.isActive { return guest.updateNotice(notice) }
        struct Body: Encodable {
            let id: String; let category: NoticeCategory; let title: String; let body: String
            let visible: Bool; let pinned: Bool
        }
        let _: OkResponse = try await client.put("api/notices", body: Body(
            id: notice.id, category: notice.category, title: notice.title, body: notice.body,
            visible: notice.visible, pinned: notice.pinned))
        return notice
    }

    /// 공지 삭제 — DELETE /api/notices (body=`{id}`).
    func deleteNotice(id: String) async throws {
        if guest.isActive { guest.deleteNotice(id: id); return }
        struct Body: Encodable { let id: String }
        struct Resp: Decodable { let deleted: Bool? }
        let _: Resp = try await client.delete("api/notices", body: Body(id: id))
    }

    // MARK: - Coupons — /api/coupons (상품 등록만; 발급·차감은 웹도 추후)
    func fetchCoupons() async throws -> CouponsResponse {
        if guest.isActive { return guest.couponsResponse }
        return try await client.get("api/coupons")
    }

    @discardableResult
    func createCoupon(_ p: CouponProduct) async throws -> CouponProduct {
        if guest.isActive { return guest.createCoupon(p) }
        struct Body: Encodable {
            let name: String; let discountType: CouponDiscountType; let discountValue: Int
            let maxDiscount: Int?; let minOrderAmount: Int?; let validDays: Int?; let code: String?
        }
        struct Resp: Decodable { let product: CouponProduct? }
        let resp: Resp = try await client.post("api/coupons", body: Body(
            name: p.name, discountType: p.discountType, discountValue: p.discountValue,
            maxDiscount: p.maxDiscount, minOrderAmount: p.minOrderAmount, validDays: p.validDays, code: p.code))
        return resp.product ?? p
    }

    @discardableResult
    func updateCoupon(_ p: CouponProduct) async throws -> CouponProduct {
        if guest.isActive { return guest.updateCoupon(p) }
        struct Body: Encodable {
            let id: String; let name: String; let discountType: CouponDiscountType; let discountValue: Int
            let maxDiscount: Int?; let minOrderAmount: Int?; let validDays: Int?; let code: String?; let status: String
        }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp = try await client.put("api/coupons", body: Body(
            id: p.id, name: p.name, discountType: p.discountType, discountValue: p.discountValue,
            maxDiscount: p.maxDiscount, minOrderAmount: p.minOrderAmount, validDays: p.validDays, code: p.code, status: p.status))
        return p
    }

    func deleteCoupon(id: String) async throws {
        if guest.isActive { guest.deleteCoupon(id: id); return }
        struct Body: Encodable { let id: String }
        struct Resp: Decodable { let deleted: Bool?; let archived: Bool? }
        let _: Resp = try await client.delete("api/coupons", body: Body(id: id))
    }

    // MARK: - Memberships — /api/memberships (상품 등록만; 발급·차감은 웹도 후속)
    func fetchMemberships() async throws -> MembershipsResponse {
        if guest.isActive { return guest.membershipsResponse }
        return try await client.get("api/memberships")
    }

    @discardableResult
    func createMembership(_ p: MembershipProduct) async throws -> MembershipProduct {
        if guest.isActive { return guest.createMembership(p) }
        struct Body: Encodable { let name: String; let totalCount: Int?; let validDays: Int?; let price: Int }
        struct Resp: Decodable { let product: MembershipProduct? }
        let resp: Resp = try await client.post("api/memberships", body: Body(
            name: p.name, totalCount: p.totalCount, validDays: p.validDays, price: p.price))
        return resp.product ?? p
    }

    @discardableResult
    func updateMembership(_ p: MembershipProduct) async throws -> MembershipProduct {
        if guest.isActive { return guest.updateMembership(p) }
        struct Body: Encodable {
            let id: String; let name: String; let totalCount: Int?; let validDays: Int?; let price: Int; let status: String
        }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp = try await client.put("api/memberships", body: Body(
            id: p.id, name: p.name, totalCount: p.totalCount, validDays: p.validDays, price: p.price, status: p.status))
        return p
    }

    func deleteMembership(id: String) async throws {
        if guest.isActive { guest.deleteMembership(id: id); return }
        struct Body: Encodable { let id: String }
        struct Resp: Decodable { let deleted: Bool?; let archived: Bool? }
        let _: Resp = try await client.delete("api/memberships", body: Body(id: id))
    }

    // MARK: - Store — /api/store
    func fetchStore() async throws -> Store {
        if guest.isActive { return guest.syntheticStore }
        return try await client.get("api/store")
    }

    /// 매장 기본 정보 저장(이름·기능 토글) — PATCH /api/store.
    /// 응답은 부분 echo라 Store로 못 받으므로, 성공 시 입력을 현재 매장에 반영해 돌려준다.
    @discardableResult
    func updateStore(current: Store, name: String, shopType: String?, usePointSystem: Bool, useMembershipSystem: Bool, useOnlineBooking: Bool) async throws -> Store {
        if guest.isActive {
            return guest.updateStoreSettings(name: name, shopType: shopType, usePointSystem: usePointSystem,
                                             useMembershipSystem: useMembershipSystem, useOnlineBooking: useOnlineBooking)
        }
        struct Body: Encodable {
            let storeName: String
            let shopType: String?
            let usePointSystem: Bool
            let useMembershipSystem: Bool
            let useOnlineBooking: Bool
        }
        // 응답은 부분 echo(id/name 없음) → error 여부만 확인.
        struct PatchResponse: Decodable { let error: String? }
        let resp: PatchResponse = try await client.patch("api/store", body: Body(
            storeName: name, shopType: shopType, usePointSystem: usePointSystem,
            useMembershipSystem: useMembershipSystem, useOnlineBooking: useOnlineBooking))
        if let error = resp.error { throw APIError.server(status: 400, message: error) }
        var updated = current
        updated.name = name
        updated.shopType = shopType
        updated.usePointSystem = usePointSystem
        updated.useMembershipSystem = useMembershipSystem
        updated.useOnlineBooking = useOnlineBooking
        return updated
    }

    /// 영업시간·휴무 저장 — PUT /api/store (body=`{businessHours, closedDates, closedWeekdays}`).
    @discardableResult
    func updateSchedule(current: Store, businessHours: BusinessHours, closedDates: [String], closedWeekdays: [Int]) async throws -> Store {
        if guest.isActive {
            return guest.updateSchedule(businessHours: businessHours, closedDates: closedDates, closedWeekdays: closedWeekdays)
        }
        struct Body: Encodable { let businessHours: BusinessHours; let closedDates: [String]; let closedWeekdays: [Int] }
        struct Resp: Decodable { let error: String? }
        let resp: Resp = try await client.put("api/store", body: Body(businessHours: businessHours, closedDates: closedDates, closedWeekdays: closedWeekdays))
        if let e = resp.error { throw APIError.server(status: 400, message: e) }
        var updated = current
        updated.businessHours = businessHours
        updated.closedDates = closedDates
        updated.closedWeekdays = closedWeekdays
        return updated
    }

    /// 적립금 설정 저장 — PUT /api/store (body=`{pointSettings}`).
    @discardableResult
    func updatePointSettings(current: Store, pointSettings: PointSettings) async throws -> Store {
        if guest.isActive { return guest.updatePointSettings(pointSettings) }
        struct Body: Encodable { let pointSettings: PointSettings }
        struct Resp: Decodable { let error: String? }
        let resp: Resp = try await client.put("api/store", body: Body(pointSettings: pointSettings))
        if let e = resp.error { throw APIError.server(status: 400, message: e) }
        var updated = current
        updated.pointSettings = pointSettings
        return updated
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
