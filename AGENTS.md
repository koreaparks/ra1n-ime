# ra1nIME 개발 규칙

## 회귀 방지 — 최우선 원칙

**정상 동작하는 앱에서 다시 문제가 발생하지 않게 해야 한다.**

새 client 또는 새 시나리오 fix를 시도할 때, 이미 정상으로 검증된 앱들에서 회귀가 발생하지 않도록 *각 변경마다* 다음 검증 체크리스트를 통과해야 한다.

## 검증된 client — 회귀 발생 금지

### NSTextView 기반 (Notes, TextEdit)

모든 시나리오 정상. 다음 항목 회귀 금지:

- A. 한글 조합: 자모 결합, 받침, 자모 분리, Backspace, Space, Enter, Tab
- B. Focus loss (Cmd+Tab / 다른 앱 마우스 클릭) + 복귀
- C. 마우스 1-click cursor 이동, drag 선택
- D. Cmd+Z / Cmd+A (조합 중·후) / Cmd+C / Cmd+V / Home / End / PageUp / PageDown / Shift+Enter
- E. 한/영 토글
- F. 시각적 underline 표시 — **acceptable** (시스템 한국어 IME와 일관성)
- G. 종합 시나리오 (빠른 입력 + 전환, 한영 mixed 등)

### Monaco (VSCode editor)

모든 시나리오 정상. 다음 항목 회귀 금지:

- 조합 중 Cmd+A 한 번에 selectAll
- Home / Backspace 등 후속 키 정상 동작 (옛 stuck-keybinding 모드 회귀 X)
- 위 NSTextView 시나리오 모두 동일하게 정상

### Terminal.app / iTerm2

모든 시나리오 정상 (C1·C2 마우스 1-click cursor 이동은 Terminal에서 N/A이므로 제외). 다음 항목 회귀 금지:

- 조합 중 Shift+Enter 한 번에 동작
- 조합 중 Enter 한 번에 동작
- Cmd+Tab focus loss + 복귀 시 commit 보존
- 한글 조합 (자모 결합, 받침, Backspace, Space)
- 위 NSTextView 시나리오 중 Terminal에서 가능한 항목 모두 정상

### VSCode chat (Chromium contenteditable)

모든 시나리오 정상. 다음 항목 회귀 금지:

- "안녕" 조합 후 Cmd+Tab → 복귀 시 doubling 없음 (doc에 "안녕" 한 번만)
- "안녕" 조합 후 **마우스 클릭으로 다른 앱 이동** → 복귀 시에도 doubling 없음
- 위 NSTextView 시나리오 중 chat에서 가능한 항목 모두 정상

**중요 — doubling 근본 원인**: Chromium contenteditable은 focus 변경 시 자체적으로 marker buffer를 commit. 우리가 focus loss(deactivateServer) 시점에 *또* commit하면 두 번 들어가 "안녕녕" doubling. Monaco editor와 chat이 **같은 VSCode bundle + 동일한 `validAttributesForMarkedText`**라 client capability로 구분 불가. 그래서 "focus loss 전에 우리가 미리 commit해서 marker를 비워두는" 전략을 씀:

1. **Cmd+Tab (키보드 focus 이동)**: `handleFlagsChanged`의 **Cmd 모디파이어 down 시 endComposition 호출** (`cmd-down → preemptive commit` 분기). Cmd+Tab이 fire되기 전에 이미 commit. 이 분기 제거 시 회귀.
2. **마우스 클릭 (포인터 focus 이동)**: `Sources/ClickMonitor.swift`. system-level `.cgSessionEventTap` `.listenOnly`로 마우스 down을 관찰하여, 클릭이 focus 이동을 일으키기 *전에* `HangulInputController.current?.commitCurrent()`로 미리 commit. 이 파일/호출 제거 시 마우스 doubling 회귀.

**ClickMonitor 주의사항**:
- tap callback에서 **insertText를 sync로 호출하면 안 됨** — focus 떠나는 중인 Chromium renderer에 re-entrant하게 들어가 VSCode가 crash한 사례 있음. 반드시 `DispatchQueue.main.async`로 다음 runloop에 commit.
- `.cghidEventTap`은 우리 agent 권한으로 tapCreate 실패 (silent). 반드시 GlobalKeyTap과 같은 `.cgSessionEventTap` 사용.
- `commitCurrent`는 `automaton.currentComposition().isEmpty` guard로 조합 중일 때만 동작 — 일반 클릭은 무영향.

### IntelliJ (JetBrains)

- 조합 중 Shift+방향키가 한 번에 selection 확장 (`commitAndRepost`로 화살표 키도 30ms delay repost — `handleKeyDown`의 화살표 case)
- Shift+Home/End도 동일하게 정상

## 변경 시 권장 패턴

### 조합 중일 때만 IME가 개입

- `automaton.isEmpty == false`인 경우만 우리 코드가 동작에 영향을 줘야 한다.
- 조합 중 아닌 시점의 키 이벤트는 자연 통과 (`return false`) — client 표준 동작 유지.
- `commitAndRepost`도 이 원칙 따름: composing이 비어 있으면 false 반환 → 자연 통과.

### Cmd+Tab은 특별 처리

- `commitAndRepost` 적용 금지. synthetic event repost가 Monaco를 stale-marker state로 만든다 (핸드오프 4.5 참고).
- 그저 `endComposition(sender:)` + `return false`로 자연 focus 전환.

### timing-critical 키는 commitAndRepost (30ms delay + synthetic repost)

- Enter / Tab / Home / End / PageUp / PageDown / ForwardDelete / **방향키 4개**.
- raw stdin client(Terminal) / IntelliJ가 우리 insertText commit이 land하기 전에 키를 소비해서, 안 하면 "첫 입력 무시 → 두 번째에 동작". commit 후 30ms 뒤 원래 키(modifier 보존)를 재주입.
- Space / Escape는 timing-tolerant → `endComposition` + 자연 통과.

### 마우스 focus 이동 시 preemptive commit (ClickMonitor)

- `Sources/ClickMonitor.swift` — system-level 마우스 down 관찰 → focus 이동 전에 미리 commit.
- 자세한 내용은 "VSCode chat" 섹션의 ClickMonitor 주의사항 참고.

### setMarkedText / insertText 호출 위치

- `setMarker(s)`: composing 중 매번. `replacementRange: NSNotFound`로 selection 자동 replace 활용.
- `endComposition`: marker commit (insertText) + `setMarkedText("")` 추가 호출로 IME state 명시 해제.
  - NSTextView: no-op
  - Chromium: mirror buffer empty (doubling 방지 목적)
  - Monaco: IME state release (Cmd+A 등 후속 키 dispatch 가능하게)

## 검증 체크리스트 (각 변경 후 필수)

각 PR / 빌드 후 다음을 통과해야 한다:

- [ ] Notes/TextEdit: 한글 조합 정상
- [ ] Notes/TextEdit: Cmd+A → 한글 입력 시 selection 새 글자로 replace
- [ ] Notes/TextEdit: Cmd+A → BS 시 doc 비워짐 (자모 단위 BS 안 됨)
- [ ] Notes/TextEdit: 마우스 1-click으로 cursor 이동
- [ ] Notes/TextEdit: 한/영 토글 시 조합 commit
- [ ] Monaco: 조합 중 Cmd+A 한 번에 selectAll
- [ ] Monaco: Home / BS 등 후속 키 정상 (control char 삽입 X)
- [ ] Monaco: 위 NSTextView 시나리오 모두 정상
- [ ] Terminal: 조합 중 Shift+Enter / Enter 한 번에 동작
- [ ] Terminal: Cmd+Tab + 복귀 시 commit 보존
- [ ] Terminal: 한글 조합 정상
- [ ] VSCode chat: 조합 중 Cmd+Tab → 복귀 시 doubling 없음
- [ ] VSCode chat: 조합 중 마우스 클릭으로 다른 앱 이동 → 복귀 시 doubling 없음
- [ ] IntelliJ: 조합 중 Shift+방향키 한 번에 selection 확장
- [ ] 일반: 마우스 클릭/드래그가 평소처럼 즉각 반응 (ClickMonitor 지연 없음)
- [ ] 안정성: VSCode 등에서 조합 중 다른 앱 클릭 반복해도 crash 없음

회귀 발견 시 즉시 변경 revert 또는 별도 분기 처리. 검증 안 한 채 다음 client로 진행 금지.

## 디버그 로그

기본은 OFF. 환경설정 창의 "디버그" 체크박스를 켜면 활성화 (Preferences.shared.debugLogging). 또한 환경설정 창 안에서 실시간 로그를 바로 볼 수 있음 (터미널 불필요). 켠 후 터미널에서 보려면:

```bash
# 우리 subsystem 로그만:
log stream --predicate 'subsystem == "kr.ra1n.inputmethod.ra1nime"' --info
# ClickMonitor의 NSLog(설치/실패)까지 보려면 process 기준:
log stream --predicate 'process == "ra1nIME"' --info
```

코드상 `imeLog`는 `DebugLogger` 래퍼라 OFF 상태에서는 `@autoclosure` 평가도 안 일어남 — 입력 hot path에 비용 0. `DebugLogger`는 메모리 ring buffer(최근 500줄)도 유지해서 환경설정 창의 로그 뷰에 표시.

주요 체크포인트는 `RA1N` 접두어로 출력:
- `RA1N kd kc=<keycode> mods=0x<flags>` — handleKeyDown 진입
- `RA1N setMarker s=<text>` — 조합 중 marker 표시
- `RA1N clearMarker` — marker 비움
- `RA1N commit committed=<text> composing=<text>` — syllable 완성
- `RA1N endComposition composing=<text>` — composition 종료
- `RA1N commitAndRepost kc=<keycode> delay=<sec>` — 명시적 repost
- `RA1N activateServer` / `deactivateServer` / `commitComposition` — IMK lifecycle
- `RA1N mouseDown idx=<index>` — 마우스 클릭
- `RA1N flagsChanged kc=<keycode> mods=<flags>` — 모디파이어 키 down/up
- `RA1N cmd-down → preemptive commit` — Cmd modifier 누름 시 우리가 마커 commit (Chromium doubling 회피용)
- `RA1N handle type=<eventType> kc=<keycode>` — 모든 IMK 이벤트 진입

증상 발생 시 해당 시점 로그를 캡처해 분석할 것.
