# ra1nIME 한글 입력기 — 인계 문서

> 다음 대화에서 이어가기 위한 컨텍스트. 마지막 작업 상태와 미해결 이슈, 그리고 다음 단계로 제안한 아키텍처 변경 계획을 정리.

> ⚠️ **이 문서는 과거 스냅샷입니다 (구 마커 아키텍처 기준).** 정본은 [AGENTS.md](../AGENTS.md).
>
> - 아래 **2·3·5절**은 초기 마커 구조, 그 시점의 미해결 이슈, 그리고 *채택되지 않은* 리팩토링 계획(인라인 commit)을 서술합니다. **현재 코드는 인라인 commit으로 가지 않았고**, 마커 방식을 유지하되 focus-loss 문제를 다른 방식(Cmd-down 선제 커밋 + `ClickMonitor` + `commitAndRepost`)으로 해결했습니다.
> - 이 문서가 참조하는 `deferCommitForFocusLoss`·`flushDeferredCommit`·`pendingCommit` 함수는 **현재 코드에 존재하지 않습니다.**
> - **3절의 미해결 이슈**(Notes/Terminal 커밋 소실, chat doubling)는 위 해결책 도입 *이전* 상태이며, **2026-07-24 수동 검증에서 모두 해결이 확인**되었습니다. 3절 표의 ✗는 과거 기록으로 보존합니다.
> - 단, **4절(Apple KoreanIM 분석, Monaco ZWSP 트릭, 클라이언트별 marker 특성)** 은 여전히 유효한 배경지식입니다.

## 1. 프로젝트 개요

macOS용 한글 IME. `IMKInputController`를 서브클래싱한 IMK 입력기. 핵심 코어 파일:

- `Sources/HangulInputController.swift` — IMK lifecycle, 마우스/키 처리, marker/insertText 호출
- `Sources/HangulAutomaton.swift` — 한글 조합 오토마톤 (초/중/종성 결합)
- `Sources/Keymap.swift` — 키 코드 → 자모 매핑
- `Sources/GlobalKeyTap.swift` — 시스템 레벨 키 이벤트 가로채기 (한/영 토글)
- `Sources/main.swift`, `Preferences.swift`, `PreferencesWindow.swift`, `StatusBarController.swift`, `PermissionChecker.swift`

번들 ID: `kr.ra1n.inputmethod.ra1nime`
빌드: `make`. 설치+캐시 갱신: `make refresh` (sudo 필요).

## 2. 핵심 동작 흐름 (현재 마커 기반)

조합 중:
1. 사용자 키 입력 → `handleKeyDown` → 자모 변환
2. `automaton.input(jamo)` → `.composing(s)` 또는 `.commit(committed, composing)`
3. `setMarker(s)` → `client.setMarkedText(attributedStr, ...)` 로 marker 표시
4. `.commit`일 땐 `insert(committed)` 후 `setMarker(composing)` 또는 `clearMarker()`

Focus loss (cmd+tab 또는 마우스 클릭):
1. cmd+tab 키: `handleKeyDown`의 special 분기 → `deferCommitForFocusLoss` 후 `return false`로 자연 통과
2. `commitComposition` 또는 `deactivateServer` 호출 → `deferCommitForFocusLoss`
3. `deferCommitForFocusLoss`: 현재는 `setMarkedText("")` 호출 + `pendingCommit`에 저장

Focus return:
1. `activateServer` → `flushDeferredCommit`
2. `flushDeferredCommit`: client의 markedRange, selectedRange, attributedSubstring(mr), attributedSubstring(beforeRange) 조회 → decision tree로 처리

## 3. 미해결된 이슈와 현 상태

> ✅ **갱신(2026-07-24): 아래 ✗ 항목(Notes/Terminal 커밋 소실, chat doubling)은 수동 검증에서 모두 해결이 확인되었습니다.** 아래 표는 당시 스냅샷으로 보존합니다. 현재 검증된 client 목록은 [AGENTS.md](../AGENTS.md) 참조.

| 시나리오 | 상태 | 비고 |
|---|---|---|
| Notes에서 한글 commit | ✗ 사라짐 | Cmd+Tab 복귀 시 조합 글자 소실 |
| Notes 1-클릭 cursor 이동 | ✓ | `mouseDownOnCharacterIndex` 오버라이드로 해결 |
| Terminal commit | ✗ 사라짐 | Cmd+Tab 복귀 시 조합 글자 소실 |
| Chat (VSCode Claude Code) doubling | ✗ leaving 시점에 발생 | "에" 조합 후 cmd+tab 시 "에에" |
| Chat cursor 위치 | ✗ 한 글자 앞으로 이동 | Chromium 자체 동작 |
| VSCode editor (Monaco) | ✓ 일단 정상 | 초기엔 Home → SOH 등 다양했음. ZWSP 트릭으로 안정 |

> 가장 마지막 변경: `deferCommitForFocusLoss`에서 `setMarkedText("")`만 호출하고 `insertText`는 안 함 + `pendingCommit` 저장. 이걸로 chat doubling은 거의 사라졌지만 Notes/Terminal에서 글자 소실 발생.

## 4. 그동안 발견한 주요 통찰

### 4.1 Apple KoreanIM 분석 결과 (가장 중요)

`/System/Library/Input Methods/KoreanIM.app/Contents/PlugIns/KIM_Extension.appex` 바이너리의 strings 분석:

```
IMKActiveCompositionController
initWithTextInputToAdapt:traits:candidateMenu:alwaysShowsComposingTextAsMarkedText:
setShowsComposingTextAsMarkedText:
showsComposingTextAsMarkedText
```

Apple은 **`alwaysShowsComposingTextAsMarkedText: NO`** 옵션이 있는 private `IMKActiveCompositionController` 클래스를 사용. 이건 조합 중인 글자를 **marker로 표시하지 않고 즉시 committed text로 doc에 삽입**하면서 IME가 그 위치를 내부적으로 추적하는 패턴.

이게 우리가 만난 모든 marker 관련 문제의 근본 해결책. 다음 작업의 핵심 방향임.

### 4.2 IMK 헤더 문서 핵심 발견

`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/.../IMKInputController.h`:

- `markForStyle:atRange:` 문서: "the appropriate underline and underline color information is added to the attributes dictionary for the style parameter" — 즉 IMK가 자동으로 underline 추가. kTSMHiliteConvertedText 써도 underline 안 사라짐. NSTextView가 marker range만 보고 자체적으로 underline 그리는 것으로 추정.
- `recognizedEvents`: 기본값이 NSKeyDownMask만 포함. mouseDown 추가 안 하면 IMK가 click을 가로채서 commitComposition만 호출하고 client에 전달 안 함 → Notes에서 1-click 동작 안 됨. `leftMouseDown` 추가 + `mouseDownOnCharacterIndex` 오버라이드해서 해결.

### 4.3 클라이언트별 marker 처리 특성

| 클라이언트 | marker 보존 (focus loss) | auto-commit | `attributedSubstring(mr)` 보고 |
|---|---|---|---|
| Notes (NSTextView) | discard | ✗ | "마" 반환 (marker 속성?) |
| Terminal.app | discard | ✗ | nil (TSMDocumentAccess 미지원) |
| VSCode editor (Monaco) | 변동, 종종 stale | ✗ | 가끔 control char ("\^A", "\^H" 등) 반환 |
| VSCode chat (Chromium contenteditable) | 별도 buffer에 보존 | ✓ (focus loss 시) | "에" 반환 |

### 4.4 Monaco의 broken keybinding mode

`setMarkedText("")`를 **활성화 시점(`activateServer`)에** 호출하면 Monaco가 "stuck keybinding" 모드에 빠짐 — 다음 Home은 Ctrl+A(SOH, 0x01)로, Backspace는 Ctrl+H(BS, 0x08)로 doc에 삽입됨. 화살표 키 한 번 누르면 해소.

해결: **ZWSP(U+200B) 트릭**. marker를 `setMarkedText("\u{200B}", replacementRange: mr)`로 덮어쓴 뒤 `setMarkedText("")`로 비움. ZWSP가 normal char라 Monaco state machine이 정상 경로로 marker 정리.

이 트릭은 `flushDeferredCommit`의 모든 skip 경로에 적용 가능. 단, Notes/Terminal에서는 ZWSP가 doc 텍스트를 진짜 ZWSP로 바꿔버려서 부작용 → "정상" marker 상태는 plain `setMarkedText("")` 사용.

### 4.5 Cmd+Tab vs 마우스 클릭 차이

- **Cmd+Tab**: 우리가 `handleKeyDown`에서 가로채면 synthetic CGEvent.post 호출. 이게 Monaco를 stale marker 상태(control char가 marker에 들어감)로 진입시킴.
- **마우스 클릭**: 우리 IME가 가로채지 않으니 자연스러운 focus 전환.
- **해결**: Cmd+Tab은 `deferCommitForFocusLoss`만 호출하고 `return false`로 자연 통과시킴.

## 5. 다음 작업: 인라인 commit 아키텍처로 리팩토링

### 5.1 개요

`setMarkedText`/marker 메커니즘 전체를 제거하고, Apple KoreanIM처럼 인라인 commit으로 전환.

### 5.2 핵심 아이디어

조합 중인 글자도 **doc에 committed text로 즉시 삽입**. IME 내부적으로 그 텍스트의 범위(`compositionRange: NSRange?`)를 추적해서, 새 자모 입력 시 그 범위의 텍스트를 새 syllable로 교체.

Focus loss 시점에 marker가 없으니 commit/doubling 문제 자체가 사라짐.

### 5.3 구현 스케치

```swift
// 새 상태
private var compositionRange: NSRange?  // 현재 조합 중인 텍스트의 doc 내 범위

// setMarker → updateCompositionDisplay 로 교체
private func updateCompositionDisplay(_ s: String, sender: Any?) {
    guard let client = sender as? IMKTextInput else { return }
    let range = compositionRange ?? NSRange(location: NSNotFound, length: 0)
    client.insertText(s, replacementRange: range)
    let cursor = client.selectedRange()
    if cursor.location != NSNotFound, cursor.location >= s.utf16.count {
        compositionRange = NSRange(location: cursor.location - s.utf16.count,
                                   length: s.utf16.count)
    } else {
        compositionRange = nil
    }
}

// clearMarker → endComposition 으로 교체
private func endComposition() {
    compositionRange = nil
}
```

### 5.4 handleKeyDown 변경 예시

```swift
switch automaton.input(jamo) {
case .composing(let s):
    updateCompositionDisplay(s, sender: sender)
case .commit(_, let composing):
    // committed는 doc에 이미 있음. 새 syllable 시작.
    endComposition()  // compositionRange = nil
    if !composing.isEmpty {
        updateCompositionDisplay(composing, sender: sender)
    }
}
```

### 5.5 focus loss / return 처리

```swift
override func commitComposition(_ sender: Any!) {
    // 이미 doc에 있으니 아무것도 안 함. 그냥 상태 정리.
    automaton.reset()
    compositionRange = nil
}

override func activateServer(_ sender: Any!) {
    super.activateServer(sender)
    // 이미 doc에 있으니 할 일 없음.
}
```

### 5.6 Backspace, Space, Enter 등 처리

- **Backspace**: `automaton.backspace()` 결과로 `updateCompositionDisplay(updatedString)`. updated 가 빈 문자열이면 `insertText("", replacementRange: compositionRange)` 로 doc에서 제거.
- **Space**: composition 종료(`compositionRange = nil`) + `insertText(" ")`. 자모는 이미 doc에 있으니 추가 commit 불필요.
- **Enter/Tab**: composition 종료 + 키 자연 전달.
- **모드 토글 (한↔영)**: composition 종료 + 토글.

### 5.7 마우스 클릭

`mouseDownOnCharacterIndex`: composition 종료. `return false`로 click 자연 통과 → cursor 이동. (현재와 동일한 패턴.)

### 5.8 예상 효과

- 밑줄 사라짐 (marker 자체가 없음)
- Doubling 안 일어남 (focus loss 시 commit할 marker 없음)
- Notes/Terminal commit 손실 없음 (이미 doc에 있음)
- Chat의 별난 cursor 위치 문제도 해소 가능 (Chromium 입장에서 그냥 plain text 입력)
- Apple 시스템 IME와 시각적/기능적 동일성

### 5.9 리스크

- 핵심 로직 대규모 변경 — 한글 조합 자체가 깨질 수 있어서 모든 자모 조합 시나리오 다시 검증 필요
- `client.selectedRange()` 의존도 증가 — 일부 클라이언트에서 NSNotFound 반환 시 fallback 필요
- 한/영 토글, Cmd+조합, Enter, Backspace 등 기존 동작 모두 재검증

### 5.10 구현 단계 제안

1. 새 `compositionRange` 상태 추가, 기존 marker 호출 자리에 `updateCompositionDisplay` placeholder만 우선 배치
2. `handleKeyDown`의 `.composing` / `.commit` 분기를 인라인 commit으로 전환
3. Backspace, Space, Enter, Mode toggle 등 각 경로 검증
4. `commitComposition` / `deactivateServer` / `activateServer` 단순화 (대부분 no-op)
5. `flushDeferredCommit` 제거 (불필요)
6. `mouseDownOnCharacterIndex` 단순화 (composition만 종료)
7. 기존 디버그 로그 정리

## 6. 코드 위치 변경

이전 위치: `/Volumes/data/trash/mac-hangul/`
새 위치: `/Volumes/data/kp/myproject/ra1n-ime/`

`.git`이 새 위치에 이미 있음. 새 대화에서 새 위치 기준으로 작업.

## 7. 디버깅 도구

- 시스템 콘솔 로그 (현재 코드의 `imeLog.notice` 출력):
  ```bash
  log stream --predicate 'subsystem == "kr.ra1n.inputmethod.ra1nime"' --info
  ```
  형식: `flushDeferred text=... mr=... sel=... mrStr=... beforeStr=... → 결정`
- `make refresh` 후 별도 입력기 toggle 불필요 (캐시 자동 갱신).

## 8. 메모리 관련

이전 대화에서 저장한 메모리 (`/Users/dhpark/.claude/projects/-Volumes-data-trash-mac-hangul/memory/`):
- `macos26_ime_registration.md` — IME 등록 이슈 (해결됨, Apple Development 서명)
- `hangulpoc_enter_handling.md` — Enter 처리 패턴 (이전 상태)

새 위치에선 메모리 경로도 바뀔 수 있음. 새 대화에서 ZWSP 트릭과 Apple KIM의 인라인 commit 패턴을 다시 메모리 저장 권장.
