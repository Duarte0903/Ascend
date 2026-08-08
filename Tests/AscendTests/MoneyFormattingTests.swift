import Testing
@testable import Ascend

private let nnbsp = "\u{202F}"

@Test func formatsWholeEurosWithNarrowSpaceSeparator() {
    #expect(Money.currency(8409.74) == "8\(nnbsp)410\(nnbsp)€")
}

@Test func formatsCentsWhenAsked() {
    #expect(Money.currency(6285.73, decimals: 2) == "6\(nnbsp)285,73\(nnbsp)€")
}

@Test func formatsSmallValuesWithoutSeparator() {
    #expect(Money.currency(915) == "915\(nnbsp)€")
}

@Test func formatsNegativeValues() {
    #expect(Money.currency(-50) == "-50\(nnbsp)€")
}

@Test func formatsPercentToOneDecimal() {
    #expect(Money.percent(0.1220427) == "12,2\(nnbsp)%")
}

@Test func nilValuesRenderAsEmDash() {
    #expect(Money.currency(nil) == "—")
    #expect(Money.percent(nil) == "—")
}
