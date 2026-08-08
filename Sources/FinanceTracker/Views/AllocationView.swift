import SwiftUI
import SwiftData
import Charts

struct AllocationView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]

    private var allocation: AllocationMetrics {
        let input = PortfolioStore.input(accounts: accounts, records: records,
                                         settings: SeedData.settings(in: context))
        return AllocationMetrics.compute(accounts: input.accounts,
                                         records: LedgerEngine.derive(input))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if allocation.slices.isEmpty {
                    ContentUnavailableView("Nothing to allocate yet",
                                           systemImage: "chart.pie",
                                           description: Text("Add a record on the Balances screen."))
                        .frame(height: 300)
                } else {
                    donut
                    breakdown
                }
            }
            .padding(20)
        }
    }

    private var donut: some View {
        CardSection("Where your money sits") {
            Chart(allocation.slices) { slice in
                SectorMark(angle: .value("Amount", slice.amount),
                           innerRadius: .ratio(0.55),
                           angularInset: 1.5)
                    .foregroundStyle(by: .value("Account", slice.name))
                    .cornerRadius(4)
            }
            .chartForegroundStyleScale(
                range: allocation.slices.map { Color(hex: $0.colorHex) })
            .frame(height: 280)
        }
    }

    private var breakdown: some View {
        CardSection("Breakdown") {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Text("Account")
                    Text("Amount").gridColumnAlignment(.trailing)
                    Text("Share").gridColumnAlignment(.trailing)
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Divider().gridCellUnsizedAxes(.horizontal)

                ForEach(allocation.slices) { slice in
                    GridRow {
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: slice.colorHex))
                                .frame(width: 10, height: 10)
                            Text(slice.name)
                        }
                        Text(Money.currency(slice.amount))
                        Text(Money.percent(slice.share))
                    }
                }

                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text("Total").fontWeight(.semibold)
                    Text(Money.currency(allocation.total)).fontWeight(.semibold)
                    Text(Money.percent(1.0)).fontWeight(.semibold)
                }
                GridRow {
                    Text("Usable").foregroundStyle(.secondary)
                    Text(Money.currency(allocation.usable)).foregroundStyle(.secondary)
                    Text("")
                }
            }
        }
    }
}
