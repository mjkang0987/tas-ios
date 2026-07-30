# tas-ios

takeaseat(TAS) 서비스의 iOS 클라이언트. 백엔드는 [`mjkang0987/tas`](https://github.com/mjkang0987/tas)이며,
모델·네트워킹은 그 저장소의 `/api/*` 도메인(`client/features/*/model.ts`)을 미러링한다.

## Versioning (버전 규약)

iOS는 버전 숫자가 둘이다. 웹의 `package.json` 대신 Xcode 빌드 세팅으로 관리한다.

| 필드 | 역할 | 규약 |
|------|------|------|
| `MARKETING_VERSION` | 사용자 표시 버전 (CFBundleShortVersionString) | **0.0.0에서 시작.** PR 머지 시 변경 내용에 따라 semver(patch/minor/major) 범프 |
| `CURRENT_PROJECT_VERSION` | 빌드 번호 (CFBundleVersion) | **1에서 시작.** TestFlight 업로드마다 +1 (동일 표시 버전이라도 업로드 간 유일해야 함) |

- 정식 릴리스(App Store) 전까지는 표시 버전을 `0.x.y`로 유지하며 테스트를 반복한다.
- 버전은 `TAS.xcodeproj`(Debug/Release 두 config)와 `project.yml`(XcodeGen) 양쪽에 있으니 함께 맞춘다.
- git 태그·CHANGELOG는 tas 저장소와 동일하게 사용하지 않는다. 변경 이력은 이슈/PR로 추적한다.

## UI 컨벤션 (중요)

- **공통 영역은 반드시 컴포넌트화해서 재사용한다.** 웹(tas)에는 하드코딩 반복이 많았으나, 앱은
  같은 마크업을 복붙하지 않는다. 반복되는 UI/로직은 `TAS/Core/UI/`(또는 적절한 공용 위치)에
  단일 컴포넌트/유틸로 추출하고 각 화면이 그것을 쓴다.
- 기존 공용 컴포넌트 예: `LoadableView`(로딩/에러/로드 분기), `StatusBadge`·`NewCustomerBadge`,
  `ColorDot`·`ColorAccentBar`, `ServiceColor`(카테고리 색), `formatWon`(금액). 새 화면은 이들을 우선 재사용한다.
- 색/라벨/포맷/판정 로직은 **직접 하드코딩하지 말고 웹 정의를 이식**한다
  (예: `RESERVATION_STATUS_BADGE_STYLES`, `CATEGORY_BASE_COLOR_MAP`, `formatPrice`, `isNewCustomerVisit`).
- 스타일은 iOS 네이티브 감성을 유지하되, 색·용어·비즈니스 로직은 웹과 일치시킨다.

## 참고
- 상세 구조·다음 작업은 `README.md` 참고.
- 백엔드 API 목록·도메인 모델의 소스오브트루스는 tas 저장소의 `index.md`.

## 위험한 명령 금지 (사고 재발 방지)

되돌릴 수 없는 작업으로 실제 데이터를 잃은 사고가 있었다(GitHub Secret 덮어쓰기, 그 이전 DB 삭제).
아래는 예외 없이 지킨다.

- **되돌릴 수 없는 명령은 제안하지 않는다.** 덮어쓰기·삭제·원격 반영은 명령 대신 **UI 경로로 안내**한다.
  (시크릿 갱신, force push, DB 마이그레이션·삭제, `rm`, 기존 파일을 덮는 `cp`/`>` 등)
- 명령이 불가피하면 **무엇이 사라지는지 먼저 적고, 승인을 받은 뒤** 제시한다.
- **읽기 명령과 쓰기 명령을 한 묶음으로 주지 않는다.**
  금지 예: `cp Secrets.example.xcconfig Secrets.xcconfig` 다음에 `gh secret set ... < Secrets.xcconfig` 를 이어 붙이기.
- 기존 값이 있는 대상은 **현재 상태를 먼저 확인**하는 단계를 둔다(덮어쓰기 전에 무엇이 들어있는지).
- 값을 다시 읽을 수 없는 저장소(GitHub Secrets 등)는 특히 주의한다 — 버전 이력도 백업도 없다.
