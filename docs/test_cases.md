# ra1nIME 테스트 케이스

> 한글 IME의 동작을 검증하기 위한 시나리오 모음. 각 케이스마다 기대 동작과 과거에 관찰된 증상을 기록.

## 환경

- macOS 26 (이전 트래킹은 macOS 14~26 기간)
- 빌드/배포: `make refresh` (sudo 필요)
- 활성화: 시스템 설정 → 키보드 → 입력 소스 → ra1n IME
- 로그: `log stream --predicate 'subsystem == "kr.ra1n.inputmethod.ra1nime"' --info`

## 테스트 클라이언트 분류

| 카테고리 | 대표 앱 | 특성 |
|---|---|---|
| **A** NSTextView 기반 | Notes (`com.apple.Notes`), TextEdit | marker 보존 안 함 (focus loss 시 discard 추정), auto-commit 안 함 |
| **B** Terminal-style | Terminal.app (`com.apple.Terminal`) | TSMDocumentAccess 미지원, attributedSubstring nil, marker overlay |
| **C** Chromium-based | VSCode chat (`com.microsoft.VSCode` 내 Claude Code 채팅) | marker 별도 buffer 보존, focus loss 시 auto-commit |
| **D** Monaco editor | VSCode 코드 에디터 | 자체 IME 구현, marker가 control char로 변질되는 quirk |

## A. 기본 한글 조합 (단일 앱 내)

### A1. 단일 음절 조합 후 enter
- 입력: ㅁ, ㅏ, Enter
- 기대: "마\n"
- 모든 앱에서 정상 동작해야 함

### A2. 받침 결합
- 입력: ㅁ, ㅏ, ㄴ, ㅁ, ㅏ, Enter
- 기대: "만마\n" (자모 분리)
   - 실제로는 ㄴ 다음 ㅁ에서 자모 결합 안 됨, "만"이 commit되고 "마" 시작 → "만마\n"
- 정확한 한글 오토마톤 동작 검증

### A3. 복합 받침
- 입력: ㄹ, ㅏ, ㄹ, ㄱ → "랄ㄱ"? "랑"이 아닌 "랄ㄱ" 또는 "랄ㄱ" 결합 후 → "랅" (래+ㄺ)
- 자세히는 `HangulAutomaton.jongseongCombos` 참고

### A4. 자모 분리
- ㄹ+ㄱ 동시 합성 후 ㅏ 누르면 → "랑" + "가" (ㄹㄱ 받침에서 ㄱ이 다음 음절로 이동)
- `inputVowel`의 jongseongSplit 검증

### A5. Backspace 동작
- 입력: ㅁ, ㅏ, ㄴ → "만"(조합중) → Backspace → "마"(조합중) → Backspace → "ㅁ" → Backspace → ""
- composition 내부에서만 동작, doc의 다른 글자에 영향 없어야

### A6. Space 후 새 조합 시작
- 입력: ㅁ, ㅏ, Space, ㄴ, ㅏ → "마 나"
- Space로 commit 완료 후 새 syllable 시작

## B. Focus loss (다른 앱 전환)

### B1. Cmd+Tab으로 이동
- 입력: ㅁ, ㅏ (조합 중) → Cmd+Tab → 다른 앱
- 기대: 원래 앱에 "마"가 commit된 채로 남아있음. 다른 앱은 영향 없음.
- 과거 증상:
  - **A앱 (Notes)**: 조합 글자 사라짐 → 우리가 leaving 시점에 commit 안 해서
  - **C앱 (Chat)**: "마마" doubling → 우리 insertText + Chromium auto-commit 중복
  - **D앱 (Monaco)**: marker stale 상태 진입 → 복귀 후 Home → SOH 같은 부작용

### B2. 마우스 클릭으로 다른 앱 이동
- 입력: ㅁ, ㅏ (조합 중) → 다른 앱 윈도우 마우스 클릭
- 기대: B1과 동일
- 차이점: Cmd+Tab은 우리 IME 키 이벤트 받고, 마우스 클릭은 안 받음

### B3. 복귀 후 동일 위치 검증
- B1 또는 B2 시나리오 후 원래 앱 복귀 → cursor 위치, 텍스트 내용 정상인지

### B4. 복귀 후 다음 키 입력
- B1 또는 B2 후 복귀 → ㅂ 또는 다른 키 입력
- 기대: "마ㅂ" (조합 종료된 마 + 새 조합 ㅂ)
- 과거 증상: 복귀 후 Home → SOH 삽입 (Monaco), Backspace → BS 삽입 (Monaco), 별 글자 사라짐 등

## C. 마우스 클릭 동작 (앱 내)

### C1. 조합 중 다른 위치 클릭
- 시나리오: "마" 조합 중 → doc의 다른 곳 클릭
- 기대: "마" commit되고 cursor가 클릭 지점으로 이동 (1-click)
- 과거 증상: 2-click 필요 (1st = commit, 2nd = cursor 이동)
- 해결책: `recognizedEvents`에 `leftMouseDown` 추가 + `mouseDownOnCharacterIndex` 오버라이드

### C2. 텍스트 선택 (drag)
- 시나리오: "마" 조합 중 → 마우스 drag로 다른 영역 선택
- 기대: "마" commit + 선택 영역 활성화

## D. 기능키 + Cmd 조합

### D1. Cmd+Z 동작
- 시나리오: "마" 조합 중 → Cmd+Z
- 기대: undo 동작 (조합 commit 후 undo)
- 과거 증상: "동작 안 함" — `commitAndRepost` 경로의 synthetic event가 client에 안 도달하는 케이스

### D2. Cmd+A 동작
- 시나리오: "마" 조합 중 → Cmd+A
- 기대: 전체 선택
- 과거 증상: Cmd+Tab 복귀 후 Cmd+A가 안 먹히고 화살표 키 눌러야 unblock됨 (Monaco)

### D3. Cmd+Tab + Cmd+Z
- 시나리오: "마" 조합 중 → Cmd+Tab → 복귀 → Cmd+Z
- 기대: 정상 undo
- 과거 증상: 간헐적으로 안 먹힘

### D4. Home, End, PageUp, PageDown
- 시나리오: "마" 조합 중 → Home (또는 End/PageUp/PageDown)
- 기대: 조합 commit + cursor가 줄 시작/끝/페이지로 이동
- 과거 증상:
  - Cmd+Tab 복귀 후 Home → SOH(0x01) 삽입 (Monaco)
  - Backspace → BS(0x08) 삽입 (Monaco)
- 해결책: 이 키들은 `commitAndRepost`로 30ms delay 후 synthetic 재주입

### D5. shift+Enter
- 시나리오: "마" 조합 중 → shift+Enter
- 기대: 조합 commit + 줄바꿈
- 과거 증상: Cmd+Tab 복귀 후 첫 shift+Enter가 안 먹힘 (chat에서)

## E. 토글 키 (한/영 모드 전환)

### E1. 토글 키 누름
- 기본 binding: Right-Shift+Space 또는 Right-Shift (Preferences에서 변경 가능)
- 기대: 모드 전환. 조합 중인 글자 commit. 상태바 아이콘 변경.

### E2. 토글 + 다른 키 조합
- 토글 키 누른 상태에서 다른 키 조합: 토글 발화 취소되어야

## F. 시각적 표현

### F1. 마커 밑줄
- 시스템 한글 IME: 조합 중 글자에 밑줄 없음
- ra1nIME 현재: 조합 중 글자에 밑줄 있음
- 원인: `markForStyle:atRange:`가 자동으로 underline 속성 추가 + NSTextView가 marker range만 보고 자체적으로 underline 그림
- 해결책 후보: 인라인 commit 아키텍처로 전환 (마커 자체를 안 씀)

### F2. 커서 위치
- 조합 중에도 cursor가 적절한 위치에 보여야
- 과거 증상: chat에서 cursor가 한 칸 앞으로 이동, Notes에서 cursor 사라짐 (plain String 전달 시)

## G. 종합 시나리오

### G1. 빠른 입력 + 전환 + 복귀
- 한글 빠르게 타이핑 → Cmd+Tab → 다른 앱에서 잠시 작업 → 원래 앱 복귀 → 한글 추가 입력
- 모든 단계에서 텍스트 손실, doubling, 잘못된 위치 삽입 없어야

### G2. 한글/영문 mixed
- 한글 입력 → 토글 → 영문 입력 → 토글 → 한글 입력
- 모드 전환 시점에 조합 글자 정상 처리

### G3. 다중 syllable 후 backspace
- "마나다라" 입력 후 backspace 4번 → 빈 doc

## H. 알려진 한계 (수용하기로 한 부분)

- 조합 중 글자 아래 밑줄 표시 — 마커 기반 아키텍처의 본질. Apple 시스템 IME는 인라인 commit으로 회피.
- VSCode chat의 cursor 한 글자 앞 이동 — Chromium 자체 동작 (인라인 commit으로 해소 가능 추정).

## 검증 체크리스트

신규 코드 변경 후 최소 다음 모두 확인:

- [ ] A1: Notes에서 정상
- [ ] A1: Terminal에서 정상
- [ ] A1: VSCode editor에서 정상
- [ ] A1: VSCode chat에서 정상
- [ ] B1 (Cmd+Tab): Notes 한글 commit 보존
- [ ] B1 (Cmd+Tab): Terminal 한글 commit 보존
- [ ] B1 (Cmd+Tab): chat에서 doubling 없음
- [ ] B2 (마우스): 위와 동일
- [ ] B4: 복귀 후 다음 키 정상 동작 (특히 Monaco Home/Backspace)
- [ ] C1: Notes 1-클릭 cursor 이동
- [ ] D1~D5: Cmd 조합과 기능키 정상 동작
- [ ] E1: 토글 전환 시 조합 commit
- [ ] G1: 종합 시나리오 통과
