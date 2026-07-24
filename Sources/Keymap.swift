import Foundation

enum Keymap {
    private static let plain: [Character: Character] = [
        "q": "ㅂ", "w": "ㅈ", "e": "ㄷ", "r": "ㄱ", "t": "ㅅ",
        "y": "ㅛ", "u": "ㅕ", "i": "ㅑ", "o": "ㅐ", "p": "ㅔ",
        "a": "ㅁ", "s": "ㄴ", "d": "ㅇ", "f": "ㄹ", "g": "ㅎ",
        "h": "ㅗ", "j": "ㅓ", "k": "ㅏ", "l": "ㅣ",
        "z": "ㅋ", "x": "ㅌ", "c": "ㅊ", "v": "ㅍ", "b": "ㅠ",
        "n": "ㅜ", "m": "ㅡ",
    ]

    // Shift를 누를 때만 바뀌는 자모. 나머지는 plain 매핑을 그대로 따름.
    private static let shifted: [Character: Character] = [
        "q": "ㅃ", "w": "ㅉ", "e": "ㄸ", "r": "ㄲ", "t": "ㅆ",
        "o": "ㅒ", "p": "ㅖ",
    ]

    static func toJamo(_ c: Character, shift: Bool) -> Character? {
        let lower = Character(c.lowercased())
        if shift, let s = shifted[lower] { return s }
        return plain[lower]
    }
}
