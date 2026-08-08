import Testing
@testable import Ascend

private let nnbsp = "\u{202F}"

@Test func formatsWholeEurosWithNarrowSpaceSeparator() {
    #expect(Money.currency(3100.40) == "3\(nnbsp)100\(nnbsp)€")
}

@Test func formatsCentsWhenAsked() {
    #expect(Money.currency(1234.56, decimals: 2) == "1\(nnbsp)234,56\(nnbsp)€")
}

@Test func formatsSmallValuesWithoutSeparator() {
    #expect(Money.currency(600) == "600\(nnbsp)€")
}

@Test func formatsNegativeValues() {
    #expect(Money.currency(-50) == "-50\(nnbsp)€")
}

@Test func formatsPercentToOneDecimal() {
    #expect(Money.percent(0.2400) == "24,0\(nnbsp)%")
}

@Test func nilValuesRenderAsEmDash() {
    #expect(Money.currency(nil) == "—")
    #expect(Money.percent(nil) == "—")
}
