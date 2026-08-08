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
