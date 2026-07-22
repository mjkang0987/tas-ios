import Foundation

/// Errors surfaced by `APIClient`.
enum APIError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized                 // 401 — 세션 없음/만료
    case forbidden                    // 403 — 권한 부족 (requireRole)
    case notFound                     // 404
    case server(status: Int, message: String?)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "잘못된 요청 주소입니다."
        case .unauthorized:
            return "로그인이 필요합니다."
        case .forbidden:
            return "권한이 없습니다."
        case .notFound:
            return "대상을 찾을 수 없습니다."
        case let .server(status, message):
            return message ?? "서버 오류 (\(status))"
        case let .decoding(detail):
            return "응답을 해석하지 못했습니다: \(detail)"
        case let .transport(detail):
            return "네트워크 오류: \(detail)"
        }
    }
}
