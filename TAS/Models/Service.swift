import Foundation

/// 공개 예약 페이지 다국어 표시명 — {en?, ja?, zh?}
struct NameI18n: Codable, Hashable {
    var en: String?
    var ja: String?
    var zh: String?
}

/// 서비스(시술) — services/model.ts `ServiceItem`
/// The web model keys services by `name`, so we synthesize `id` from it for SwiftUI.
struct ServiceItem: Codable, Identifiable, Hashable {
    var name: String
    var durationMinutes: Int
    var category: String
    var price: Int
    var nameI18n: NameI18n?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, durationMinutes, category, price, nameI18n
    }
}

/// GET /api/services response envelope.
struct ServicesResponse: Codable {
    var services: [ServiceItem]
    var categoryBaseColors: [String: String]
}
