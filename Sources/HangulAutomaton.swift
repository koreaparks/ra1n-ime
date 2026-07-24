import Foundation

enum Jamo {
    static let choseongTable: [Character: Int] = [
        "ㄱ": 0, "ㄲ": 1, "ㄴ": 2, "ㄷ": 3, "ㄸ": 4,
        "ㄹ": 5, "ㅁ": 6, "ㅂ": 7, "ㅃ": 8, "ㅅ": 9,
        "ㅆ": 10, "ㅇ": 11, "ㅈ": 12, "ㅉ": 13, "ㅊ": 14,
        "ㅋ": 15, "ㅌ": 16, "ㅍ": 17, "ㅎ": 18,
    ]

    static let jungseongTable: [Character: Int] = [
        "ㅏ": 0, "ㅐ": 1, "ㅑ": 2, "ㅒ": 3, "ㅓ": 4,
        "ㅔ": 5, "ㅕ": 6, "ㅖ": 7, "ㅗ": 8, "ㅘ": 9,
        "ㅙ": 10, "ㅚ": 11, "ㅛ": 12, "ㅜ": 13, "ㅝ": 14,
        "ㅞ": 15, "ㅟ": 16, "ㅠ": 17, "ㅡ": 18, "ㅢ": 19,
        "ㅣ": 20,
    ]

    static let jongseongTable: [Character: Int] = [
        "ㄱ": 1, "ㄲ": 2, "ㄳ": 3, "ㄴ": 4, "ㄵ": 5,
        "ㄶ": 6, "ㄷ": 7, "ㄹ": 8, "ㄺ": 9, "ㄻ": 10,
        "ㄼ": 11, "ㄽ": 12, "ㄾ": 13, "ㄿ": 14, "ㅀ": 15,
        "ㅁ": 16, "ㅂ": 17, "ㅄ": 18, "ㅅ": 19, "ㅆ": 20,
        "ㅇ": 21, "ㅈ": 22, "ㅊ": 23, "ㅋ": 24, "ㅌ": 25,
        "ㅍ": 26, "ㅎ": 27,
    ]

    static let jongseongCombos: [Character: [Character: Character]] = [
        "ㄱ": ["ㅅ": "ㄳ"],
        "ㄴ": ["ㅈ": "ㄵ", "ㅎ": "ㄶ"],
        "ㄹ": ["ㄱ": "ㄺ", "ㅁ": "ㄻ", "ㅂ": "ㄼ", "ㅅ": "ㄽ", "ㅌ": "ㄾ", "ㅍ": "ㄿ", "ㅎ": "ㅀ"],
        "ㅂ": ["ㅅ": "ㅄ"],
    ]

    static let jongseongSplit: [Character: (Character, Character)] = [
        "ㄳ": ("ㄱ", "ㅅ"), "ㄵ": ("ㄴ", "ㅈ"), "ㄶ": ("ㄴ", "ㅎ"),
        "ㄺ": ("ㄹ", "ㄱ"), "ㄻ": ("ㄹ", "ㅁ"), "ㄼ": ("ㄹ", "ㅂ"),
        "ㄽ": ("ㄹ", "ㅅ"), "ㄾ": ("ㄹ", "ㅌ"), "ㄿ": ("ㄹ", "ㅍ"),
        "ㅀ": ("ㄹ", "ㅎ"), "ㅄ": ("ㅂ", "ㅅ"),
    ]

    static let jungseongCombos: [Character: [Character: Character]] = [
        "ㅗ": ["ㅏ": "ㅘ", "ㅐ": "ㅙ", "ㅣ": "ㅚ"],
        "ㅜ": ["ㅓ": "ㅝ", "ㅔ": "ㅞ", "ㅣ": "ㅟ"],
        "ㅡ": ["ㅣ": "ㅢ"],
    ]

    static let jungseongSplit: [Character: (Character, Character)] = [
        "ㅘ": ("ㅗ", "ㅏ"), "ㅙ": ("ㅗ", "ㅐ"), "ㅚ": ("ㅗ", "ㅣ"),
        "ㅝ": ("ㅜ", "ㅓ"), "ㅞ": ("ㅜ", "ㅔ"), "ㅟ": ("ㅜ", "ㅣ"),
        "ㅢ": ("ㅡ", "ㅣ"),
    ]
}

enum InputResult {
    case composing(String)
    case commit(committed: String, composing: String)
}

final class HangulAutomaton {
    private var L: Character?  // 초성
    private var V: Character?  // 중성
    private var T: Character?  // 종성

    var isEmpty: Bool { L == nil && V == nil && T == nil }

    func input(_ jamo: Character) -> InputResult {
        if Jamo.choseongTable[jamo] != nil {
            return inputConsonant(jamo)
        }
        if Jamo.jungseongTable[jamo] != nil {
            return inputVowel(jamo)
        }
        // 방어적 경로: 유효한 자모(초/중성)가 아니면 진행 중 조합을 커밋하고
        // 해당 문자를 그대로 덧붙인다. 현재 호출처(Keymap)는 항상 유효 자모만
        // 넘기므로 실제로는 도달하지 않지만, 오용 시 크래시 대신 안전하게 처리한다.
        let committed = currentComposition()
        reset()
        return .commit(committed: committed + String(jamo), composing: "")
    }

    private func inputConsonant(_ c: Character) -> InputResult {
        if L == nil && V != nil {
            let committed = currentComposition()
            reset()
            L = c
            return .commit(committed: committed, composing: currentComposition())
        }

        if L == nil && V == nil {
            L = c
            return .composing(currentComposition())
        }
        if L != nil && V == nil {
            let committed = currentComposition()
            reset()
            L = c
            return .commit(committed: committed, composing: currentComposition())
        }
        if V != nil && T == nil {
            if Jamo.jongseongTable[c] != nil {
                T = c
                return .composing(currentComposition())
            }
            // ㄸ, ㅃ, ㅉ 등은 종성이 될 수 없음. 커밋 후 새로 시작.
            let committed = currentComposition()
            reset()
            L = c
            return .commit(committed: committed, composing: currentComposition())
        }
        if let t = T, let combined = Jamo.jongseongCombos[t]?[c] {
            T = combined
            return .composing(currentComposition())
        }
        let committed = currentComposition()
        reset()
        L = c
        return .commit(committed: committed, composing: currentComposition())
    }

    private func inputVowel(_ v: Character) -> InputResult {
        if L == nil {
            if V == nil {
                V = v
                return .composing(currentComposition())
            } else {
                if let combined = Jamo.jungseongCombos[V!]?[v] {
                    V = combined
                    return .composing(currentComposition())
                }
                let committed = currentComposition()
                reset()
                V = v
                return .commit(committed: committed, composing: currentComposition())
            }
        }
        if V == nil {
            V = v
            return .composing(currentComposition())
        }
        if T == nil {
            if let combined = Jamo.jungseongCombos[V!]?[v] {
                V = combined
                return .composing(currentComposition())
            }
            let committed = currentComposition()
            reset()
            return .commit(committed: committed + String(v), composing: "")
        }
        // L+V+T 상태: 종성의 마지막 자소를 다음 음절 초성으로 이동.
        let movedL: Character
        let remainingT: Character?
        if let (first, second) = Jamo.jongseongSplit[T!] {
            remainingT = first
            movedL = second
        } else {
            remainingT = nil
            movedL = T!
        }
        T = remainingT
        let committed = currentComposition()
        reset()
        L = movedL
        V = v
        return .commit(committed: committed, composing: currentComposition())
    }

    func currentComposition() -> String {
        if isEmpty { return "" }
        if let l = L, let v = V {
            let lIdx = Jamo.choseongTable[l]!
            let vIdx = Jamo.jungseongTable[v]!
            let tIdx = T.map { Jamo.jongseongTable[$0]! } ?? 0
            let code = 0xAC00 + (lIdx * 21 + vIdx) * 28 + tIdx
            return String(UnicodeScalar(code)!)
        }
        if let l = L { return String(l) }
        if let v = V { return String(v) }
        return ""
    }

    func reset() {
        L = nil; V = nil; T = nil
    }

    /// 백스페이스 처리. 삭제할 것이 없으면 nil을 반환하고
    /// 호출처가 백스페이스를 앱에 그대로 전달해야 함.
    func backspace() -> String? {
        if let t = T {
            if let (first, _) = Jamo.jongseongSplit[t] {
                T = first
            } else {
                T = nil
            }
            return currentComposition()
        }
        if let v = V {
            if let (first, _) = Jamo.jungseongSplit[v] {
                V = first
            } else {
                V = nil
            }
            return currentComposition()
        }
        if L != nil {
            L = nil
            return currentComposition()
        }
        return nil
    }
}
