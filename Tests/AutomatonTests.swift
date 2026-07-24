import Foundation

// HangulAutomaton / Keymap 단위 테스트.
//
// 이 입력기의 최우선 목표는 "한글을 문제없이 입력"하는 것이며, 그 정확성은
// 순수 로직인 HangulAutomaton(IMK 의존 없음)에 집중되어 있다.
// 이 파일은 그 엔진을 실제 앱 없이 검증한다.
//
// 실행: `make test`
//   Sources/HangulAutomaton.swift + Sources/Keymap.swift 와 함께 컴파일되어
//   독립 실행되며, 하나라도 실패하면 종료 코드 1을 반환한다.
//
// 주의: 이 테스트는 조합 엔진의 정확성만 다룬다. IMK 통합부(마커 커밋,
// 앱 전환 시 커밋, 이벤트 재주입 등)는 여기서 검증하지 못하며
// docs/test_cases.md 의 수동 시나리오로 확인한다.

// MARK: - 미니 테스트 프레임워크

var passCount = 0
var failCount = 0

func check(_ actual: String, _ expected: String, _ desc: String) {
    if actual == expected {
        passCount += 1
    } else {
        failCount += 1
        print("❌ \(desc): 기대 \"\(expected)\" 이지만 \"\(actual)\" 나옴")
    }
}

func check(_ actual: String?, _ expected: String, _ desc: String) {
    if actual == expected {
        passCount += 1
    } else {
        let shown = actual.map { "\"\($0)\"" } ?? "nil"
        failCount += 1
        print("❌ \(desc): 기대 \"\(expected)\" 이지만 \(shown) 나옴")
    }
}

func check(_ cond: Bool, _ desc: String) {
    if cond {
        passCount += 1
    } else {
        failCount += 1
        print("❌ \(desc)")
    }
}

// MARK: - 헬퍼

/// 자모 시퀀스를 엔진에 순서대로 입력하고 "화면에 보이는 최종 텍스트"를 재구성.
/// (커밋된 텍스트 + 남아있는 조합 중 음절)
func render(_ jamos: [Character]) -> String {
    let a = HangulAutomaton()
    var out = ""
    for j in jamos {
        switch a.input(j) {
        case .composing:
            break
        case .commit(let committed, _):
            out += committed
        }
    }
    return out + a.currentComposition()
}

/// 문자열을 자모 배열로 편하게 쓰기 위한 헬퍼.
func j(_ s: String) -> [Character] { Array(s) }

// MARK: - 테스트

func testBasic() {
    check(render(j("ㄱㅏ")), "가", "기본 초성+중성")
    check(render(j("ㅎㅏㄴ")), "한", "초성+중성+종성")
    check(render(j("ㅎㅏㄴㄱㅡㄹ")), "한글", "받침 뒤 새 음절")
    check(render(j("ㅇㅏㄴㄴㅕㅇ")), "안녕", "받침 ㄴ + 다음 음절 초성 ㄴ")
    check(render(j("ㄱㅏㄱㅏ")), "가가", "완성 후 새 음절")
}

func testDoubleFinal() {
    // 겹받침 11종 — 실제 한글 음절로 검증
    check(render(j("ㅁㅗㄱㅅ")), "몫", "겹받침 ㄳ")
    check(render(j("ㅇㅏㄴㅈ")), "앉", "겹받침 ㄵ")
    check(render(j("ㅁㅏㄴㅎ")), "많", "겹받침 ㄶ")
    check(render(j("ㄷㅏㄹㄱ")), "닭", "겹받침 ㄺ")
    check(render(j("ㅅㅏㄹㅁ")), "삶", "겹받침 ㄻ")
    check(render(j("ㄷㅓㄹㅂ")), "덟", "겹받침 ㄼ")
    check(render(j("ㄱㅗㄹㅅ")), "곬", "겹받침 ㄽ")
    check(render(j("ㅎㅏㄹㅌ")), "핥", "겹받침 ㄾ")
    check(render(j("ㅇㅡㄹㅍ")), "읊", "겹받침 ㄿ")
    check(render(j("ㅇㅏㄹㅎ")), "앓", "겹받침 ㅀ")
    check(render(j("ㄱㅏㅂㅅ")), "값", "겹받침 ㅄ")
}

func testDoubleMedial() {
    // 이중모음(복합 중성) 7종 — test_cases.md 에 누락돼 있던 커버리지
    check(render(j("ㄱㅗㅏ")), "과", "이중모음 ㅘ")
    check(render(j("ㅇㅗㅐ")), "왜", "이중모음 ㅙ")
    check(render(j("ㅇㅗㅣ")), "외", "이중모음 ㅚ")
    check(render(j("ㅇㅜㅓ")), "워", "이중모음 ㅝ")
    check(render(j("ㅇㅜㅔ")), "웨", "이중모음 ㅞ")
    check(render(j("ㅇㅜㅣ")), "위", "이중모음 ㅟ")
    check(render(j("ㅇㅡㅣ")), "의", "이중모음 ㅢ")
}

func testLiaison() {
    // 연음: 종성이 뒤 모음의 초성으로 이동
    check(render(j("ㄱㅏㄹㅏ")), "가라", "홑받침 연음 이동")
    check(render(j("ㄷㅏㄹㄱㅣ")), "달기", "겹받침 뒷자음만 이동")
}

func testCannotBeFinal() {
    // ㄸ, ㅃ, ㅉ 는 종성이 될 수 없으므로 커밋 후 새 초성으로 시작
    check(render(j("ㄱㅏㄸ")), "가ㄸ", "ㄸ 종성 불가 → 새 초성")
    check(render(j("ㄱㅏㅃ")), "가ㅃ", "ㅃ 종성 불가 → 새 초성")
}

func testDefensiveFallback() {
    // 유효 자모(초/중성)가 아닌 문자가 들어오면 진행 중 조합을 커밋하고
    // 그 문자를 그대로 덧붙인다. 실제 호출처(Keymap)에선 도달하지 않지만,
    // 오용 시에도 크래시 없이 안전하게 처리해야 한다.
    check(render(j("ㄱㅏX")), "가X", "비자모 입력 시 조합 커밋 후 덧붙임")
    check(render(j("X")), "X", "빈 조합에서 비자모 입력")
}

func testBackspace() {
    // 닭(ㄷㅏㄹㄱ) 조합을 단계적으로 지운다
    let a = HangulAutomaton()
    for c in j("ㄷㅏㄹㄱ") { _ = a.input(c) }
    check(a.backspace(), "달", "닭 → 달 (겹받침 뒷자음 삭제)")
    check(a.backspace(), "다", "달 → 다 (받침 삭제)")
    check(a.backspace(), "ㄷ", "다 → ㄷ (중성 삭제)")
    check(a.backspace(), "", "ㄷ → 빈 조합 (초성 삭제)")
    check(a.backspace() == nil, "빈 상태에서 백스페이스는 nil (앱에 위임)")
}

func testBackspaceDoubleMedial() {
    // 과(ㄱㅗㅏ)에서 백스페이스 시 ㅘ → ㅗ 로 분해
    let a = HangulAutomaton()
    for c in j("ㄱㅗㅏ") { _ = a.input(c) }
    check(a.backspace(), "고", "과 → 고 (이중모음 분해)")
    check(a.backspace(), "ㄱ", "고 → ㄱ (중성 삭제)")
}

func testKeymapSanity() {
    // 자판 매핑: 영문 → 자모, 숫자/기호는 nil(그대로 통과)
    check(Keymap.toJamo("r", shift: false) == "ㄱ", "keymap r → ㄱ")
    check(Keymap.toJamo("k", shift: false) == "ㅏ", "keymap k → ㅏ")
    check(Keymap.toJamo("R", shift: true) == "ㄲ", "keymap Shift+r → ㄲ")
    check(Keymap.toJamo("O", shift: true) == "ㅒ", "keymap Shift+o → ㅒ")
    check(Keymap.toJamo("1", shift: false) == nil, "keymap 숫자 1 → nil")
    check(Keymap.toJamo(";", shift: false) == nil, "keymap 기호 → nil")
}

// MARK: - 실행

@main
struct AutomatonTests {
    static func main() {
        testBasic()
        testDoubleFinal()
        testDoubleMedial()
        testLiaison()
        testCannotBeFinal()
        testDefensiveFallback()
        testBackspace()
        testBackspaceDoubleMedial()
        testKeymapSanity()

        let total = passCount + failCount
        print("\n결과: \(passCount)/\(total) 통과", failCount == 0 ? "✅" : "❌ (\(failCount) 실패)")
        exit(failCount == 0 ? 0 : 1)
    }
}
