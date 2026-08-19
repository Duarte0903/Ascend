import SwiftUI

/// Setting up the escalões de IRS: one row per band, with the ceiling and the
/// rate that applies to the slice of income inside it.
///
/// A popover rather than a sheet, like the other list managers — every edit is
/// committed as it is made, so clicking away loses nothing.
struct TaxBracketEditor: View {
    @Binding var isPresented: Bool
    @Binding var table: TaxYear

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DialogHeader(title: "Tax bands",
                         subtitle: "Each band taxes only the slice of income inside it, so a higher band never re-taxes what a lower one already did.") {
                isPresented = false
            }

            header

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(table.brackets.enumerated()), id: \.offset) { index, bracket in
                        row(index, bracket)
                        if index < table.brackets.count - 1 {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
            .frame(height: 300)
            .background(Color.ftSurface)

            Divider()

            footer
        }
        .frame(width: Theme.Size.sheetNarrow)
        .background(Color.ftCanvas)
    }

    private var header: some View {
        HStack(spacing: 12) {
            columnTitle("Band", width: 38)
            columnTitle("Up to", width: Theme.Size.picker)
            columnTitle("Rate", width: Theme.Size.fieldSmall)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func columnTitle(_ text: String, width: CGFloat) -> some View {
        Text(text.uppercased())
            .font(.system(size: Theme.tableHeaderSize, weight: .semibold))
            .tracking(Theme.tableHeaderTracking)
            .foregroundStyle(Color.ftInkTertiary)
            .frame(width: width, alignment: .leading)
    }

    private func row(_ index: Int, _ bracket: TaxBracket) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.ftInkTertiary)
                .frame(width: 38, alignment: .leading)

            if let limit = bracket.upperLimit {
                MoneyField(value: Binding(
                    get: { limit },
                    set: { edit(index) { $0.upperLimit = max(0, $1) } ($0) }),
                           decimals: 0, width: Theme.Size.picker, suffix: Money.symbol)
            } else {
                Text("No ceiling")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.ftInkTertiary)
                    .frame(width: Theme.Size.picker, alignment: .leading)
            }

            MoneyField(value: Binding(
                get: { bracket.rate * 100 },
                set: { new in edit(index) { $0.rate = min(max(0, $1), 100) / 100 } (new) }),
                       decimals: 1, width: Theme.Size.fieldSmall, suffix: "%")

            Spacer(minLength: 0)

            Button {
                table.removeBracket(at: index)
            } label: {
                Image(systemName: "trash").frame(width: Theme.Size.iconButton)
            }
            .buttonStyle(.borderless)
            // The open-ended band is what taxes everything above the last
            // ceiling, so it is not removable.
            .disabled(bracket.upperLimit == nil || table.brackets.count <= 1)
            .help(bracket.upperLimit == nil
                  ? "The top band has no ceiling and can't be removed"
                  : "Remove this band")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                table.addBracket()
            } label: {
                Image(systemName: "plus").frame(width: Theme.Size.iconButton)
            }
            .buttonStyle(.borderless)
            .help("Add a band")

            Text(hint)
                .font(.system(size: 11.5))
                .foregroundStyle(table.bandsAreOrdered ? Color.ftInkTertiary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("Done") {
                // Sorted on the way out rather than as you type, which would
                // move a row out from under the cursor mid-edit.
                table = table.normalised()
                isPresented = false
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var hint: String {
        table.bandsAreOrdered
            ? "\(table.brackets.count) bands, \(Money.percent(lowestRate)) to \(Money.percent(highestRate))."
            : "Out of order — Done will sort them."
    }

    private var lowestRate: Double { table.brackets.map(\.rate).min() ?? 0 }
    private var highestRate: Double { table.brackets.map(\.rate).max() ?? 0 }

    /// Changes one band in place, leaving the rest alone.
    private func edit(_ index: Int,
                      _ change: @escaping (inout TaxBracket, Double) -> Void) -> (Double) -> Void {
        { value in
            guard table.brackets.indices.contains(index) else { return }
            change(&table.brackets[index], value)
        }
    }
}
