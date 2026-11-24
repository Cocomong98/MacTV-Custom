# 브랜치와 배포

- 기능은 `main`에서 `add-기능명` 브랜치를 만든다. 예를 들어 `add-remote-presets`에서 작업하고 테스트를 거쳐 `main`에 PR로 병합한다.
- 주간 배포를 준비할 때 `main`의 검증된 변경을 `release`로 병합한다. 배포 변경에서 `VERSION`과 `CHANGELOG.md`를 함께 갱신한다.
- [Semantic Versioning](https://semver.org/lang/ko/)을 따른다. 일반 배포에서 호환되는 버그 수정은 `PATCH`, 호환되는 기능 추가는 `MINOR`, 호환성 파괴는 `MAJOR`를 올린다. `0.x` 개발 단계의 호환성 변경은 `MINOR`를 올리고 변경 기록에 영향을 적는다.
- 배포 커밋을 `release`에 푸시한 다음 같은 커밋에 `vMAJOR.MINOR.PATCH` 태그를 붙여 푸시한다. GitHub Actions가 버전·브랜치·테스트를 확인하고 GitHub Releases에 DMG와 SHA‑256을 게시한다. 배포 후 `release`의 버전과 변경 기록을 `main`에 다시 병합한다. 이미 배포한 태그의 수정은 다음 버전에서 한다.

## 로컬 확인

```bash
bash scripts/test-custom.sh
bash scripts/make-custom-dmg.sh
```

빌드와 실행에는 Swift 6 이상, 웹 테스트에는 Node.js 22 이상과 Chrome 또는 Brave가 필요하다. DMG와 체크섬은 `build/`에 생성된다. 공개 배포 전후의 실기기 확인은 [테스트 계획](TEST_PLAN.md)에 기록한다.
