import SwiftUI

/// Plain-language definitions for every figure on the Tax screen.
///
/// The screen is dense with terms that are either Portuguese law or accounting
/// jargon, and several of them mean something different from what they sound
/// like. This is the one place that says so outright.
struct TaxGlossary: View {
    @Binding var isPresented: Bool

    private struct Entry: Identifiable {
        let term: String
        let meaning: String
        var id: String { term }
    }

    private struct Group: Identifiable {
        let title: String
        let entries: [Entry]
        var id: String { title }
    }

    private let groups: [Group] = [
        Group(title: "What you are paid", entries: [
            Entry(term: "Gross pay a year",
                  meaning: "Everything your contract pays across a year, before anything is taken, with the food allowance included. The salary the tax runs on is this figure less the allowance."),
            Entry(term: "Food allowance",
                  meaning: "Subsídio de alimentação. Paid for each day worked, and exempt up to a daily limit — higher on a card than in cash. Only the part above the limit counts as salary."),
            Entry(term: "Days paid",
                  meaning: "Weekdays in the year, less national holidays that fall on a weekday, less your vacation and any municipal holiday. Holidays landing at the weekend cost you nothing."),
            Entry(term: "Per salary payment",
                  meaning: "What one of the year's payments is worth. Monthly figures spread the year over twelve instead, so they differ whenever you are paid more than twelve times."),
        ]),
        Group(title: "What is taken", entries: [
            Entry(term: "Social security",
                  meaning: "Segurança Social: 11% of salary, taken before tax. Charged whatever relief applies — IRS Jovem does not touch it."),
            Entry(term: "IRS",
                  meaning: "Portuguese income tax, charged on a rising scale of bands once every deduction and relief has been applied."),
            Entry(term: "Withholding",
                  meaning: "Retenção na fonte: a monthly instalment your employer holds back against the year's tax. It is not the tax — the difference is settled when you file."),
            Entry(term: "Tax due",
                  meaning: "What the year actually costs, worked out from your whole year's income. This is the figure your annual return arrives at."),
            Entry(term: "Refund, or still to pay",
                  meaning: "The gap between what was withheld month by month and what was due. Withhold more than you owe and it comes back."),
            Entry(term: "Solidarity surcharge",
                  meaning: "An extra rate on very high incomes, on top of the ordinary scale. It only touches income above its floor."),
        ]),
        Group(title: "How the tax is worked out", entries: [
            Entry(term: "Specific deduction",
                  meaning: "Dedução específica: a flat slice of every salary that goes untaxed, standing in for work expenses nobody itemises. You get the fixed figure or your social security, whichever is larger. It is applied when you file, and never appears on a payslip."),
            Entry(term: "IRS Jovem",
                  meaning: "Relief for young workers: a share of your salary exempt from tax, tapering across ten fiscal years and capped at a multiple of the social support index. The years are ones you claim it in, not calendar years elapsed — a year you skip pushes the last one further out."),
            Entry(term: "Taxable income",
                  meaning: "What is left of your salary once relief and deductions come off. The bands apply to this, not to what you earn."),
            Entry(term: "Tax bands",
                  meaning: "Escalões. Each band taxes only the slice of income that falls inside it, so you are never taxed entirely at one rate. Reaching a higher band costs you more only on the part above its floor."),
            Entry(term: "Social support index",
                  meaning: "The IAS, published each year. It sets the specific deduction and caps the IRS Jovem exemption, so both move with it."),
        ]),
        Group(title: "Rates", entries: [
            Entry(term: "Marginal rate",
                  meaning: "What the next euro you earn would cost: the band it lands in, plus any surcharge, plus social security."),
            Entry(term: "Effective rate",
                  meaning: "Everything taken, over everything you were paid. Always below the marginal rate, because the lower bands tax the first part of your income more gently."),
        ]),
        Group(title: "What you end up with", entries: [
            Entry(term: "Net for the year",
                  meaning: "Everything received, less social security and the tax actually due."),
            Entry(term: "Reaches you",
                  meaning: "The same, but at the rate your employer withholds rather than what the assessment says. This is the money that lands during the year; the balance follows later."),
            Entry(term: "Net per month",
                  meaning: "The spendable figure, spread evenly across twelve months. It holds back anything that cannot be spent freely — a meal card buys food and nothing else — and it is what the Projections screen budgets on."),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DialogHeader(title: "What everything means",
                         subtitle: "Several of these mean something other than they sound like, so this says outright what each figure is.") {
                isPresented = false
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { Divider().padding(.vertical, 12) }
                        Text(group.title.uppercased())
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Color.ftInkTertiary)
                            .padding(.bottom, 8)

                        ForEach(group.entries) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.term)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(Color.ftInk)
                                Text(entry.meaning)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Color.ftInkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 10)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(Color.ftSurface)

            Divider()

            HStack {
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: Theme.Size.sheetWide, height: 560)
        .background(Color.ftCanvas)
    }
}
