# tas-ios

takeaseat(TAS) 서비스의 iOS 클라이언트. 백엔드는 [`mjkang0987/tas`](https://github.com/mjkang0987/tas)이며,
모델·네트워킹은 그 저장소의 `/api/*` 도메인(`client/features/*/model.ts`)을 미러링한다.

## Core Principles
- 확실하지 않은 내용은 임의로 추측하지 말고 모른다고 명시할 것.
- 사용자의 접근 방식에 문제가 있다면 즉시, 직접적으로 지적할 것.
- 코드나 테스트가 실패할 경우 무작정 재시도하지 말고 반드시 근본 원인(root cause)을 먼저 조사할 것.

## Session Startup Rules
- 새 세션 시작 시 가장 먼저 `README.md`와 `plan.md`를 읽을 것. (이 저장소에는 `index.md`가 없다 —
  구조·현재 상태의 SSOT는 `README.md`, 작업의 SSOT는 `plan.md`.)
- 두 문서를 검토하기 전까지 코드 구현을 시작하지 말 것.
- 문서와 실제 구현이 다르면 임의로 진행하지 말고 불일치를 보고한 뒤 확인을 요청할 것.

## Development Workflow
- **작업 계획 수립:** 모든 작업을 시작하기 전 `plan.md`를 작성할 것. 요구사항, 구현 방식, 영향받는 파일,
  예상 결과를 기록하고 검토가 끝난 후 코드를 수정할 것. (개발 중 범위가 변경되면 `plan.md` 즉시 업데이트)
- **작업 분할 및 브랜치 생성:** 작업 요청 시 가장 작은 단위의 이슈로 나누고, `develop` 브랜치 파생으로
  개별 `feature` 브랜치를 생성하여 시작할 것. (세션마다 지정 브랜치가 있으면 그것을 따른다.)
- **Feature 검증 사이클:** `작업` > `코드리뷰` > `개선` > `검증` > `수정작업` > `코드리뷰` > `개선` > `검증`
  — 이 프로세스를 브랜치 내에서 완벽히 완료할 것. 리뷰를 건너뛰고 푸시하지 않는다.
- **Dev 병합 및 2차 검증:** 단일 `feature` 검증이 끝나면 `develop` 에 머지 + 푸시하고, `develop` 에서도
  동일한 사이클을 거쳐 통합 부작용을 해결할 것.
- **Main 배포:** `develop` 진행이 완료되면 PR을 생성하고 `main` 머지를 **요청**할 것.
  지시자의 명시적 승인 없이 `main`에 머지하지 않는다.
- **검증 수단:** 로컬 빌드가 불가한 환경(리눅스 컨테이너 등)에서는 푸시 후 CI 그린까지를 검증으로 본다.
  Xcode가 있으면 `xcodegen generate` → `xcodebuild build`(로직 변경 시 `xcodebuild test`).
- **버전 펌핑:** PR 머지 시 변경 규모(Patch / Minor / Major)를 판단해 아래 `Versioning` 규약대로 올릴 것.

## On Commit
- 커밋은 최소 작업 단위로 잘게 분할할 것.
- 커밋 메시지는 한국어로 작성할 것.
- Conventional Commits 접두사(`feat:`, `fix:`, `refactor:`, `style:`, `chore:`, `perf:`, `docs:`)를 반드시 쓸 것.
- 커밋 후에는 항상 푸시할 것.

## Documentation Maintenance
- 단일 작업이나 이슈를 완료한 후에는 변경 사항을 반영해 `README.md`와 `plan.md`를 즉시 갱신할 것.

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
