import XCTest
@testable import TAS

/// 로그인 모드 고객 저장 — 등록은 POST(생성 전용, 서버가 번호를 다시 정할 수 있다), 수정은 PUT `{customers: […]}`.
/// (POST 로 수정하면 서버가 생성 전용이라 적립금 조정·충전·수정이 남지 않는다 — tas 2026-10-16 이후.)
final class CustomerSaveTests: XCTestCase {

    /// 보낸 요청을 모으고 정해 둔 응답을 돌려준다.
    final class Stub: URLProtocol {
        nonisolated(unsafe) static var requests: [(method: String, path: String, body: [String: Any])] = []
        nonisolated(unsafe) static var postResponse = #"{"ok":true,"id":42}"#

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            var data = request.httpBody
            if data == nil, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 65_536)
                let n = stream.read(&buffer, maxLength: buffer.count)
                data = Data(buffer.prefix(max(n, 0)))
            }
            let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            Self.requests.append((request.httpMethod ?? "", request.url?.path ?? "", body))
            let json = request.httpMethod == "POST" ? Self.postResponse : #"{"customers":[]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private var service: TASService!

    override func setUp() {
        super.setUp()
        GuestStore.shared.isActive = false
        Stub.requests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        service = TASService(client: APIClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: config)))
    }

    func testCreateUsesServerAssignedIdAndSavesTagsWithPut() async throws {
        let saved = try await service.createCustomer(
            Customer(id: 7, name: "가온", tel: "01012345678", memoTags: [CustomerMemoTag(text: "VIP", color: "#E5484D")]))
        XCTAssertEqual(saved.id, 42) // 서버가 정한 번호
        XCTAssertEqual(Stub.requests.map(\.method), ["POST", "PUT"])
        let put = try XCTUnwrap(Stub.requests.last?.body["customers"] as? [[String: Any]])
        XCTAssertEqual(put.first?["id"] as? Int, 42)
    }

    func testCreateWithoutTagsIsPostOnly() async throws {
        _ = try await service.createCustomer(Customer(id: 7, name: "가온", tel: ""))
        XCTAssertEqual(Stub.requests.map(\.method), ["POST"])
    }

    func testUpdateIsPutWithCustomersArray() async throws {
        var c = Customer(id: 3, name: "하윤", tel: "01022223333", points: 5000)
        c.pointHistories = [PointHistoryEntry(id: "h1", type: .recharge, delta: 55000, balance: 55000, description: "적립금 기준 충전",
                                              createdAt: "2026-10-23T00:00:00Z", relatedReservationId: nil, paidAmount: 50000, paymentMethod: .card)]
        try await service.updateCustomer(c)
        XCTAssertEqual(Stub.requests.map(\.method), ["PUT"])
        XCTAssertEqual(Stub.requests.first?.path, "/api/customers")
        let sent = try XCTUnwrap((Stub.requests.first?.body["customers"] as? [[String: Any]])?.first)
        XCTAssertEqual(sent["id"] as? Int, 3)
        // 충전 받은 금액·결제수단이 같이 간다 — 서버가 매출로 잡는다
        let history = try XCTUnwrap((sent["pointHistories"] as? [[String: Any]])?.first)
        XCTAssertEqual(history["paidAmount"] as? Int, 50000)
        XCTAssertEqual(history["paymentMethod"] as? String, "카드")
    }
}
