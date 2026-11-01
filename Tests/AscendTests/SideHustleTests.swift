import Foundation
import Testing
@testable import Ascend

private let calendar = Calendar(identifier: .gregorian)

private func day(_ d: Int, _ m: Int, _ y: Int) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
}

private func hustle(_ name: String = "Freelance",
                    activity: SideHustleActivity = .professionalServices,
                    contributions: SideHustleContributions = .automatic,
                    amounts: [(Double, Date)]) -> SideHustleInput {
    SideHustleInput(name: name, activity: activity, contributions: contributions,
                    earnings: amounts.map { SideHustleEarningInput(date: $0.1, amount: $0.0) })
}

/// The coefficient is the whole mechanism of the regime simplificado: a share
/// of what is invoiced counts as profit, the rest is treated as the cost of
/// earning it without receipts being asked for.
@Suite("Side hustle, what is taxed")
struct SideHustleCoefficientTests {
    private let rules = SideHustleRules(marginalIRSRate: 0.235, hasEmployment: true)

    @Test("Professional services are taxed on three quarters of the invoice")
    func professionalServices() {
        let a = SideHustleEngine.assess(
            hustle(amounts: [(1_000, day(5, 3, 2026))]), rules: rules, year: 2026,
            calendar: calendar)
        #expect(a.gross == 1_000)
        #expect(a.taxableProfit == 750)
        #expect(a.irs == Money.cents(750 * 0.235))
    }

    @Test("Each kind of work has its own share")
    func everyCoefficient() {
        let expected: [SideHustleActivity: Double] = [
            .professionalServices: 0.75, .otherServices: 0.35,
            .goods: 0.15, .intellectualProperty: 0.95,
        ]
        for (activity, coefficient) in expected {
            #expect(activity.coefficient == coefficient)
            let a = SideHustleEngine.assess(
                hustle(activity: activity, amounts: [(2_000, day(1, 6, 2026))]),
                rules: rules, year: 2026, calendar: calendar)
            #expect(a.taxableProfit == Money.cents(2_000 * coefficient))
        }
    }

    @Test("Nothing invoiced owes nothing")
    func empty() {
        let a = SideHustleEngine.assess(hustle(amounts: []), rules: rules,
                                        year: 2026, calendar: calendar)
        #expect(a.gross == 0)
        #expect(a.totalTax == 0)
        #expect(a.net == 0)
        #expect(a.effectiveRate == 0)
        #expect(a.contributionBasis == .noIncome)
    }

    @Test("Only the year asked for is counted")
    func oneYearAtATime() {
        let subject = hustle(amounts: [(1_000, day(5, 3, 2026)),
                                       (500, day(31, 12, 2025)),
                                       (250, day(1, 1, 2027))])
        #expect(SideHustleEngine.assess(subject, rules: rules, year: 2026,
                                        calendar: calendar).gross == 1_000)
        #expect(SideHustleEngine.assess(subject, rules: rules, year: 2025,
                                        calendar: calendar).gross == 500)
        #expect(SideHustleEngine.years(in: [subject], calendar: calendar)
                == [2027, 2026, 2025])
    }

    @Test("Every figure is whole cents")
    func cents() {
        let a = SideHustleEngine.assess(
            hustle(amounts: [(1_333.33, day(7, 7, 2026)), (99.99, day(8, 8, 2026))]),
            rules: SideHustleRules(marginalIRSRate: 0.2335, hasEmployment: false),
            year: 2026, calendar: calendar)
        for value in [a.gross, a.taxableProfit, a.irs, a.contributionBase,
                      a.contributions, a.totalTax, a.net] {
            #expect(Money.cents(value) == value)
        }
        #expect(a.net == Money.cents(a.gross - a.totalTax))
    }
}

/// An employed person pays nothing further on small side work: the salary is
/// already contributing, and the side income sits under the published ceiling.
@Suite("Side hustle contributions")
struct SideHustleContributionTests {
    private let employed = SideHustleRules(marginalIRSRate: 0.235,
                                           hasEmployment: true,
                                           monthsActive: 12)

    @Test("Below the ceiling, an employed person owes no contributions")
    func exemptBelowCeiling() {
        let a = SideHustleEngine.assess(
            hustle(amounts: [(6_000, day(1, 6, 2026))]), rules: employed,
            year: 2026, calendar: calendar)
        // 70% of 6 000 over twelve months is 350 a month, well under 4 × IAS.
        #expect(a.monthlyRelevantIncome == 350)
        #expect(a.contributionBasis == .exemptBelowCeiling)
        #expect(a.contributions == 0)
    }

    @Test("Above it they are charged, on their own base and rate")
    func chargedAboveCeiling() {
        let a = SideHustleEngine.assess(
            hustle(amounts: [(60_000, day(1, 6, 2026))]), rules: employed,
            year: 2026, calendar: calendar)
        #expect(a.contributionBasis == .charged)
        #expect(a.contributionBase == 42_000)              // 70% of 60 000
        #expect(a.contributions == Money.cents(42_000 * 0.214))
    }

    @Test("Without a salary there is no exemption to claim")
    func noEmploymentMeansCharged() {
        let a = SideHustleEngine.assess(
            hustle(amounts: [(6_000, day(1, 6, 2026))]),
            rules: SideHustleRules(marginalIRSRate: 0.235, hasEmployment: false),
            year: 2026, calendar: calendar)
        #expect(a.contributionBasis == .charged)
        #expect(a.contributions > 0)
    }

    @Test("Fewer months running raises the monthly average it is tested on")
    func monthsActive() {
        let short = SideHustleRules(marginalIRSRate: 0.235, hasEmployment: true,
                                    monthsActive: 2)
        let a = SideHustleEngine.assess(
            hustle(amounts: [(6_000, day(1, 6, 2026))]), rules: short,
            year: 2026, calendar: calendar)
        #expect(a.monthlyRelevantIncome == 2_100)
        // 2 100 is over the 2 090 ceiling, so it tips into being charged.
        #expect(a.contributionBasis == .charged)
    }

    @Test("Selling goods contributes on a fifth, not seven tenths")
    func goodsBase() {
        let a = SideHustleEngine.assess(
            hustle(activity: .goods, amounts: [(10_000, day(1, 6, 2026))]),
            rules: SideHustleRules(marginalIRSRate: 0.235, hasEmployment: false),
            year: 2026, calendar: calendar)
        #expect(a.contributionBase == 2_000)
    }

    @Test("The setting overrides the rules, both ways")
    func overrides() {
        let small: [(Double, Date)] = [(6_000, day(1, 6, 2026))]
        let forced = SideHustleEngine.assess(
            hustle(contributions: .charged, amounts: small), rules: employed,
            year: 2026, calendar: calendar)
        #expect(forced.contributionBasis == .chargedBySetting)
        #expect(forced.contributions > 0)

        let big: [(Double, Date)] = [(60_000, day(1, 6, 2026))]
        let waived = SideHustleEngine.assess(
            hustle(contributions: .exempt, amounts: big), rules: employed,
            year: 2026, calendar: calendar)
        #expect(waived.contributionBasis == .exemptBySetting)
        #expect(waived.contributions == 0)
    }

    @Test("The ceiling is four times the social support index")
    func ceiling() {
        #expect(employed.exemptionCeiling == Money.cents(522.50 * 4))
    }
}

/// Several hustles in one year add up, and only the active ones count.
@Suite("Side hustle year")
struct SideHustleYearTests {
    private let rules = SideHustleRules(marginalIRSRate: 0.235, hasEmployment: true)

    @Test("The totals are the parts, to the cent")
    func totals() {
        let year = SideHustleYear.compute(
            [hustle("Writing", amounts: [(1_000, day(5, 3, 2026))]),
             hustle("Prints", activity: .goods, amounts: [(500, day(9, 9, 2026))])],
            rules: rules, year: 2026, calendar: calendar)

        #expect(year.hustles.count == 2)
        #expect(year.gross == 1_500)
        #expect(year.irs == Money.cents(year.hustles.reduce(0) { $0 + $1.irs }))
        #expect(year.totalTax == Money.cents(year.irs + year.contributions))
        #expect(year.net == Money.cents(year.gross - year.totalTax))
    }

    @Test("An archived hustle is left out entirely")
    func archivedIsIgnored() {
        var retired = hustle("Old", amounts: [(9_000, day(5, 3, 2026))])
        retired.isArchived = true
        let year = SideHustleYear.compute(
            [hustle("Current", amounts: [(1_000, day(5, 3, 2026))]), retired],
            rules: rules, year: 2026, calendar: calendar)
        #expect(year.hustles.count == 1)
        #expect(year.gross == 1_000)
    }

    @Test("Nothing at all is a quiet zero, not a divide by zero")
    func nothing() {
        let year = SideHustleYear.compute([], rules: rules, year: 2026,
                                          calendar: calendar)
        #expect(year.gross == 0)
        #expect(year.effectiveRate == 0)
        #expect(year.hustles.isEmpty)
    }
}

/// The IRS rate side work meets is the one the salary already reached, which
/// is why the two screens share a figure rather than asking twice.
@Suite("Side hustle meets the salary's rate")
struct SideHustleRateTests {
    @Test("The marginal rate for side work leaves out employee contributions")
    func irsOnlyMarginalRate() {
        let assessment = TaxEngine.assess(
            TaxInput(grossAnnual: 40_000, withholdingAtSource: true))
        #expect(assessment.marginalIRSRate < assessment.marginalRate)
        #expect(abs((assessment.marginalRate - assessment.marginalIRSRate) - 0.11) < 0.000_1)
    }

    @Test("A higher salary makes the same side work cost more")
    func stacksOnSalary() {
        func irs(onSalary salary: Double) -> Double {
            let rate = TaxEngine.assess(
                TaxInput(grossAnnual: salary, withholdingAtSource: true)).marginalIRSRate
            return SideHustleEngine.assess(
                hustle(amounts: [(5_000, day(5, 3, 2026))]),
                rules: SideHustleRules(marginalIRSRate: rate, hasEmployment: true),
                year: 2026, calendar: calendar).irs
        }
        #expect(irs(onSalary: 60_000) > irs(onSalary: 20_000))
    }
}

/// Article 12.º-B exempts income from categories A and B alike, with one cap
/// of 55 × IAS across both. Side work is covered on the same terms as the
/// salary, and what the salary has already used is gone before it is reached.
@Suite("IRS Jovem reaches side work too")
struct SideHustleYoungTaxpayerTests {
    private func rules(share: Double, remaining: Double) -> SideHustleRules {
        SideHustleRules(marginalIRSRate: 0.235, hasEmployment: true,
                        youngExemptionShare: share,
                        youngExemptionRemaining: remaining)
    }

    @Test("A full exemption leaves no IRS on the profit at all")
    func fullExemption() {
        let a = SideHustleEngine.assess(
            hustle(amounts: [(4_000, day(5, 3, 2026))]),
            rules: rules(share: 1, remaining: 28_737.50), year: 2026,
            calendar: calendar)
        #expect(a.taxableProfit == 3_000)
        #expect(a.youngExemption == 3_000)
        #expect(a.taxedProfit == 0)
        #expect(a.irs == 0)
    }

    @Test("A partial one taxes only what is left")
    func partialExemption() {
        let a = SideHustleEngine.assess(
            hustle(amounts: [(4_000, day(5, 3, 2026))]),
            rules: rules(share: 0.5, remaining: 28_737.50), year: 2026,
            calendar: calendar)
        #expect(a.youngExemption == 1_500)
        #expect(a.taxedProfit == 1_500)
        #expect(a.irs == Money.cents(1_500 * 0.235))
    }

    @Test("Nothing left of the cap means nothing exempt")
    func capExhausted() {
        let a = SideHustleEngine.assess(
            hustle(amounts: [(4_000, day(5, 3, 2026))]),
            rules: rules(share: 1, remaining: 0), year: 2026, calendar: calendar)
        #expect(a.youngExemption == 0)
        #expect(a.irs == Money.cents(3_000 * 0.235))
    }

    @Test("What is left of the cap caps it")
    func partialCap() {
        let a = SideHustleEngine.assess(
            hustle(amounts: [(4_000, day(5, 3, 2026))]),
            rules: rules(share: 1, remaining: 1_000), year: 2026, calendar: calendar)
        #expect(a.youngExemption == 1_000)
        #expect(a.taxedProfit == 2_000)
    }

    @Test("Several hustles share one allowance, not one each")
    func sharedAcrossHustles() {
        let year = SideHustleYear.compute(
            [hustle("First", amounts: [(4_000, day(5, 3, 2026))]),
             hustle("Second", amounts: [(4_000, day(6, 4, 2026))])],
            rules: rules(share: 1, remaining: 4_000), year: 2026, calendar: calendar)

        // 3 000 of profit each; the allowance covers the first and 1 000 of
        // the second, never 3 000 twice.
        #expect(year.youngExemption == 4_000)
        #expect(year.hustles[0].youngExemption == 3_000)
        #expect(year.hustles[1].youngExemption == 1_000)
        #expect(year.irs == Money.cents(2_000 * 0.235))
    }

    @Test("With no scheme running nothing is exempt")
    func noScheme() {
        let a = SideHustleEngine.assess(
            hustle(amounts: [(4_000, day(5, 3, 2026))]),
            rules: SideHustleRules(marginalIRSRate: 0.235, hasEmployment: true),
            year: 2026, calendar: calendar)
        #expect(a.youngExemption == 0)
        #expect(a.taxedProfit == a.taxableProfit)
    }

    @Test("Contributions are untouched by it — a different levy entirely")
    func contributionsUnaffected() {
        let exempt = SideHustleEngine.assess(
            hustle(amounts: [(60_000, day(5, 3, 2026))]),
            rules: rules(share: 1, remaining: 28_737.50), year: 2026,
            calendar: calendar)
        let taxed = SideHustleEngine.assess(
            hustle(amounts: [(60_000, day(5, 3, 2026))]),
            rules: rules(share: 0, remaining: 0), year: 2026, calendar: calendar)
        #expect(exempt.contributions == taxed.contributions)
        #expect(exempt.irs < taxed.irs)
    }
}

/// Categoria B is taxed when the money arrives, not when it is billed, so an
/// invoice still waiting owes nothing yet.
@Suite("Unpaid invoices are not taxed")
struct SideHustleUnpaidTests {
    private let rules = SideHustleRules(marginalIRSRate: 0.235, hasEmployment: true)

    private func mixed() -> SideHustleInput {
        SideHustleInput(name: "Freelance", earnings: [
            SideHustleEarningInput(date: day(5, 3, 2026), amount: 1_000, isPaid: true),
            SideHustleEarningInput(date: day(9, 9, 2026), amount: 400, isPaid: false),
        ])
    }

    @Test("Only what arrived is taxed; the rest is simply owed")
    func onlyPaidIsTaxed() {
        let a = SideHustleEngine.assess(mixed(), rules: rules, year: 2026,
                                        calendar: calendar)
        #expect(a.gross == 1_000)
        #expect(a.outstanding == 400)
        #expect(a.invoiced == 1_400)
        #expect(a.taxableProfit == 750)
        #expect(a.net == Money.cents(1_000 - a.totalTax))
    }

    @Test("Marking it paid brings it into the tax")
    func markingPaid() {
        var subject = mixed()
        let waiting = SideHustleEngine.assess(subject, rules: rules, year: 2026,
                                              calendar: calendar)
        subject.earnings = subject.earnings.map {
            var copy = $0; copy.isPaid = true; return copy
        }
        let settled = SideHustleEngine.assess(subject, rules: rules, year: 2026,
                                              calendar: calendar)
        #expect(settled.gross == 1_400)
        #expect(settled.outstanding == 0)
        #expect(settled.irs > waiting.irs)
    }

    @Test("Nothing paid owes nothing, however much is outstanding")
    func allUnpaid() {
        var subject = mixed()
        subject.earnings = subject.earnings.map {
            var copy = $0; copy.isPaid = false; return copy
        }
        let a = SideHustleEngine.assess(subject, rules: rules, year: 2026,
                                        calendar: calendar)
        #expect(a.gross == 0)
        #expect(a.outstanding == 1_400)
        #expect(a.totalTax == 0)
        #expect(a.contributionBasis == .noIncome)
    }

    @Test("The year's totals keep the two apart")
    func yearTotals() {
        let year = SideHustleYear.compute([mixed()], rules: rules, year: 2026,
                                          calendar: calendar)
        #expect(year.gross == 1_000)
        #expect(year.outstanding == 400)
        #expect(year.invoiced == 1_400)
        #expect(year.effectiveRate == year.totalTax / 1_000)
    }

    @Test("An earning recorded before this existed counts as received")
    func defaultsToPaid() {
        #expect(SideHustleEarningInput(date: day(1, 1, 2026), amount: 100).isPaid)
    }
}
