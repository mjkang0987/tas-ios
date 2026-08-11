import Foundation

/// 이름 정렬 규칙 — 웹 정의 이식(`customers/model.ts`·`assignees/model.ts`).
///
/// Swift 기본 `<`는 코드포인트 비교라 'Zebra' < 'apple'(대문자가 먼저)이고 '고객10' < '고객9'이다.
/// 웹은 `Intl.Collator('ko')`/`localeCompare(_, 'ko')`로 비교하므로 같은 규칙을 쓰려면 로케일을 줘야 한다.
/// 기기 로케일에 따라 목록 순서가 흔들리지 않도록 `ko_KR`을 고정한다(웹이 'ko'를 고정하는 것과 동일).
enum NameSort {
    static let locale = Locale(identifier: "ko_KR")

    /// 한국어 기준 문자열 비교. `numeric`이면 숫자 꼬리를 수로 읽는다('고객9' < '고객10').
    static func compare(_ lhs: String, _ rhs: String, numeric: Bool = false) -> ComparisonResult {
        lhs.compare(rhs, options: numeric ? [.numeric] : [], range: nil, locale: locale)
    }

    /// compareAssigneeName(a, b) — assignees/model.ts
    /// 영문(0) → 한글(1) → 기타(2) 그룹으로 먼저 가른 뒤 같은 그룹 안에서 가나다순.
    private static func assigneeNameOrder(_ name: String) -> Int {
        guard let first = name.first else { return 2 }
        if first.isASCII, first.isLetter { return 0 }
        // 한글 음절(가-힣) + 자모(ㄱ-ㅎ, ㅏ-ㅣ) — 웹 정규식 `[가-힣ㄱ-ㅎㅏ-ㅣ]`와 같은 범위.
        if ("가"..."힣").contains(first) || ("ㄱ"..."ㅣ").contains(first) { return 1 }
        return 2
    }

    static func assigneeName(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = assigneeNameOrder(lhs), r = assigneeNameOrder(rhs)
        if l != r { return l < r ? .orderedAscending : .orderedDescending }
        return compare(lhs, rhs)
    }
}

extension Customer {
    /// compareCustomerName(a, b) — customers/model.ts (tas #175)
    /// 이름이 같으면(동명이인) id로 갈라 정렬을 안정화한다.
    static func isOrderedBeforeByName(_ lhs: Customer, _ rhs: Customer) -> Bool {
        switch NameSort.compare(lhs.name, rhs.name, numeric: true) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.id < rhs.id
        }
    }
}

extension Array where Element == Customer {
    /// sortCustomersByName(list) — customers/model.ts. 원본을 건드리지 않고 이름 오름차순 사본.
    func sortedByName() -> [Customer] { sorted(by: Customer.isOrderedBeforeByName) }
}
