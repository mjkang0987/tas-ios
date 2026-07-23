import Foundation

/// 업종(ShopType) 마스터 + 기본 서비스/색상 프리셋 — 웹
/// `features/store-settings/labels.ts`(SHOP_INDUSTRIES) 및
/// `features/services/default-services.ts`(DEFAULT_SERVICES, SHOP_CATEGORY_COLOR_MAP) 이식.
/// 게스트 온보딩에서 업종 선택 시 기본 서비스·카테고리 색을 시드하는 데 쓴다.
struct ShopIndustry: Identifiable, Hashable {
    let value: String       // ShopType 토큰 (예: "hair")
    let label: String
    let emoji: String
    let desc: String
    let category: String    // 상위 분류 키

    var id: String { value }
}

enum ShopCatalog {
    /// 상위 분류 표시명(순서 유지) — 웹 CATEGORY_NAMES.
    static let categories: [(key: String, name: String)] = [
        ("beauty", "뷰티"),
        ("food", "음식"),
        ("medical", "의료"),
        ("fitness", "피트니스"),
        ("class", "교육·클래스"),
        ("pet", "반려"),
        ("repair", "정비·수리"),
        ("space", "공간대여"),
        ("counsel", "상담"),
        ("etc", "기타"),
    ]

    /// 업종 마스터 — 웹 SHOP_INDUSTRIES.
    static let industries: [ShopIndustry] = [
        .init(value: "hair", label: "헤어샵", emoji: "✂️", desc: "커트·펌·염색·클리닉", category: "beauty"),
        .init(value: "nail", label: "네일샵", emoji: "💅", desc: "젤네일·케어·아트", category: "beauty"),
        .init(value: "waxing", label: "왁싱샵", emoji: "🪷", desc: "바디·페이스 왁싱", category: "beauty"),
        .init(value: "lash", label: "속눈썹샵", emoji: "👁️", desc: "연장·펌·리무브", category: "beauty"),
        .init(value: "skin", label: "피부관리실", emoji: "🧴", desc: "기본·스페셜·클렌징", category: "beauty"),
        .init(value: "makeup", label: "메이크업", emoji: "💄", desc: "메이크업·헤어메이크업", category: "beauty"),
        .init(value: "tattoo", label: "반영구·타투", emoji: "🖋️", desc: "눈썹·아이라인·타투", category: "beauty"),
        .init(value: "restaurant", label: "음식점", emoji: "🍽️", desc: "식당·레스토랑", category: "food"),
        .init(value: "cafe", label: "카페", emoji: "☕", desc: "카페·디저트", category: "food"),
        .init(value: "bar", label: "주점·바", emoji: "🍺", desc: "바·펍·주점", category: "food"),
        .init(value: "clinic", label: "병원·의원", emoji: "🏥", desc: "진료·검진", category: "medical"),
        .init(value: "dental", label: "치과", emoji: "🦷", desc: "치과 진료", category: "medical"),
        .init(value: "oriental", label: "한의원", emoji: "🌿", desc: "한방 진료", category: "medical"),
        .init(value: "vet", label: "동물병원", emoji: "🐾", desc: "반려동물 진료", category: "medical"),
        .init(value: "gym", label: "헬스·PT", emoji: "💪", desc: "헬스·퍼스널 트레이닝", category: "fitness"),
        .init(value: "yoga", label: "요가·필라테스", emoji: "🧘", desc: "요가·필라테스", category: "fitness"),
        .init(value: "golf", label: "골프", emoji: "⛳", desc: "골프 레슨·연습", category: "fitness"),
        .init(value: "dance", label: "댄스", emoji: "🕺", desc: "댄스 레슨", category: "fitness"),
        .init(value: "academy", label: "학원", emoji: "📚", desc: "학원·교습", category: "class"),
        .init(value: "craft", label: "공방·클래스", emoji: "🎨", desc: "원데이·정기 클래스", category: "class"),
        .init(value: "tutoring", label: "과외", emoji: "✏️", desc: "개인·그룹 과외", category: "class"),
        .init(value: "petgroom", label: "애견미용", emoji: "🐩", desc: "미용·목욕", category: "pet"),
        .init(value: "carwash", label: "세차", emoji: "🚗", desc: "세차·디테일링", category: "repair"),
        .init(value: "repair", label: "정비·수리", emoji: "🔧", desc: "정비·A/S", category: "repair"),
        .init(value: "rentalspace", label: "공간대여", emoji: "🏢", desc: "회의실·파티룸 등", category: "space"),
        .init(value: "practice", label: "연습실", emoji: "🎵", desc: "합주·연습실", category: "space"),
        .init(value: "counseling", label: "상담", emoji: "💬", desc: "심리·코칭 상담", category: "counsel"),
        .init(value: "etc", label: "기타", emoji: "🏪", desc: "기타 업종", category: "etc"),
    ]

    /// 업종별 기본 서비스 프리셋 — 웹 DEFAULT_SERVICES. (없는 업종은 빈 배열)
    private static let defaultServiceSeeds: [String: [ServiceItem]] = [
        "hair": [
            .init(name: "커트", durationMinutes: 30, category: "커트", price: 20000),
            .init(name: "일반펌", durationMinutes: 120, category: "펌", price: 80000),
            .init(name: "볼륨매직", durationMinutes: 120, category: "펌", price: 130000),
            .init(name: "전체염색", durationMinutes: 90, category: "염색", price: 80000),
            .init(name: "부분염색", durationMinutes: 45, category: "염색", price: 40000),
            .init(name: "두피/모발 클리닉", durationMinutes: 60, category: "클리닉", price: 80000),
        ],
        "nail": [
            .init(name: "손 젤", durationMinutes: 60, category: "젤네일", price: 40000),
            .init(name: "발 젤", durationMinutes: 60, category: "젤네일", price: 50000),
            .init(name: "젤 제거", durationMinutes: 20, category: "젤네일", price: 13000),
            .init(name: "손 케어", durationMinutes: 30, category: "케어", price: 17000),
            .init(name: "발 케어", durationMinutes: 30, category: "케어", price: 22000),
            .init(name: "네일아트", durationMinutes: 30, category: "아트", price: 70000),
        ],
        "waxing": [
            .init(name: "브라질리언", durationMinutes: 30, category: "바디왁싱", price: 50000),
            .init(name: "반다리", durationMinutes: 20, category: "바디왁싱", price: 30000),
            .init(name: "전체다리", durationMinutes: 40, category: "바디왁싱", price: 50000),
            .init(name: "겨드랑이", durationMinutes: 15, category: "바디왁싱", price: 25000),
            .init(name: "눈썹", durationMinutes: 10, category: "페이스왁싱", price: 15000),
            .init(name: "코", durationMinutes: 10, category: "페이스왁싱", price: 10000),
            .init(name: "인중", durationMinutes: 10, category: "페이스왁싱", price: 10000),
        ],
        "lash": [
            .init(name: "클래식", durationMinutes: 90, category: "속눈썹 연장", price: 50000),
            .init(name: "볼륨", durationMinutes: 120, category: "속눈썹 연장", price: 90000),
            .init(name: "내추럴", durationMinutes: 90, category: "속눈썹 연장", price: 45000),
            .init(name: "속눈썹 펌", durationMinutes: 60, category: "속눈썹 펌", price: 40000),
            .init(name: "전체 리무브", durationMinutes: 20, category: "리무브", price: 15000),
            .init(name: "부분 리무브", durationMinutes: 10, category: "리무브", price: 10000),
        ],
        "skin": [
            .init(name: "기본 피부 관리", durationMinutes: 60, category: "기본 관리", price: 70000),
            .init(name: "수분 관리", durationMinutes: 60, category: "기본 관리", price: 60000),
            .init(name: "리프팅", durationMinutes: 90, category: "스페셜 관리", price: 100000),
            .init(name: "미백/화이트닝", durationMinutes: 90, category: "스페셜 관리", price: 80000),
            .init(name: "딥 클렌징", durationMinutes: 30, category: "클렌징", price: 60000),
            .init(name: "풀 케어 패키지", durationMinutes: 120, category: "패키지", price: 150000),
        ],
    ]

    /// 업종별 카테고리 색 — 웹 SHOP_CATEGORY_COLOR_MAP.
    private static let categoryColorSeeds: [String: [String: String]] = [
        "hair": ["커트": "#2D7FF9", "펌": "#E53935", "염색": "#FB8C00", "클리닉": "#00A896"],
        "nail": ["젤네일": "#E85D75", "케어": "#00A896", "아트": "#7E57C2"],
        "waxing": ["바디왁싱": "#FB8C00", "페이스왁싱": "#E85D75"],
        "lash": ["속눈썹 연장": "#7E57C2", "속눈썹 펌": "#2D7FF9", "리무브": "#6D6F78"],
        "skin": ["기본 관리": "#00A896", "스페셜 관리": "#E85D75", "클렌징": "#2D7FF9", "패키지": "#FB8C00"],
    ]

    /// 선택 업종들의 기본 서비스(이름 기준 중복 제거) — 웹 온보딩 자동 시드.
    static func defaultServices(for values: [String]) -> [ServiceItem] {
        var seen = Set<String>()
        var result: [ServiceItem] = []
        for value in values {
            for item in defaultServiceSeeds[value] ?? [] where !seen.contains(item.name) {
                seen.insert(item.name)
                result.append(item)
            }
        }
        // 뷰티 외 업종(음식·의료·피트니스 등)은 프리셋이 없어 카탈로그가 비면
        // 예약에서 서비스를 못 고르는 막다른 길이 된다 → 편집 가능한 기본 서비스 1개 시드.
        if result.isEmpty {
            result = [ServiceItem(name: "기본 서비스", durationMinutes: 60, category: "기본", price: 0)]
        }
        return result
    }

    /// 선택 업종들의 카테고리 색을 병합.
    static func categoryColors(for values: [String]) -> [String: String] {
        var merged: [String: String] = [:]
        for value in values {
            for (category, color) in categoryColorSeeds[value] ?? [:] {
                merged[category] = color
            }
        }
        return merged
    }

    /// 기본 근무 스케줄 — 웹 createDefaultSchedule(월~금 10:00~20:00 근무).
    static func defaultSchedule() -> [DaySchedule] {
        (0..<7).map { index in
            DaySchedule(enabled: index < 5, start: "10:00", end: "20:00")
        }
    }

    /// 게스트 기본 담당자 — 웹 온보딩 기본값(원장 1명).
    static func defaultAssignees() -> [Assignee] {
        [Assignee(id: 1, name: "원장", nameI18n: nil, schedule: defaultSchedule(),
                  status: .active, phone: "", note: "", color: "#6526D9")]
    }

    // MARK: - 업종 조회 (웹 getPrimaryIndustry / shopType 라벨)

    private static let byValue: [String: ShopIndustry] =
        Dictionary(industries.map { ($0.value, $0) }, uniquingKeysWith: { first, _ in first })

    /// value 토큰 → 업종.
    static func industry(value: String) -> ShopIndustry? { byValue[value] }

    /// shopType("hair,nail") → 첫 유효 업종(웹 getPrimaryIndustry).
    static func primaryIndustry(shopType: String?) -> ShopIndustry? {
        guard let shopType else { return nil }
        for token in shopType.split(separator: ",") {
            if let ind = byValue[token.trimmingCharacters(in: .whitespaces)] { return ind }
        }
        return nil
    }

    /// shopType 토큰들을 사람이 읽는 라벨로("hair,nail" → "헤어샵·네일샵").
    static func shopTypeLabel(_ shopType: String?) -> String? {
        guard let shopType else { return nil }
        let labels = shopType.split(separator: ",").compactMap {
            byValue[$0.trimmingCharacters(in: .whitespaces)]?.label
        }
        return labels.isEmpty ? nil : labels.joined(separator: "·")
    }

    /// 업종 선택 드롭다운용 — 카테고리 순서대로 (분류명, 업종들) 그룹.
    static var industryGroups: [(category: String, items: [ShopIndustry])] {
        categories.compactMap { cat in
            let items = industries.filter { $0.category == cat.key }
            return items.isEmpty ? nil : (cat.name, items)
        }
    }
}
