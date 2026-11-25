# 브랜치와 배포

- 기능은 `main`에서 `add-기능명` 브랜치를 만든다. 예를 들어 `add-remote-presets`에서 작업하고 테스트를 거쳐 `main`에 PR로 병합한다.
- 주간 배포를 준비할 때 `main`의 검증된 변경을 `release`로 병합한다. 배포 변경에서 `VERSION`과 `CHANGELOG.md`를 함께 갱신한다.
- [Semantic Versioning](https://semver.org/lang/ko/)을 따른다. 일반 배포에서 호환되는 버그 수정은 `PATCH`, 호환되는 기능 추가는 `MINOR`, 호환성 파괴는 `MAJOR`를 올린다. `0.x` 개발 단계의 호환성 변경은 `MINOR`를 올리고 변경 기록에 영향을 적는다.
- 배포 커밋을 `release`에 푸시하고 같은 커밋에 `vMAJOR.MINOR.PATCH` 태그를 붙인다. 서명용 Mac에서 아래 명령으로 만든 DMG와 SHA‑256을 같은 태그의 GitHub Releases에 게시한다. GitHub Actions는 게시된 두 파일의 체크섬과 DMG 형식을 검증한다.
- DMG가 게시되면 `main`에 배포 커밋을 반영하고 `Casks/mactv-custom.rb`의 버전과 SHA‑256을 갱신한다. 이미 배포한 태그와 파일의 수정은 다음 버전에서 한다.

## 공개판과 개인용 로컬판

`./build.sh --release`로 빌드하는 공개판의 표시 이름은 **CouchDial**이다. 공개판은 자체 색상 타일과 일반 YouTube 웹을 사용한다. `./build.sh --local`은 해당 Mac에 보관한 별도 입력으로 `CouchDial Local.app`을 빌드한다. 개인용 입력과 산출물은 Git 추적에서 제외하며, GitHub Releases와 Homebrew에는 공개판만 사용한다.

공개 DMG 이름은 `CouchDial-<버전>.dmg`이다. `0.3.0`부터 기존 Cask 토큰을 CouchDial DMG에 연결한다. 다음 릴리스가 게시되면 같은 토큰에서 DMG URL과 버전·체크섬을 함께 갱신한다. 앱 번들 파일명 `MacTV Custom.app`, 공개판 번들 ID와 기존 데이터 경로는 업그레이드 비교를 위해 유지한다.

## 배포용 서명

`0.2.0`부터 같은 배포 인증서와 번들 ID `local.couch.tv.custom`을 사용한다. 인증서의 표시 이름이 같아도 새로 만들면 서명 요건이 달라진다. 서명은 배포용 Mac의 키체인에서 수행한다.

```bash
MACTV_SIGN_IDENTITY=00965DC4A85ABD2B8C0994FC18D46BE39931E849 bash scripts/make-custom-dmg.sh
```

첫 Cask 버전에서 한 번 실행을 승인하고, 같은 Cask의 다음 버전으로 업데이트해 macOS 실행 승인이 이어지는지 확인한다.

## 로컬 확인

```bash
bash scripts/test-custom.sh
bash scripts/make-custom-dmg.sh
```

빌드와 실행에는 Swift 6 이상, 웹 테스트에는 Node.js 22 이상과 Chrome 또는 Brave가 필요하다. DMG와 체크섬은 `build/`에 생성된다. 공개 배포 전후의 실기기 확인은 [테스트 계획](TEST_PLAN.md)에 기록한다.
