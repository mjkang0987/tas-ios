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

## 참고
- 상세 구조·다음 작업은 `README.md` 참고.
- 백엔드 API 목록·도메인 모델의 소스오브트루스는 tas 저장소의 `index.md`.
