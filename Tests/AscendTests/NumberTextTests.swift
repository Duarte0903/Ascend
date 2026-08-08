import Testing
import Foundation
@testable import Ascend

private let pt = Locale(identifier: "pt_PT")
private let en = Locale(identifier: "en_US")

private func parse(_ text: String, _ locale: Locale = pt) -> Double? {
    NumberText.double(from: text, locale: locale)
}

// MARK: - The reported bug

/// Typing a grouped figure the Portuguese way — dot for thousands, comma for
/// decimals — used to fail to parse, so the field silently reverted.
@Test func parsesPortugueseGroupedInput() {
    #expect(parse("6.285,73") == 6285.73)
    #expect(parse("1.234.567,89") == 1234567.89)
    #expect(parse("25.000") == 25000)
}

@Test func parsesPlainCommaDecimals() {
    #expect(parse("6285,73") == 6285.73)
    #expect(parse("350,27") == 350.27)
    #expect(parse("0,5") == 0.5)
}

/// A dot decimal must keep working — people type both.
@Test func parsesDotDecimals() {
    #expect(parse("6285.73") == 6285.73)
    #expect(parse("0.5") == 0.5)
}

/// English-style grouping, in case it is pasted in from elsewhere.
@Test func parsesEnglishGroupedInput() {
    #expect(parse("6,285.73") == 6285.73)
    #expect(parse("1,234,567.89") == 1234567.89)
}

// MARK: - Formatting artefacts round-tripping back in

@Test func toleratesTheAppsOwnDisplayFormatting() {
    #expect(parse("8\u{202F}410\u{202F}€") == 8410)
    #expect(parse("6 285,73 €") == 6285.73)
    #expect(parse("12,2\u{202F}%") == 12.2)
}

// MARK: - Partial and awkward input

@Test func toleratesPartialInput() {
    #expect(parse(",5") == 0.5)
    #expect(parse("12,") == 12)
    #expect(parse("-50,25") == -50.25)
}

@Test func rejectsUnparseableInput() {
    #expect(parse("") == nil)
    #expect(parse("abc") == nil)
    #expect(parse("€") == nil)
    #expect(parse("-") == nil)
}

// MARK: - Locale sensitivity

/// With three trailing digits and only one separator the input is ambiguous.
/// It resolves by locale: a dot groups in pt_PT, and separates decimals in en_US.
@Test func resolvesAmbiguousSeparatorByLocale() {
    #expect(parse("1.234", pt) == 1234)
    #expect(parse("1.234", en) == 1.234)
    #expect(parse("1,234", pt) == 1.234)
    #expect(parse("1,234", en) == 1234)
}

// MARK: - Display

@Test func formatsWithCommaDecimalAndNoGrouping() {
    #expect(NumberText.string(from: 6285.73, decimals: 2, locale: pt) == "6285,73")
    #expect(NumberText.string(from: 25000, decimals: 0, locale: pt) == "25000")
}

// MARK: - Cents must survive being displayed

/// The reported case: 224,40 typed into the monthly contribution field came
/// back as 224. Parsing was correct; the *display* padded to a fixed zero
/// decimals, and that truncated text reparsed as 224 on the next commit.
@Test func displayNeverTruncatesCents() {
    #expect(NumberText.string(from: 224.4, decimals: 0, locale: pt) == "224,4")
    #expect(NumberText.string(from: 224.4, decimals: 2, locale: pt) == "224,4")
    #expect(NumberText.double(from: "224,40", locale: pt) == 224.4)
}

/// Whole numbers stay clean — no "224,00" padding.
@Test func displayDropsTrailingZeros() {
    #expect(NumberText.string(from: 224, decimals: 2, locale: pt) == "224")
    #expect(NumberText.string(from: 1117, decimals: 2, locale: pt) == "1117")
    #expect(NumberText.string(from: 0, decimals: 2, locale: pt) == "0")
}

/// The full commit cycle a field performs: parse the typed text, render it,
/// then parse that rendering again. Cents must survive both passes at every
/// decimals setting a field might be configured with.
@Test func commitCycleIsStableAtEveryDecimalsSetting() {
    for decimals in [0, 2] {
        for typed in ["224,40", "224,4", "1117,50", "6285,73", "0,05"] {
            let first = NumberText.double(from: typed, locale: pt)
            #expect(first != nil, "'\(typed)' failed to parse")
            let shown = NumberText.string(from: first ?? 0, decimals: decimals, locale: pt)
            let second = NumberText.double(from: shown, locale: pt)
            #expect(second == first,
                    "decimals \(decimals): '\(typed)' -> \(first ?? .nan) -> '\(shown)' -> \(second ?? .nan)")
        }
    }
}

/// Whatever is displayed must parse back to the same number, or committing a
/// field twice would drift.
@Test func displayRoundTripsThroughParsing() {
    for value in [0.0, 0.5, 350.27, 6285.73, 25000, 1234567.89, -50.25] {
        let shown = NumberText.string(from: value, decimals: 2, locale: pt)
        let back = parse(shown)
        #expect(back != nil, "could not re-parse '\(shown)'")
        #expect(abs((back ?? .nan) - value) < 0.000001, "'\(shown)' round-tripped to \(back ?? .nan)")
    }
}
