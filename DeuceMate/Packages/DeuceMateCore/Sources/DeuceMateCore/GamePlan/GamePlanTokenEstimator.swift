// GamePlanTokenEstimator.swift — a dependency-free, on-device estimate of
// how many input tokens a block of text will cost an AI model.
//
// It is an ESTIMATE. Every model family tokenizes differently, AI apps add
// their own wrapping and file handling, and nothing here contacts a service.
// The heuristic counts the text's own shape instead of applying a flat
// characters-per-token rule, because the evidence pack mixes English prose,
// Markdown tables full of short numbers and symbols, and free-text notes in
// any language:
//
// - ASCII word runs: one token up to `freeWordLength` letters (common English
//   words are single tokens), then one more per further `wordCharsPerToken`
//   letters. A single leading space joins the word (BPE merges " the").
// - Digit runs: one token per `digitsPerToken` digits.
// - ASCII punctuation: one token per character, except runs of the same
//   character ("---", "...") which compress.
// - Spaces/tabs beyond the one a word absorbs, and each newline run: one token.
// - CJK ideographs and kana: `cjkTokensPerChar` per character; Hangul
//   syllables `hangulTokensPerChar`.
// - Other non-ASCII letters/marks inside a word (é, ß, ç, Cyrillic, Greek…):
//   `otherLetterTokensPerChar` per character.
// - Emoji: `emojiTokens` each (variation selectors and joiners are free).
// - Other symbols (en dash, ·, →): `symbolTokens` each.
// - The sum is scaled by `scale`, chosen so whole packs land slightly above
//   the reference tokenizers rather than below them.
//
// The constants were calibrated against reference tokenizers on prose, point
// table and multilingual fixtures; the measured error and method are recorded
// in docs/features/OPPONENT_GAME_PLAN_PROPOSAL.md §11 and pinned by
// GamePlanTokenEstimatorTests.
import Foundation

public struct GamePlanTokenEstimate: Equatable, Sendable {
    /// The raw estimate. Show `label`, never this number, to a person.
    public let tokens: Int

    public init(tokens: Int) {
        self.tokens = max(0, tokens)
    }

    public init(text: String) {
        self.init(tokens: GamePlanTokenEstimator.estimate(text))
    }

    /// Rounded to avoid false precision: nearest 10 under 1,000, nearest 100
    /// under 10,000, nearest 1,000 above.
    public var rounded: Int {
        let step: Int
        switch tokens {
        case ..<1_000:  step = 10
        case ..<10_000: step = 100
        default:        step = 1_000
        }
        return max(step, Int((Double(tokens) / Double(step)).rounded()) * step)
    }

    /// "~12,000 tokens".
    public var label: String {
        "~\(Self.grouped(rounded)) tokens"
    }

    /// "Estimated input: ~12,000 tokens".
    public var inputLabel: String { "Estimated input: \(label)" }

    /// Locale-independent thousands grouping so tests and copy are stable.
    static func grouped(_ value: Int) -> String {
        let digits = String(value)
        var out = ""
        for (index, char) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(char)
        }
        return out
    }
}

public enum GamePlanTokenEstimator {

    // Calibrated constants (see the file header).
    static let freeWordLength = 11
    static let wordCharsPerToken = 3.0
    static let digitsPerToken = 3.0
    static let repeatedPunctuationPerToken = 8.0
    static let cjkTokensPerChar = 1.0
    static let hangulTokensPerChar = 1.3
    static let emojiTokens = 2.0
    static let otherLetterTokensPerChar = 0.5
    static let symbolTokens = 1.0
    /// Overall scale applied to the summed estimate.
    static let scale = 1.05

    /// How far the estimate is expected to land from a reference tokenizer
    /// on the calibration fixtures (see the file header). Shown in the
    /// screen's explanation.
    public static let documentedErrorPercent = 10

    public static func estimate(_ text: String) -> Int {
        var total = 0.0
        var wordLength = 0          // ASCII letters in the current word
        var digitRun = 0
        var punctuation: Unicode.Scalar?
        var punctuationRun = 0
        var pendingSpaces = 0       // spaces since the last non-space
        var inNewlineRun = false

        func flushWord() {
            guard wordLength > 0 else { return }
            total += wordLength <= freeWordLength
                ? 1
                : 1 + (Double(wordLength - freeWordLength) / wordCharsPerToken).rounded(.up)
            wordLength = 0
        }
        func flushDigits() {
            guard digitRun > 0 else { return }
            total += (Double(digitRun) / digitsPerToken).rounded(.up)
            digitRun = 0
        }
        func flushPunctuation() {
            guard punctuationRun > 0 else { return }
            total += punctuationRun == 1 ? 1 : max(1, (Double(punctuationRun) / repeatedPunctuationPerToken).rounded(.up))
            punctuationRun = 0
            punctuation = nil
        }
        func flushSpaces(absorbedByNext: Bool) {
            // One space before a token is free; any extra spacing is one token.
            let extra = absorbedByNext ? pendingSpaces - 1 : pendingSpaces
            if extra > 0 { total += 1 }
            pendingSpaces = 0
        }

        for scalar in text.unicodeScalars {
            let v = scalar.value
            if scalar == "\n" || scalar == "\r" {
                flushWord(); flushDigits(); flushPunctuation()
                pendingSpaces = 0
                if !inNewlineRun { total += 1; inNewlineRun = true }
                continue
            }
            inNewlineRun = false
            if scalar == " " || scalar == "\t" {
                flushWord(); flushDigits(); flushPunctuation()
                pendingSpaces += 1
                continue
            }
            let hadSpaces = pendingSpaces > 0
            if hadSpaces { flushSpaces(absorbedByNext: true) }

            if (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) {
                if hadSpaces { flushWord() }
                flushDigits(); flushPunctuation()
                wordLength += 1
            } else if v >= 0x30 && v <= 0x39 {
                flushWord(); flushPunctuation()
                digitRun += 1
            } else if v < 0x80 {
                flushWord(); flushDigits()
                if scalar == punctuation {
                    punctuationRun += 1
                } else {
                    flushPunctuation()
                    punctuation = scalar
                    punctuationRun = 1
                }
            } else if (0xAC00...0xD7AF).contains(v) {
                flushWord(); flushDigits(); flushPunctuation()
                total += hangulTokensPerChar
            } else if v >= 0x1F000 {
                flushWord(); flushDigits(); flushPunctuation()
                total += emojiTokens
            } else if (0xFE00...0xFE0F).contains(v) || v == 0x200D {
                continue
            } else if isCJK(v) {
                flushWord(); flushDigits(); flushPunctuation()
                total += cjkTokensPerChar
            } else if scalar.properties.isAlphabetic || scalar.properties.generalCategory == .nonspacingMark {
                // Accented and non-Latin letters: part of the word, but they
                // split BPE merges far more often than ASCII letters do.
                flushDigits(); flushPunctuation()
                if hadSpaces { flushWord() }
                total += otherLetterTokensPerChar
            } else {
                flushWord(); flushDigits(); flushPunctuation()
                total += symbolTokens
            }
        }
        flushWord(); flushDigits(); flushPunctuation()
        flushSpaces(absorbedByNext: false)
        return Int((total * scale).rounded())
    }

    static func isCJK(_ v: UInt32) -> Bool {
        (0x3040...0x30FF).contains(v)       // Hiragana, Katakana
            || (0x3400...0x4DBF).contains(v)  // CJK Extension A
            || (0x4E00...0x9FFF).contains(v)  // CJK Unified Ideographs
            || (0xF900...0xFAFF).contains(v)  // CJK Compatibility Ideographs
            || (0xFF00...0xFFEF).contains(v)  // Half/full-width forms
            || (0x20000...0x2FFFF).contains(v)
    }
}
