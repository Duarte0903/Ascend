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

@Suite("Rounding to the cent")
struct MoneyCentsTests {
    @Test("A half cent rounds away from zero, as a payslip line does")
    func halfRoundsUp() {
        #expect(Money.cents(2_556.2416) == 2_556.24)
        #expect(Money.cents(2_246.816) == 2_246.82)
        #expect(Money.cents(0.005) == 0.01)
        #expect(Money.cents(-0.005) == -0.01)
        #expect(Money.cents(1.004999) == 1.00)
    }

    @Test("A figure already in cents is returned unchanged")
    func idempotent() {
        for value in [0.0, 1.0, 19_392.72, -450.55, 1_723.53] {
            #expect(Money.cents(value) == value)
            #expect(Money.cents(Money.cents(value)) == Money.cents(value))
        }
    }

    @Test("Nothing that is not a number comes back out")
    func nonFinite() {
        #expect(Money.cents(.nan) == 0)
        #expect(Money.cents(.infinity) == 0)
        #expect(Money.cents(-.infinity) == 0)
    }
}
