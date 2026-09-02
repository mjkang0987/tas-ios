import Foundation

/// 검색어가 걸린 구간 — 웹 `client/features/customers/search-highlight.ts` 이식.
enum SearchHighlight {
    /// findMatchRange(text, query, {caseInsensitive}) — search-highlight.ts
    /// 일반 부분일치를 먼저 보고, 못 찾으면 초성 부분일치(`Chosung`)를 본다 — 검색 화면의
    /// 매칭 규칙(이름 OR 초성)과 정확히 같은 순서라 실제 매칭과 하이라이트가 어긋나지 않는다.
    static func matchRange(in text: String, query: String, caseInsensitive: Bool = false) -> Range<String.Index>? {
        guard !query.isEmpty else { return nil }

        // 로케일까지 맞추는 이유: 호출부(CustomersViewModel.filterResult)가 필터링에
        // localizedCaseInsensitiveContains(로케일 인식)를 쓴다. 여기서 로케일 없이 비교하면
        // 필터엔 걸렸는데 하이라이트만 안 뜨는 경우가 생길 수 있다.
        let options: String.CompareOptions = caseInsensitive ? [.caseInsensitive] : []
        let locale: Locale? = caseInsensitive ? .current : nil
        if let found = text.range(of: query, options: options, locale: locale) {
            return found
        }

        guard Chosung.isQuery(query) else { return nil }

        let chosungText = Chosung.extract(text)
        guard let chosungRange = chosungText.range(of: query) else { return nil }

        // Chosung.extract는 문자 수를 그대로 보존(음절 1개 → 초성 1개)하므로 초성열에서 찾은
        // 문자 오프셋이 원문의 문자 오프셋과 그대로 대응한다.
        let startOffset = chosungText.distance(from: chosungText.startIndex, to: chosungRange.lowerBound)
        let endOffset = chosungText.distance(from: chosungText.startIndex, to: chosungRange.upperBound)
        guard let start = text.index(text.startIndex, offsetBy: startOffset, limitedBy: text.endIndex),
              let end = text.index(text.startIndex, offsetBy: endOffset, limitedBy: text.endIndex) else { return nil }
        return start..<end
    }
}
