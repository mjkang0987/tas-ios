import Foundation

/// 한글 초성(첫소리) 검색 — 웹 `client/features/customers/chosung.ts` 이식.
/// "김민수"를 "ㄱㅁㅅ"로도 찾을 수 있게 한다.
enum Chosung {
    private static let list: [Character] = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]
    private static let syllableStart: UInt32 = 0xAC00 // '가'
    private static let syllableEnd: UInt32 = 0xD7A3 // '힣'
    private static let jungJongCount: UInt32 = 588 // 중성(21) × 종성(28)
    private static let set = Set(list)

    /// getChosung(text) — chosung.ts. 한글 음절은 초성으로, 그 외 문자(자모 단독·영문·숫자·기호)는
    /// 그대로 통과시킨다. 문자 수를 그대로 보존한다(음절 1개 → 초성 1개).
    static func extract(_ text: String) -> String {
        String(text.map { ch -> Character in
            guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1,
                  scalar.value >= syllableStart, scalar.value <= syllableEnd else { return ch }
            let index = Int((scalar.value - syllableStart) / jungJongCount)
            return list[index]
        })
    }

    /// isChosungQuery(query) — chosung.ts. 빈 문자열이 아니고 모든 글자가 초성 자모일 때만 true.
    static func isQuery(_ query: String) -> Bool {
        !query.isEmpty && query.allSatisfy { set.contains($0) }
    }

    /// matchesChosung(target, query) — chosung.ts. 초성 질의일 때만 대상 문자열의 초성열에 부분일치시킨다.
    static func matches(_ target: String, _ query: String) -> Bool {
        guard isQuery(query) else { return false }
        return extract(target).contains(query)
    }
}
