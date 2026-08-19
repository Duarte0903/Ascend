import SwiftUI
import SwiftData
import Charts

struct AllocationView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]
    @Query(sort: \Expense.sortOrder) private var expenseItems: [Expense]
    /// Settings are edited on other screens now, so this view has to watch
    /// them: without a query on the object, a change elsewhere leaves these
    /// figures stale until the screen is left and re-entered.
    @Query private var storedSettings: [AppSettings]

    private var settings: AppSettings {
        storedSettings.first ?? SeedData.settings(in: context)
    }

    private var latestDate: Date? {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records,
            settings: settings,
            expenses: expenseItems)).last?.date
    }

    private var allocation: AllocationMetrics {
        let input = PortfolioStore.input(accounts: accounts, records: records,
                                         settings: settings,
            expenses: expenseItems)
        return AllocationMetrics.compute(accounts: input.accounts,
                                         records: LedgerEngine.derive(input))
    }

    var body: some View {
        FillingScreen {
            if allocation.slices.isEmpty {
                ContentUnavailableView("Nothing to allocate yet",
                                       systemImage: "chart.pie",
                                       description: Text("Add a record on the Balances screen."))
                    .frame(maxWidth: .infinity)
                    .fillsHeight()
            } else {
                // Equal halves that both stretch, so neither card leaves a void
                // beneath it on a tall window.
                HStack(alignment: .top, spacing: Theme.gap) {
                    donut.fillsHeight(minimum: 320)
                    breakdown.fillsHeight(minimum: 320)
                }
                .fillsHeight(minimum: 320)
            }
        }
    }

    private var donut: some View {
        CardSection("Where your money sits", subtitle: latestCaption) {
            Chart(allocation.slices) { slice in
                SectorMark(angle: .value("Amount", slice.amount),
                           innerRadius: .ratio(0.62),
                           angularInset: 2)
                    .foregroundStyle(by: .value("Account", slice.name))
                    .cornerRadius(5)
            }
            .chartForegroundStyleScale(range: allocation.slices.map { Color(hex: $0.colorHex) })
            .chartLegend(.hidden)
            .chartBackground { proxy in
                GeometryReader { geo in
                    if let frame = proxy.plotFrame.map({ geo[$0] }) {
                        VStack(spacing: 1) {
                            Text(Money.currency(allocation.total))
                                .font(.figure(26))
                                .monospacedDigit()
                                .foregroundStyle(Color.ftInk)
                            Text("total")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color.ftInkTertiary)
                        }
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func note(for accountID: UUID) -> String? {
        let note = accounts.first { $0.id == accountID }?.note ?? ""
        return note.isEmpty ? nil : note
    }

    private var latestCaption: String? {
        latestDate.map { "Most recent record, \($0.formatted(.dateTime.day().month(.wide).year()))" }
    }

    private var breakdown: some View {
        CardSection("Breakdown") {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 9) {
                GridRow {
                    Text("Account")
                    Text("Amount").gridColumnAlignment(.trailing)
                    Text("Share").gridColumnAlignment(.trailing)
                }
                .font(.tableHeader)
                .tracking(Theme.tableHeaderTracking)
                .foregroundStyle(Color.ftInkSecondary)

                Divider().gridCellUnsizedAxes(.horizontal)

                ForEach(allocation.slices) { slice in
                    GridRow {
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color(hex: slice.colorHex))
                                .frame(width: Theme.Size.dot, height: Theme.Size.dot)
                            Text(slice.name).font(.system(size: 12.5))
                        }
                        .help(note(for: slice.accountID) ?? slice.name)
                        DerivedText(text: Money.currency(slice.amount))
                        DerivedText(text: Money.percent(slice.share))
                    }
                    shareBar(slice)
                }

                Divider().gridCellUnsizedAxes(.horizontal)

                GridRow {
                    Text("Total").font(.system(size: 12.5, weight: .semibold))
                    DerivedText(text: Money.currency(allocation.total), emphasis: true)
                    DerivedText(text: Money.percent(1.0), emphasis: true)
                }
                GridRow {
                    Text("Usable").font(.system(size: 12.5))
                        .foregroundStyle(Color.ftInkTertiary)
                    DerivedText(text: Money.currency(allocation.usable))
                    Text("")
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// A thin bar under each row — share as length, not only as a number.
    private func shareBar(_ slice: AllocationSlice) -> some View {
        GridRow {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ftSurfaceAlt)
                    Capsule().fill(Color(hex: slice.colorHex).opacity(0.75))
                        .frame(width: max(geo.size.width * slice.share, slice.share > 0 ? 3 : 0))
                }
            }
            .frame(height: 4)
            .gridCellColumns(3)
        }
    }
}
