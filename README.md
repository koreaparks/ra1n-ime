# ra1n IME

macOS용 가벼운 한글 입력기입니다. 두벌식 자판을 지원하며, 전역 한영 토글키로 어떤 앱에서든 빠르게 한글/영문을 전환할 수 있습니다.

## 특징

- **전역 한영 토글** — 기본적으로 `Right ⌘` (오른쪽 Command) 키를 눌러 한글 ↔ 영문 전환
- **다른 입력기에서도 즉시 전환** — ABC 입력기를 사용 중일 때 토글키를 누륾면 자동으로 ra1n IME로 변경
- **IMK 기반 조합** — 표준 마커 방식으로 NSTextView, Safari, Chrome, VSCode 등 대부분의 앱에서 정상 동작
- **설정 UI** — 메뉴 아이콘이나 입력기 메뉴에서 설정 창 열기

## 요구사항

- macOS 13.0 (Ventura) 이상
- Apple Silicon (arm64)

## 설치

### pkg 인스톨러 (권장)

1. [Releases](https://github.com/koreaparks/ra1n-ime/releases)에서 최신 `ra1nIME.pkg`를 다운로드합니다.
2. 다운로드한 파일을 더블클릭하여 설치를 진행합니다.
3. **로그아웃/로그인** 또는 재부팅합니다.
4. **시스템 설정 → 키보드 → 입력 소스**에서 **ra1n IME**를 추가합니다.

> ⚠️ **보안 경고**: 설치 후 다음 권한이 필요합니다.
>
> - **손쉬운 사용** — 팝업이 자동으로 뜨고 리스트에 추가됩니다. 체크박스만 활성화하세요.
> - **입력 모니터링** — macOS 제한으로 **자동 추가되지 않습니다**.  
>   시스템 설정 → 개인정보 보호 및 보안 → 입력 모니터링에서  
>   화면 하단의 `＋` 버튼을 누르고 `/Library/Input Methods/ra1nIME.app`를 직접 선택해 추가하세요.  
>   이 권한이 없으면 전역 한영 토글키가 동작하지 않습니다.

### 수동 설치

```bash
mkdir -p ~/Library/Input\ Methods/
cp -R ra1nIME.app ~/Library/Input\ Methods/
xattr -cr ~/Library/Input\ Methods/ra1nIME.app
# 로그아웃/로그인 후 입력 소스에 추가
```

## 사용법

| 동작 | 방법 |
|------|------|
| 한영 전환 | `Right ⌘` (오른쪽 Command) 키를 단독으로 누름 |
| 설정 열기 | 메뉴 바의 입력기 메뉴 또는 상태 바 아이콘 클릭 |
| 시작 모드 설정 | 설정 창에서 "한글" 또는 "영문" 선택 |

### 설정 변경

- **조합 키 좌/우 구분** — 예: `Left Shift+Space`와 `Right Shift+Space`를 별도로 인식
- **다른 입력기에서 자동 전환** — ABC 등을 사용 중일 때 토글키로 ra1n IME로 변경
- **전환 시 한글 모드 시작** — 다른 입력기에서 ra1n IME로 올 때 한글 상태로 시작

## 제거

터미널에서 다음 명령을 실행하세요:

```bash
sudo bash scripts/uninstall.sh
```

이 명령은 다음을 수행합니다:
- 실행 중인 입력기 프로세스 종료
- **시스템 설정 입력 소스 목록에서 제거**
- 앱 번들 삭제
- LaunchServices 등록 해제

변경사항을 완전히 적용하려면 **로그아웃/로그인** 해주세요.

> 입력 모니터링/손쉬운 사용 권한 목록에 남아있는 경우, **시스템 설정 → 개인정보 보호 및 보안**에서 수동으로 제거할 수 있습니다.

## 업데이트

새 버전의 `ra1nIME.pkg`를 다시 설치하면 됩니다.

> ⚠️ **주의**: 개발자 계정 없이 배포되므로, 매 업데이트마다 **입력 모니터링 권한을 다시 허용**해야 합니다. 설치 후 알림이 뜨면 시스템 설정에서 체크해주세요.

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

### 프로젝트 구조

```
├── Sources/
│   ├── main.swift              # 앱 진입점
│   ├── HangulInputController.swift  # IMK 입력 처리
│   ├── HangulAutomaton.swift   # 한글 조합 엔진
│   ├── GlobalKeyTap.swift      # 전역 키 이벤트 탭
│   ├── Preferences.swift       # 설정 저장
│   ├── PreferencesWindow.swift # 설정 UI
│   └── ...
├── scripts/
│   ├── build-pkg.sh            # 배포 pkg 빌드
│   ├── uninstall.sh            # 제거 스크립트
└── Makefile
```

## 라이선스

Apache License 2.0
