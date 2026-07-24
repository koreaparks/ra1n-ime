# ra1n IME

macOS용 가벼운 한글 입력기입니다. 두벌식 자판을 지원하며, 전역 한영 토글키로 어떤 앱에서든 빠르게 한글/영문을 전환할 수 있습니다.

## 특징

- **전역 한영 토글** — 기본적으로 `Right ⌘` (오른쪽 Command) 키를 눌러 한글 ↔ 영문 전환
- **다른 입력기에서도 즉시 전환** — ABC 입력기를 사용 중일 때 토글키를 누르면 자동으로 ra1n IME로 변경
- **IMK 기반 조합** — 표준 마커 방식으로 NSTextView, Safari, Chrome, VSCode 등 대부분의 앱에서 정상 동작
- **설정 UI** — 메뉴 아이콘이나 입력기 메뉴에서 설정 창 열기

## 요구사항

- macOS 13.0 (Ventura) 이상
- Apple Silicon (arm64)

## 개발

```bash
# 빌드
make

# 빌드 + /Library/Input Methods/에 설치 + 캐시 리프레시
make refresh

# 배포용 pkg 생성
./scripts/build-pkg.sh
# 결과물: build/ra1nIME.pkg

# 완전히 지우고 처음부터 다시 설치
sudo bash scripts/uninstall-all.sh
make refresh
```

## 라이선스

Apache License 2.0
