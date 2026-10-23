import Foundation

/// 서비스 이름·가격·소요시간을 바꿨을 때 앞으로의 예약에 반영(순수) — 웹 `buildServiceCatalogReservationUpdates`·안드로이드 `updateService`.
///
/// 대상: 오늘 이후 · 상태 예약(active) · 결제 전 · 그 서비스를 포함한 예약. 지난·취소·결제한 예약은 옛 이름 그대로.
/// 손댄 값은 지킨다 — 저장된 가격이 옛 카탈로그 합계와 다르면 가격 유지, 저장된 소요시간이 옛 합계와 다르면 종료시각 유지.
enum ServiceRename {
    struct Update: Encodable, Equatable {
        let prev: Reservation
        let updated: Reservation
    }

    static func reservationUpdates(_ reservations: [Reservation], originalName: String, updatedName: String,
                                   prevCatalog: [ServiceItem], nextCatalog: [ServiceItem], today: String) -> [Update] {
        let oldMap = Dictionary(prevCatalog.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let newMap = Dictionary(nextCatalog.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let oldNames = Set(oldMap.keys)

        return reservations.compactMap { r -> Update? in
            guard (r.status ?? .active) == .active, r.date >= today, !r.hasCompletedPayment else { return nil }
            let names = ServiceColor.parseServiceString(r.service, knownNames: oldNames)
            guard names.contains(originalName) else { return nil }

            let priceManual = (r.price ?? 0) != sum(names, oldMap, \.price)
            let durationManual = minutesBetween(r.startTime, r.endTime) != sum(names, oldMap, \.durationMinutes)

            let newNames = names.map { $0 == originalName ? updatedName : $0 }
            var updated = r
            updated.service = newNames.joined(separator: "+")
            updated.price = priceManual ? (r.price ?? 0) : sum(newNames, newMap, \.price)
            if !durationManual { updated.endTime = endTime(r.startTime, plus: sum(newNames, newMap, \.durationMinutes)) }

            guard updated.service != r.service || updated.price != (r.price ?? 0) || updated.endTime != r.endTime else { return nil }
            return Update(prev: r, updated: updated)
        }
    }

    private static func sum(_ names: [String], _ map: [String: ServiceItem], _ key: KeyPath<ServiceItem, Int>) -> Int {
        names.reduce(0) { $0 + (map[$1]?[keyPath: key] ?? 0) }
    }

    private static func minutesBetween(_ start: String, _ end: String) -> Int {
        guard let s = ReservationOverlap.minutes(start), let e = ReservationOverlap.minutes(end) else { return -1 }
        return e - s
    }

    /// 웹 `calcEndTime` — 24시를 넘으면 다음 날 시각으로 돈다.
    static func endTime(_ start: String, plus minutes: Int) -> String {
        let total = (ReservationOverlap.minutes(start) ?? 0) + minutes
        return String(format: "%02d:%02d", (total / 60) % 24, total % 60)
    }
}
