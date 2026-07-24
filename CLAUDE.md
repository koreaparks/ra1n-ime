# CLAUDE.md

이 파일은 이 저장소에서 작업하는 Claude Code를 위한 지침입니다.

## 언어 규칙 (최우선)

- 모든 응답은 **예외 없이 한국어**로 작성한다.
- 작업 진행 상황 설명, 계획 설명, 도구 사용 이유 설명도 반드시 한국어로 작성한다.
- 파일 내용, 코드 주석, 커밋 메시지, 최종 요약 모두 한국어로 작성한다.
- 영어로 응답하는 것은 어떤 경우에도 허용되지 않는다.

## 커밋 규칙

- 커밋은 **사용자의 요청이 있을 때만** 한다. 요청 없이 임의로 커밋하지 않는다.
- 커밋 메시지에 `Co-Authored-By` 같은 서명·공동작성자 표기를 넣지 않는다.
- 커밋 메시지는 한국어로 작성한다.

## 프로젝트 개요

macOS용 한글 입력기(IME)입니다. Swift로 작성되었으며, InputMethodKit 기반으로 두벌식 한글 조합과 전역 한영 토글을 제공합니다. Apple Silicon(arm64), macOS 13.0 이상 대상입니다.

## 빌드 / 배포

```bash
make                   # ra1nIME.app 번들 빌드
make refresh           # 빌드 + /Library/Input Methods/에 설치 + 캐시 리프레시
make version           # 현재 버전 출력
./scripts/build-pkg.sh # 배포용 build/ra1nIME.pkg 생성
```

- 배포 pkg는 개발자 등록 없이 **ad-hoc 서명**으로 만들어진다. 그래서 받는 쪽에서 Gatekeeper 경고가 뜰 수 있으며, 우회 방법은 `README.md`의 설치 안내를 따른다.

## 버전 관리

- 버전은 루트의 **`VERSION` 파일 하나**가 단일 소스이다. 빌드 시 `Info.plist`, pkg, `scripts/distribution.xml`에 자동 주입된다.
- 버전을 올릴 때는 `VERSION` 파일만 수정한다. (예: `echo "1.1.0" > VERSION`)
- 빌드 번호(`CFBundleVersion`)는 git 커밋 수에서 자동 계산되므로 직접 건드리지 않는다.
- 소스 `Info.plist`의 버전 문자열은 템플릿 값이며, 실제 번들에는 항상 `VERSION` 값이 새겨진다.
