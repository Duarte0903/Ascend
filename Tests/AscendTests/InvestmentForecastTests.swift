import Foundation
import SwiftData
import Testing
@testable import Ascend

@Suite("Projecting one holding")
struct InvestmentForecastTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func holding(value: Double, rate: Double, contribution: Double = 0,
                         interest: Date? = nil,
                         every frequency: InterestFrequency = .annual) -> InvestmentHolding {
        InvestmentHolding(accountID: UUID(), name: "XTB", colorHex: "#1F6E8C",
                          invested: value, value: value,
                          trackedSince: nil, years: nil,
                          expectedAnnualReturn: rate,
                          monthlyContribution: contribution,
                          interestDate: interest,
                          interestFrequency: interest == nil ? .none : frequency)
    }

    // MARK: - Compounding

    @Test("A year of growth compounds to the annual rate")
    func oneYearMatchesTheRate() {
        let subject = holding(value: 1_000, rate: 0.12)
        // Twelve monthly steps of the twelfth root come back to 12%.
        #expect(abs(subject.projectedValue(months: 12) - 1_120) < 0.01)
    }

    @Test("Growth compounds rather than adding up")
    func growthCompounds() {
        let subject = holding(value: 1_000, rate: 0.10)
        let twoYears = subject.projectedValue(months: 24)
        #expect(twoYears > 1_200)                       // more than 10% twice
        #expect(abs(twoYears - 1_210) < 0.01)           // exactly 1,10²
    }

    @Test("Contributions are added every month and compound after that")
    func contributionsCompound() {
        let plain = holding(value: 1_000, rate: 0.12)
        let saving = holding(value: 1_000, rate: 0.12, contribution: 100)
        let added = saving.projectedValue(months: 12) - plain.projectedValue(months: 12)
        // Twelve payments of 100, worth more than 1 200 because the early ones
        // have been growing.
        #expect(added > 1_200)
        #expect(added < 1_300)
    }

    @Test("Projecting no months is just today's value")
    func zeroMonths() {
        let subject = holding(value: 1_000, rate: 0.12)
        #expect(subject.projectedValue(months: 0) == 1_000)
        #expect(subject.projectedValue(months: -5) == 1_000)
    }

    @Test("An account with no expected return keeps its contributions only")
    func noReturn() {
        let subject = holding(value: 500, rate: 0, contribution: 50)
        #expect(abs(subject.projectedValue(months: 12) - 1_100) < 0.000_1)
    }

    @Test("A negative expected return shrinks the balance")
    func negativeReturn() {
        let subject = holding(value: 1_000, rate: -0.10)
        #expect(subject.projectedValue(months: 12) < 1_000)
    }

    // MARK: - The interest date

    private func day(_ d: Int, _ m: Int, _ y: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test("The next payment is the anchor itself when it is still ahead")
    func anchorInTheFuture() {
        let subject = holding(value: 1_000, rate: 0.03, interest: day(15, 12, 2026))
        let next = subject.nextInterest(after: day(20, 8, 2026), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: next!)
                == DateComponents(year: 2026, month: 12, day: 15))
    }

    @Test("A quarterly account pays four times a year, not once")
    func quarterlyStepsByThreeMonths() {
        // Anchored in January: April, July, October, then next January.
        let subject = holding(value: 1_000, rate: 0.04,
                              interest: day(15, 1, 2026), every: .quarterly)
        let next = subject.nextInterest(after: day(20, 8, 2026), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: next!)
                == DateComponents(year: 2026, month: 10, day: 15))
    }

    @Test("A monthly account pays next month, not next year")
    func monthlySteps() {
        let subject = holding(value: 1_000, rate: 0.03,
                              interest: day(5, 1, 2026), every: .monthly)
        let next = subject.nextInterest(after: day(20, 8, 2026), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: next!)
                == DateComponents(year: 2026, month: 9, day: 5))
    }

    @Test("Every six months lands on the half-year from the anchor")
    func semiannualSteps() {
        let subject = holding(value: 1_000, rate: 0.03,
                              interest: day(1, 3, 2026), every: .semiannual)
        let next = subject.nextInterest(after: day(20, 8, 2026), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: next!)
                == DateComponents(year: 2026, month: 9, day: 1))
    }

    @Test("An anchor years in the past still lands on a real payment")
    func oldAnchorCatchesUp() {
        let subject = holding(value: 1_000, rate: 0.03,
                              interest: day(15, 3, 1998), every: .quarterly)
        let next = subject.nextInterest(after: day(20, 8, 2026), calendar: calendar)!
        #expect(next >= day(20, 8, 2026))
        // Still on the anchor's day, and a whole number of quarters along.
        // Measured from the start of the anchor's day: the result is a midnight,
        // so comparing against a midday anchor would lose a day and a month.
        #expect(calendar.component(.day, from: next) == 15)
        let months = calendar.dateComponents(
            [.month], from: calendar.startOfDay(for: day(15, 3, 1998)), to: next).month!
        #expect(months % 3 == 0)
    }

    @Test("A payment due today is today's, not the next one along")
    func dueTodayCountsAsNext() {
        let subject = holding(value: 1_000, rate: 0.03,
                              interest: day(20, 8, 2026), every: .monthly)
        let next = subject.nextInterest(after: day(20, 8, 2026), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: next!)
                == DateComponents(year: 2026, month: 8, day: 20))
    }

    @Test("With no schedule there is no next payment, whatever the date says")
    func noScheduleNoPayment() {
        let subject = holding(value: 1_000, rate: 0.03,
                              interest: day(15, 3, 2026), every: .none)
        #expect(subject.nextInterest(after: day(20, 8, 2026), calendar: calendar) == nil)
        #expect(subject.expectedInterestPerPayment == nil)
    }

    @Test("No date means no next payment and no expected interest")
    func noDate() {
        let subject = holding(value: 1_000, rate: 0.03)
        #expect(subject.nextInterest(after: day(20, 8, 2026), calendar: calendar) == nil)
        #expect(subject.expectedInterestPerPayment == nil)
    }

    @Test("The annual rate is split across the payments, not applied to each")
    func interestIsPerPayment() {
        let annual = holding(value: 1_200, rate: 0.10,
                             interest: day(15, 3, 2026), every: .annual)
        let monthly = holding(value: 1_200, rate: 0.10,
                              interest: day(15, 3, 2026), every: .monthly)
        // A year's payment is the whole rate; a month's is nowhere near it.
        #expect(abs(annual.expectedInterestPerPayment! - 120) < 0.000_1)
        #expect(monthly.expectedInterestPerPayment! < 10)
        #expect(monthly.expectedInterestPerPayment! > 9)
    }

    @Test("A year's payments compound back to exactly the expected return")
    func paymentsCompoundToTheYear() {
        for frequency in InterestFrequency.presets where frequency.isScheduled {
            let subject = holding(value: 1_200, rate: 0.10,
                                  interest: day(15, 3, 2026), every: frequency)
            let perPaymentRate = subject.expectedInterestPerPayment! / 1_200
            let compounded = pow(1 + perPaymentRate, frequency.timesPerYear) - 1
            #expect(abs(compounded - 0.10) < 0.000_001)
        }
    }

    @Test("The interest column agrees with the projection beside it")
    func agreesWithTheProjection() {
        // One month of the projection is one monthly payment: the two figures
        // sit on the same row and must be the same arithmetic.
        let subject = holding(value: 1_200, rate: 0.10,
                              interest: day(15, 3, 2026), every: .monthly)
        let growth = subject.projectedValue(months: 1) - subject.value
        #expect(abs(growth - subject.expectedInterestPerPayment!) < 0.000_1)
    }

    @Test("With no return, or nothing in it, there is no interest to expect")
    func noInterestWithoutReturnOrBalance() {
        #expect(holding(value: 1_000, rate: 0, interest: day(15, 3, 2026))
            .expectedInterestPerPayment == nil)
        #expect(holding(value: 0, rate: 0.03, interest: day(15, 3, 2026))
            .expectedInterestPerPayment == nil)
    }
}

@MainActor
@Suite("Custom interest schedules")
struct CustomInterestScheduleTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ d: Int, _ m: Int, _ y: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func holding(every frequency: InterestFrequency,
                         anchor: Date, value: Double = 1_200,
                         rate: Double = 0.12) -> InvestmentHolding {
        InvestmentHolding(accountID: UUID(), name: "Bond", colorHex: "#1F6E8C",
                          invested: value, value: value, trackedSince: nil, years: nil,
                          expectedAnnualReturn: rate, monthlyContribution: 0,
                          interestDate: anchor, interestFrequency: frequency)
    }

    @Test("An interval the presets don't cover still walks correctly")
    func twoMonthlySchedule() {
        // Anchored in January, every two months: March, May, July, September.
        let subject = holding(every: .everyMonths(2), anchor: day(10, 1, 2026))
        let next = subject.nextInterest(after: day(20, 8, 2026), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: next!)
                == DateComponents(year: 2026, month: 9, day: 10))
    }

    @Test("An interval longer than a year works too")
    func eighteenMonthSchedule() {
        let subject = holding(every: .everyMonths(18), anchor: day(1, 1, 2026))
        let next = subject.nextInterest(after: day(20, 8, 2026), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month], from: next!)
                == DateComponents(year: 2027, month: 7))
    }

    @Test("Payments per year follow the interval")
    func amountFollowsTheInterval() {
        // Every two months is six payments a year, each a sixth root of 12%.
        let subject = holding(every: .everyMonths(2), anchor: day(1, 1, 2026))
        #expect(abs(subject.interestFrequency.timesPerYear - 6) < 0.000_1)
        let expected = 1_200 * (pow(1.12, 1.0 / 6.0) - 1)
        #expect(abs(subject.expectedInterestPerPayment! - expected) < 0.000_1)
        // Six of them is less than a flat sixth of the year's 144.
        #expect(subject.expectedInterestPerPayment! < 24)
    }

    @Test("A custom interval matching a preset is stored as that preset")
    func customCollapsesOntoPresets() {
        #expect(InterestFrequency.normalised(.everyMonths(1)) == .monthly)
        #expect(InterestFrequency.normalised(.everyMonths(3)) == .quarterly)
        #expect(InterestFrequency.normalised(.everyMonths(6)) == .semiannual)
        #expect(InterestFrequency.normalised(.everyMonths(12)) == .annual)
        // Anything else stays as it was written.
        #expect(InterestFrequency.normalised(.everyMonths(2)) == .everyMonths(2))
    }

    @Test("An out-of-range interval is clamped rather than stored")
    func clampsAbsurdIntervals() {
        #expect(InterestFrequency.normalised(.everyMonths(0)) == .monthly)
        #expect(InterestFrequency.normalised(.everyMonths(-4)) == .monthly)
        #expect(InterestFrequency.normalised(.everyMonths(9_999)) == .everyMonths(120))
    }

    @Test("A custom interval survives being stored and read back")
    func roundTrips() {
        #expect(InterestFrequency.everyMonths(2).rawValue == "every2")
        #expect(InterestFrequency(rawValue: "every2") == .everyMonths(2))
        // And a preset spelled the long way comes back as the preset.
        #expect(InterestFrequency(rawValue: "every3") == .quarterly)
        #expect(InterestFrequency(rawValue: "nonsense") == nil)
    }

    @Test("The five original stored values still read")
    func presetsStillLoad() {
        for preset in InterestFrequency.presets {
            #expect(InterestFrequency(rawValue: preset.rawValue) == preset)
        }
    }

    @Test("Setting a schedule on an account stores its simplest form")
    func serviceNormalises() throws {
        let context = try inMemoryContext()
        let account = Account(name: "Bond", colorHex: "#1F6E8C", sortOrder: 0,
                              includeInUsable: true, countsAsSavings: true)
        context.insert(account)
        try context.save()

        AccountService.setInterestSchedule(.everyMonths(3), on: account, in: context)
        #expect(account.interestFrequency == .quarterly)
        #expect(account.interestDate != nil)

        AccountService.setInterestSchedule(.everyMonths(2), on: account, in: context)
        #expect(account.interestFrequency == .everyMonths(2))

        AccountService.setInterestSchedule(.none, on: account, in: context)
        #expect(account.interestDate == nil)
    }

    @Test("Every interval's payments compound back to the expected return")
    func paymentsCompound() {
        for months in [1, 2, 4, 5, 6, 12, 18] {
            let subject = holding(every: .everyMonths(months), anchor: day(1, 1, 2026))
            let perPaymentRate = subject.expectedInterestPerPayment! / 1_200
            let compounded = pow(1 + perPaymentRate,
                                 subject.interestFrequency.timesPerYear) - 1
            #expect(abs(compounded - 0.12) < 0.000_001)
        }
    }
}

@MainActor
@Suite("When a new schedule starts")
struct InterestScheduleStartTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ d: Int, _ m: Int, _ y: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func account(in context: ModelContext) -> Account {
        let account = Account(name: "Savings", colorHex: "#1F6E8C", sortOrder: 0,
                              includeInUsable: true, countsAsSavings: true,
                              expectedAnnualReturn: 0.03)
        context.insert(account)
        return account
    }

    @Test("A new schedule starts next month, not today")
    func startsNextMonth() throws {
        let context = try inMemoryContext()
        let subject = account(in: context)

        AccountService.setInterestSchedule(.monthly, on: subject, in: context,
                                           now: day(20, 8, 2026), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: subject.interestDate!)
                == DateComponents(year: 2026, month: 9, day: 1))
    }

    @Test("Set in December, it starts in January")
    func rollsIntoTheNewYear() throws {
        let context = try inMemoryContext()
        let subject = account(in: context)

        AccountService.setInterestSchedule(.monthly, on: subject, in: context,
                                           now: day(28, 12, 2026), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: subject.interestDate!)
                == DateComponents(year: 2027, month: 1, day: 1))
    }

    @Test("The next payment is never the day the schedule was created")
    func neverDueOnCreation() throws {
        let context = try inMemoryContext()
        let today = day(20, 8, 2026)
        for frequency in InterestFrequency.presets where frequency.isScheduled {
            let subject = account(in: context)
            AccountService.setInterestSchedule(frequency, on: subject, in: context,
                                               now: today, calendar: calendar)
            #expect(subject.interestDate! > today)
        }
    }

    @Test("Changing the day moves it within the same cycle")
    func dayMovesWithinTheMonth() throws {
        let context = try inMemoryContext()
        let subject = account(in: context)
        AccountService.setInterestSchedule(.monthly, on: subject, in: context,
                                           now: day(20, 8, 2026), calendar: calendar)

        AccountService.setInterestDay(15, on: subject, in: context,
                                      now: day(20, 8, 2026), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: subject.interestDate!)
                == DateComponents(year: 2026, month: 9, day: 15))
        #expect(AccountService.interestDay(of: subject, calendar: calendar) == 15)
    }

    @Test("A day already gone this month lands next month")
    func neverLeavesTheAnchorBehind() throws {
        let context = try inMemoryContext()
        let subject = account(in: context)
        subject.interestFrequency = .monthly
        subject.interestDate = day(1, 9, 2026)

        // The 5th has passed by the 20th, so the next one is October's.
        AccountService.setInterestDay(5, on: subject, in: context,
                                      now: day(20, 9, 2026), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: subject.interestDate!)
                == DateComponents(year: 2026, month: 10, day: 5))
    }

    @Test("The 31st resolves in a month that has no 31st")
    func clampsToShortMonths() throws {
        let context = try inMemoryContext()
        let subject = account(in: context)
        subject.interestFrequency = .monthly
        subject.interestDate = day(1, 2, 2027)

        // Asking for the 31st in February lands on the 28th, not in March.
        AccountService.setInterestDay(31, on: subject, in: context,
                                      now: day(5, 2, 2027), calendar: calendar)
        #expect(calendar.component(.month, from: subject.interestDate!) == 2)
        #expect(calendar.component(.day, from: subject.interestDate!) == 28)
    }

    @Test("The day chosen decides the date, not the month it was set up in")
    func dayDecidesTheDate() throws {
        let context = try inMemoryContext()
        let subject = account(in: context)
        // Created on 2 September, so the schedule is anchored to 1 October.
        AccountService.setInterestSchedule(.monthly, on: subject, in: context,
                                           now: day(2, 9, 2026), calendar: calendar)
        #expect(calendar.component(.month, from: subject.interestDate!) == 10)

        // Choosing the 15th gives *this* month's 15th, which is still ahead.
        AccountService.setInterestDay(15, on: subject, in: context,
                                      now: day(2, 9, 2026), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: subject.interestDate!)
                == DateComponents(year: 2026, month: 9, day: 15))
    }

    @Test("A day already past this month rolls to the next")
    func pastDayRollsForward() throws {
        let context = try inMemoryContext()
        let subject = account(in: context)
        subject.interestFrequency = .monthly
        subject.interestDate = day(1, 10, 2026)

        AccountService.setInterestDay(1, on: subject, in: context,
                                      now: day(2, 9, 2026), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: subject.interestDate!)
                == DateComponents(year: 2026, month: 10, day: 1))
    }

    @Test("Today's own day is never the next payment")
    func todayIsNeverNext() throws {
        let context = try inMemoryContext()
        let subject = account(in: context)
        subject.interestFrequency = .monthly
        subject.interestDate = day(1, 10, 2026)

        AccountService.setInterestDay(2, on: subject, in: context,
                                      now: day(2, 9, 2026), calendar: calendar)
        #expect(subject.interestDate! > day(2, 9, 2026))
        #expect(calendar.component(.month, from: subject.interestDate!) == 10)
    }

    @Test("Clearing the schedule clears the date with it")
    func clearingClearsTheDate() throws {
        let context = try inMemoryContext()
        let subject = account(in: context)
        AccountService.setInterestSchedule(.quarterly, on: subject, in: context,
                                           now: day(20, 8, 2026), calendar: calendar)
        #expect(subject.interestDate != nil)

        AccountService.setInterestSchedule(.none, on: subject, in: context,
                                           now: day(20, 8, 2026), calendar: calendar)
        #expect(subject.interestDate == nil)
    }
}

@Suite("How schedules are named")
struct InterestFrequencyLabelTests {

    @Test("Every schedule is named by its interval, so no name needs translating")
    func labelledByInterval() {
        #expect(InterestFrequency.none.label == "No set schedule")
        #expect(InterestFrequency.monthly.label == "Every month")
        #expect(InterestFrequency.quarterly.label == "Every 3 months")
        #expect(InterestFrequency.semiannual.label == "Every 6 months")
        #expect(InterestFrequency.annual.label == "Every 12 months")
        #expect(InterestFrequency.everyMonths(4).label == "Every 4 months")
    }

    @Test("A preset and the custom interval meaning the same thing read the same")
    func presetAndCustomAgree() {
        for preset in InterestFrequency.presets where preset.isScheduled {
            let months = preset.monthsBetween!
            #expect(InterestFrequency.everyMonths(months).label == preset.label)
        }
    }

    @Test("No two options in the list read alike")
    func labelsAreDistinct() {
        let labels = InterestFrequency.presets.map(\.label)
        #expect(Set(labels).count == labels.count)
    }
}

@Suite("Return separated from what you pay in")
struct InvestmentGrowthTests {

    private func holding(value: Double, rate: Double,
                         contribution: Double) -> InvestmentHolding {
        InvestmentHolding(accountID: UUID(), name: "Savings", colorHex: "#1F6E8C",
                          invested: value, value: value, trackedSince: nil, years: nil,
                          expectedAnnualReturn: rate, monthlyContribution: contribution)
    }

    @Test("Two accounts on the same rate earn in proportion to their balance")
    func sameRateComparableGrowth() {
        // The confusion this exists to prevent: one account is paid into, the
        // other is not, and the projected values look nothing alike.
        let bank = holding(value: 5_000, rate: 0.03, contribution: 0)
        let broker = holding(value: 457.34, rate: 0.03, contribution: 100)

        // The projection nearly quadruples the account that is paid into and
        // barely moves the one that is not, though both earn the same rate.
        let brokerMultiple = broker.projectedValue(months: 12) / broker.value
        let bankMultiple = bank.projectedValue(months: 12) / bank.value
        #expect(brokerMultiple > bankMultiple * 3)

        // On what is actually earned, the bigger balance plainly wins.
        #expect(bank.growth(overMonths: 12) > broker.growth(overMonths: 12) * 4)
        #expect(abs(bank.growth(overMonths: 12) - 150) < 0.01)
    }

    @Test("Growth is the projection less what you started with and paid in")
    func growthReconciles() {
        let subject = holding(value: 457.34, rate: 0.03, contribution: 100)
        for months in [1, 12, 60] {
            let expected = subject.projectedValue(months: months)
                - subject.value - subject.contributions(overMonths: months)
            #expect(abs(subject.growth(overMonths: months) - expected) < 0.000_1)
        }
    }

    @Test("With nothing paid in, growth is the whole increase")
    func noContributions() {
        let subject = holding(value: 5_000, rate: 0.03, contribution: 0)
        #expect(subject.contributions(overMonths: 60) == 0)
        #expect(abs(subject.growth(overMonths: 60)
                    - (subject.projectedValue(months: 60) - 5_000)) < 0.000_1)
    }

    @Test("With no return, nothing is earned however much is paid in")
    func noReturnNoGrowth() {
        let subject = holding(value: 1_000, rate: 0, contribution: 250)
        #expect(abs(subject.growth(overMonths: 12)) < 0.000_1)
        #expect(subject.contributions(overMonths: 12) == 3_000)
        #expect(abs(subject.projectedValue(months: 12) - 4_000) < 0.000_1)
    }

    @Test("Contributions are what you pay in, not what they grow into")
    func contributionsAreNotGrowth() {
        let subject = holding(value: 0, rate: 0.12, contribution: 100)
        #expect(subject.contributions(overMonths: 12) == 1_200)
        // The payments earn something on top, which is growth, not contribution.
        #expect(subject.growth(overMonths: 12) > 0)
        #expect(subject.projectedValue(months: 12) > 1_200)
    }

    @Test("Over no time at all, nothing is paid in and nothing earned")
    func zeroMonths() {
        let subject = holding(value: 1_000, rate: 0.12, contribution: 100)
        #expect(subject.contributions(overMonths: 0) == 0)
        #expect(subject.growth(overMonths: 0) == 0)
    }
}

@Suite("Tax on interest")
struct InvestmentTaxTests {

    private func holding(rate: Double = 0.03, tax: Double,
                         every frequency: InterestFrequency = .monthly,
                         value: Double = 1_000,
                         contribution: Double = 0) -> InvestmentHolding {
        InvestmentHolding(accountID: UUID(), name: "Savings", colorHex: "#1F6E8C",
                          invested: value, value: value, trackedSince: nil, years: nil,
                          expectedAnnualReturn: rate, monthlyContribution: contribution,
                          interestDate: frequency.isScheduled ? Date() : nil,
                          interestFrequency: frequency,
                          interestTaxRate: tax)
    }

    @Test("Interest is credited net of tax")
    func paymentIsNet() {
        let subject = holding(tax: 0.28)
        let gross = subject.expectedInterestPerPayment!
        #expect(abs(subject.netInterestPerPayment! - gross * 0.72) < 0.000_1)
    }

    @Test("Tax slows the compounding, not just the payment")
    func taxReducesGrowth() {
        let taxed = holding(tax: 0.28)
        let untaxed = holding(tax: 0)
        #expect(taxed.growth(overMonths: 60) < untaxed.growth(overMonths: 60))

        // Each month's interest is taxed and the remainder compounds, so a
        // year comes to slightly under the rate times what is left after tax.
        let netMonthly = 1 + (pow(1.03, 1.0 / 12.0) - 1) * 0.72
        #expect(abs(taxed.growth(overMonths: 12) - 1_000 * (pow(netMonthly, 12) - 1))
                < 0.000_1)
        #expect(taxed.growth(overMonths: 12) < 1_000 * 0.03 * 0.72)
    }

    @Test("An account with no schedule is not taxed year by year")
    func unscheduledIsUntaxed() {
        // Gains taxed only on sale: the app does not know the sale date, so
        // charging annually would invent a bill.
        let broker = holding(rate: 0.12, tax: 0.28, every: .none)
        let untaxed = holding(rate: 0.12, tax: 0, every: .none)
        #expect(broker.appliedTaxRate == 0)
        #expect(abs(broker.growth(overMonths: 60)
                    - untaxed.growth(overMonths: 60)) < 0.000_1)
    }

    @Test("Zero tax leaves every figure as it was")
    func zeroTaxChangesNothing() {
        let subject = holding(tax: 0)
        #expect(subject.netInterestPerPayment == subject.expectedInterestPerPayment)
        #expect(abs(subject.growth(overMonths: 12) - 1_000 * 0.03) < 0.01)
    }

    @Test("Taxing everything leaves nothing to compound")
    func fullTaxStopsGrowth() {
        let subject = holding(tax: 1.0)
        #expect(subject.netInterestPerPayment == 0)
        #expect(abs(subject.growth(overMonths: 60)) < 0.000_1)
    }

    @Test("An absurd rate is clamped rather than reversing the growth")
    func rateIsClamped() {
        #expect(holding(tax: 5).appliedTaxRate == 1)
        #expect(holding(tax: -1).appliedTaxRate == 0)
        #expect(holding(tax: -1).growth(overMonths: 12) > 0)
    }

    @Test("Contributions are untouched — tax falls on what is earned")
    func contributionsAreNotTaxed() {
        let subject = holding(tax: 0.28, contribution: 100)
        #expect(subject.contributions(overMonths: 12) == 1_200)
        #expect(subject.projectedValue(months: 12) > 1_200)
    }
}
