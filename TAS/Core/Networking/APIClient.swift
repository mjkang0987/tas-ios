import Foundation

/// Thin async/await HTTP client for the takeaseat (TAS) backend.
///
/// Auth uses the mobile Bearer token from `KeychainTokenStore` (obtained via the
/// mobile-auth bridge). The server's `getApiSession` accepts either this Bearer
/// token or the web NextAuth cookie.
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = AppConfig.apiBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Public request surface

    func get<Response: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> Response {
        try await send(path, method: "GET", query: query, body: Optional<Empty>.none)
    }

    @discardableResult
    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await send(path, method: "POST", body: body)
    }

    @discardableResult
    func put<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await send(path, method: "PUT", body: body)
    }

    @discardableResult
    func patch<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await send(path, method: "PATCH", body: body)
    }

    @discardableResult
    func delete<Response: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> Response {
        try await send(path, method: "DELETE", query: query, body: Optional<Empty>.none)
    }

    /// body를 실어 보내는 DELETE — 웹 예약/고객 삭제가 `{ id }`를 본문으로 받는다.
    @discardableResult
    func delete<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await send(path, method: "DELETE", body: body)
    }

    // MARK: - Core

    private func send<Body: Encodable, Response: Decodable>(
        _ path: String,
        method: String,
        query: [String: String] = [:],
        body: Body?
    ) async throws -> Response {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 모바일 Bearer 토큰(있으면). 서버 getApiSession이 쿠키 대신 이걸 인식한다.
        if let token = KeychainTokenStore.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Non-HTTP response")
        }

        switch http.statusCode {
        case 200...299:
            if data.isEmpty, let empty = EmptyResponse() as? Response {
                return empty
            }
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw APIError.decoding(String(describing: error))
            }
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        default:
            throw APIError.server(status: http.statusCode, message: Self.extractMessage(from: data))
        }
    }

    private static func extractMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (object["error"] as? String) ?? (object["message"] as? String)
    }
}

/// Placeholder for requests without a body.
private struct Empty: Encodable {}

/// Decodable placeholder for endpoints that return no meaningful body.
struct EmptyResponse: Decodable {}
