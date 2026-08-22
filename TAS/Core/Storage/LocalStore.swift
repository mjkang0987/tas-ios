import Foundation

/// 게스트(오프라인) 모드용 로컬 영속 계층.
///
/// 웹의 `localStorage['takeaseat.local-db.v1']` 단일 스냅샷 방식을 그대로 옮긴다:
/// 전체 스냅샷을 앱 Documents 폴더의 단일 JSON 파일로 읽고 쓴다.
/// (로그인 사용자는 서버 API를 쓰므로 이 계층을 타지 않는다.)
///
/// 스냅샷 타입(`GuestSnapshot`)은 웹 `lib/local-db.ts`의 필드를 미러링해서
/// 로그인 시 `/api/migrate-local` payload로 그대로 넘길 수 있게 한다.
final class LocalStore {
    static let shared = LocalStore()

    /// 웹 localStorage 키(`takeaseat.local-db.v1`)에 대응하는 파일명.
    /// 스크린샷 CI가 이 파일을 심어 게스트 상태를 만든다 — 이름이 갈리면 앱은 조용히
    /// 로그인 화면으로 떨어지므로 `GuestSeedTests`가 워크플로와 이 상수를 대조한다.
    static let fileName = "takeaseat.local-db.v1.json"
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    private var fileURL: URL? {
        guard let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent(Self.fileName)
    }

    /// 저장된 스냅샷을 읽는다. 없거나 디코딩 실패 시 nil.
    func load<T: Decodable>(_ type: T.Type = T.self) -> T? {
        guard let url = fileURL, fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    /// 스냅샷을 저장한다. 실패 시 false.
    @discardableResult
    func save<T: Encodable>(_ value: T) -> Bool {
        guard let url = fileURL else { return false }
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    /// 저장된 스냅샷을 삭제한다(로그아웃·이관 완료 후 로컬 정리).
    func clear() {
        guard let url = fileURL, fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }

    /// 게스트 데이터 파일이 존재하는지 — 웹 `hasGuestData()`에 대응(정밀 판정은 스냅샷 내용으로).
    var hasFile: Bool {
        guard let url = fileURL else { return false }
        return fileManager.fileExists(atPath: url.path)
    }
}
