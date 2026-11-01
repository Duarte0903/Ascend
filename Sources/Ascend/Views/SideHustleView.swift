import SwiftUI
import SwiftData

/// A side hustle being named, before it exists.
private struct DraftHustle {
    var name = ""
    var activity: SideHustleActivity = .professionalServices
}

/// A payment being entered, before it is recorded.
private struct DraftEarning {
    var hustleID: UUID
    var date = Date()
    var amount: Double = 0
    var note = ""
    /// You record an invoice when you send it, so it starts unpaid.
    var isPaid = false
}

struct SideHustleView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SideHustle.sortOrder) private var hustles: [SideHustle]
    // Settings are read for the marginal rate; without the query the screen
    // would not redraw when the Tax screen changes underneath it.
    @Query private var storedSettings: [AppSettings]

    @State private var selectedYear: Int?
    @State private var selectedHustleID: UUID?
    @State private var draftHustle: DraftHustle?
    @State private var draftEarning: DraftEarning?
    @State private var errorMessage: String?
    @State private var hoveredRow: UUID?
    /// Which hustles have their invoices open. Closed by default: the table
    /// is about what each one earned, not every payment behind it.
    @State private var expanded: Set<UUID> = []
    @FocusState private var draftNameFocused: Bool

    private var settings: AppSettings { SeedData.settings(in: context) }
    private var active: [SideHustle] { hustles.filter { !$0.isArchived } }
    private var inputs: [SideHustleInput] { active.map { $0.toInput() } }

    private var years: [Int] {
        let found = SideHustleEngine.years(in: inputs)
        let current = Calendar.current.component(.year, from: Date())
        return found.contains(current) ? found : ([current] + found)
    }

    private var year: Int {
        selectedYear ?? years.first ?? Calendar.current.component(.year, from: Date())
    }

    private var rules: SideHustleRules {
        SideHustleService.rules(settings: settings, hustle: nil)
    }

    private var summary: SideHustleYear {
        SideHustleYear.compute(inputs, rules: rules, year: year)
    }

    private var selected: SideHustle? {
        active.first { $0.id == selectedHustleID } ?? active.first
    }

    var body: some View {
        FillingScreen {
            Callout(text: calloutText, systemImage: "info.circle.fill")

            tiles

            HStack(alignment: .top, spacing: Theme.gap) {
                hustleTable
                if !active.isEmpty {
                    breakdown
                        .frame(width: Theme.Size.sidePanelWide)
                }
            }
            .fillsHeight(minimum: 220)
        }
        .toolbar {
            // Two groups with a spacer between them: filtering the year and
            // adding work are unrelated, and sharing one piece of glass
            // reads as though the plus belonged to the picker.
            ToolbarItemGroup {
                Menu {
                    ForEach(years, id: \.self) { option in
                        Button {
                            selectedYear = option
                        } label: {
                            HStack {
                                // `verbatim`: a year is a label, not a
                                // quantity, or it comes out as "2 026".
                                Text(verbatim: String(option))
                                if option == year { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Label(String(year), systemImage: "calendar")
                }
                .help("Show one year's invoices")
            }
            ToolbarSpacer(.flexible)
            ToolbarItem {
                Button("New side hustle", systemImage: "plus") {
                    draftHustle = DraftHustle()
                    draftNameFocused = true
                }
                .disabled(draftHustle != nil)
                .help("Add work you invoice for on the side")
            }
        }
        .alert("Couldn't do that", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
               actions: { Button("OK") { errorMessage = nil } },
               message: { Text(errorMessage ?? "") })
    }

    private var calloutText: String {
        let base = "An estimate under the regime simplificado. A share of what you invoice is taxed as profit — the rest is treated as the cost of earning it — and IRS is reckoned at the rate your next euro meets."
        return rules.derivesIRSRate
            ? base + " That rate, \(Money.percent(rules.marginalIRSRate)), comes from your Tax screen."
            : base + " Set up the Tax screen and that rate is worked out for you."
    }

    // MARK: - Summary

    private var tiles: some View {
        HStack(spacing: Theme.gap) {
            MetricTile(title: "Paid in \(year)",
                       value: Money.currency(summary.gross, decimals: 2),
                       caption: summary.outstanding > 0
                           ? "\(Money.currency(summary.outstanding, decimals: 2)) still owed to you"
                           : "Across \(active.count) side hustle\(active.count == 1 ? "" : "s")")
            MetricTile(title: "Set aside for tax",
                       value: Money.currency(summary.totalTax, decimals: 2),
                       caption: "IRS \(Money.currency(summary.irs, decimals: 2)) · contributions \(Money.currency(summary.contributions, decimals: 2))",
                       valueColor: .ftNegative)
            MetricTile(title: "Yours to keep",
                       value: Money.currency(summary.net, decimals: 2),
                       caption: "\(Money.percent(summary.effectiveRate)) of what arrived goes in tax",
                       valueColor: .ftPositive)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - The hustles

    private var hustleTable: some View {
        CardSection("Side hustles", subtitle: "What each one earned in \(year), and what it owes") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                GridRow {
                    header("Name")
                    header("What it is")
                    header("Paid").gridColumnAlignment(.trailing)
                    header("Owed").gridColumnAlignment(.trailing)
                    header("Tax").gridColumnAlignment(.trailing)
                    header("Kept").gridColumnAlignment(.trailing)
                    Color.clear.frame(width: Theme.Size.iconButton, height: 1)
                }
                Divider()
                if active.isEmpty && draftHustle == nil {
                    GridRow {
                        Text("Nothing here yet. Use New side hustle above to add work you invoice for.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ftInkTertiary)
                            .gridCellColumns(7)
                    }
                }
                ForEach(active) { hustle in
                    let found = summary.hustles.first { $0.id == hustle.id }
                    GridRow {
                        Button {
                            selectedHustleID = hustle.id
                            toggleExpanded(hustle.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.ftInkTertiary)
                                    .rotationEffect(.degrees(expanded.contains(hustle.id)
                                                             ? 90 : 0))
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color(hex: hustle.colorHex))
                                    .frame(width: Theme.Size.dot, height: Theme.Size.dot)
                                Text(hustle.name)
                                    .font(.system(size: 12.5,
                                                  weight: hustle.id == selected?.id
                                                      ? .semibold : .regular))
                                    .foregroundStyle(Color.ftInk)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(expanded.contains(hustle.id)
                              ? "Hide its invoices" : "Show its invoices")

                        Picker("", selection: Binding(
                            get: { hustle.activity },
                            set: { hustle.activity = $0; try? context.save() })) {
                            ForEach(SideHustleActivity.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: Theme.Size.picker)

                        value(found?.gross ?? 0)
                        value(found?.outstanding ?? 0,
                              tint: (found?.outstanding ?? 0) > 0 ? .orange : nil)
                        value(found?.totalTax ?? 0, tint: .ftNegative)
                        value(found?.net ?? 0, emphasis: true)

                        Button {
                            SideHustleService.delete(hustle, in: context)
                            if selectedHustleID == hustle.id { selectedHustleID = nil }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.ftInkTertiary)
                                .frame(width: Theme.Size.iconButton,
                                       height: Theme.Size.iconButton)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(hoveredRow == hustle.id ? 1 : 0)
                        .help("Delete this side hustle and everything it earned")
                    }
                    .onHover { hoveredRow = $0 ? hustle.id : nil }
                    if expanded.contains(hustle.id) {
                        GridRow {
                            invoices(of: hustle)
                                .gridCellColumns(7)
                                .padding(.leading, 17)
                                .padding(.vertical, 2)
                        }
                    }
                    Divider()
                }
                if draftHustle != nil { draftHustleRow }
            }
        }
        .fillingHeight()
    }

    private var draftHustleRow: some View {
        GridRow {
            TextField("Name", text: Binding(
                get: { draftHustle?.name ?? "" },
                set: { draftHustle?.name = $0 }))
                .textFieldStyle(.roundedBorder)
                .frame(width: Theme.Size.name)
                .focused($draftNameFocused)
                .onSubmit { commitDraftHustle() }
            Picker("", selection: Binding(
                get: { draftHustle?.activity ?? .professionalServices },
                set: { draftHustle?.activity = $0 })) {
                ForEach(SideHustleActivity.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: Theme.Size.picker)
            Color.clear.frame(height: 1)
            Color.clear.frame(height: 1)
            Color.clear.frame(height: 1)
            HStack(spacing: 6) {
                Button("Cancel") { draftHustle = nil }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                Button("Add") { commitDraftHustle() }
                    .controlSize(.small)
            }
            .gridColumnAlignment(.trailing)
            Color.clear.frame(width: Theme.Size.iconButton, height: 1)
        }
    }

    private func toggleExpanded(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func commitDraftHustle() {
        guard let draft = draftHustle else { return }
        do {
            let created = try SideHustleService.create(name: draft.name,
                                                       activity: draft.activity,
                                                       in: context)
            selectedHustleID = created.id
            draftHustle = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Earnings

    /// One hustle's invoices, folded under its row in the table.
    @ViewBuilder
    private func invoices(of hustle: SideHustle) -> some View {
        let entries = (hustle.earnings ?? [])
            .filter { Calendar.current.component(.year, from: $0.date) == year }
            .sorted { $0.date > $1.date }

        VStack(alignment: .leading, spacing: 7) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    header("Date")
                    header("Note")
                    header("Invoiced").gridColumnAlignment(.trailing)
                    header("Paid")
                    Color.clear.frame(width: Theme.Size.iconButton, height: 1)
                }
                if entries.isEmpty && draftEarning?.hustleID != hustle.id {
                    GridRow {
                        Text("No invoices recorded for \(year).")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.ftInkTertiary)
                            .gridCellColumns(5)
                    }
                }
                ForEach(entries) { stored in
                    GridRow {
                        Text(Dates.short(stored.date))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(stored.isPaid
                                             ? Color.ftInk : Color.ftInkTertiary)
                        DescriptionField(note: stored.note) {
                            SideHustleService.update(stored, note: $0, in: context)
                        }
                        MoneyField(value: Binding(
                            get: { stored.amount },
                            set: { SideHustleService.update(stored, amount: $0,
                                                            in: context) }),
                                   decimals: 2, suffix: Money.symbol)
                        Toggle("", isOn: Binding(
                            get: { stored.isPaid },
                            set: { SideHustleService.update(stored, isPaid: $0,
                                                            in: context) }))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .help(stored.isPaid
                                  ? "Received — this is taxed"
                                  : "Still owed — not taxed until it arrives")
                        Button {
                            SideHustleService.remove(stored, in: context)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.ftInkTertiary)
                                .frame(width: Theme.Size.iconButton,
                                       height: Theme.Size.iconButton)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(hoveredRow == stored.id ? 1 : 0)
                    }
                    .onHover { hoveredRow = $0 ? stored.id : nil }
                }
                if draftEarning?.hustleID == hustle.id { draftEarningRow(for: hustle) }
            }
            Button {
                draftEarning = DraftEarning(hustleID: hustle.id)
            } label: {
                Label("Record an invoice", systemImage: "plus")
            }
            .controlSize(.small)
            .disabled(draftEarning != nil)
        }
        .padding(.vertical, 4)
    }

    private func draftEarningRow(for hustle: SideHustle) -> some View {
        GridRow {
            DatePicker("", selection: Binding(
                get: { draftEarning?.date ?? Date() },
                set: { draftEarning?.date = $0 }), displayedComponents: .date)
                .labelsHidden()
                .environment(\.locale, Dates.pickerLocale)
            TextField("What for", text: Binding(
                get: { draftEarning?.note ?? "" },
                set: { draftEarning?.note = $0 }))
                .textFieldStyle(.roundedBorder)
            MoneyField(value: Binding(
                get: { draftEarning?.amount ?? 0 },
                set: { draftEarning?.amount = $0 }),
                       decimals: 2, suffix: Money.symbol)
            Toggle("", isOn: Binding(
                get: { draftEarning?.isPaid ?? false },
                set: { draftEarning?.isPaid = $0 }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("Tick if the money has already arrived")
            HStack(spacing: 6) {
                Button("Cancel") { draftEarning = nil }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                Button("Add") { commitDraftEarning(for: hustle) }
                    .controlSize(.small)
            }
        }
    }

    private func commitDraftEarning(for hustle: SideHustle) {
        guard let draft = draftEarning else { return }
        do {
            try SideHustleService.record(amount: draft.amount, on: draft.date,
                                         note: draft.note, isPaid: draft.isPaid,
                                         for: hustle, in: context)
            selectedYear = Calendar.current.component(.year, from: draft.date)
            draftEarning = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - What it owes

    private var breakdown: some View {
        CardSection("What you owe on it",
                    subtitle: selected.map { "\($0.name), \(year)" } ?? "Pick a side hustle") {
            if let hustle = selected,
               let found = summary.hustles.first(where: { $0.id == hustle.id }) {
                // The answer, before any of the working that produces it.
                VStack(alignment: .leading, spacing: 2) {
                    Text(Money.currency(found.totalTax, decimals: 2))
                        .font(.figure(26))
                        .monospacedDigit()
                        .foregroundStyle(found.totalTax > 0 ? Color.ftNegative : Color.ftPositive)
                        .contentTransition(.numericText())
                    Text(headline(found))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.ftInkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Grid(alignment: .leadingFirstTextBaseline,
                     horizontalSpacing: 18, verticalSpacing: 10) {
                    amountRow("Yours to keep", found.net, emphasised: true)
                }

                Text(contributionNote(found))
                    .font(.system(size: 11.5))
                    .foregroundStyle(found.contributions > 0
                                     ? Color.ftInkTertiary : Color.ftPositive)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().padding(.vertical, 2)

                // Settings, not figures: kept apart so the card does not read
                // as though these were amounts owed.
                Eyebrow("How it is treated")
                Grid(alignment: .leadingFirstTextBaseline,
                     horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        Text("Contributions")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.ftInkSecondary)
                        Picker("", selection: Binding(
                            get: { hustle.contributions },
                            set: { hustle.contributions = $0; try? context.save() })) {
                            ForEach(SideHustleContributions.allCases) {
                                Text($0.label).tag($0)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    GridRow {
                        Text("Months running")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.ftInkSecondary)
                        IntField(value: Binding(
                            get: { hustle.monthsActive == 0 ? 12 : hustle.monthsActive },
                            set: { hustle.monthsActive = min(12, max(1, $0))
                                   try? context.save() }),
                                 range: 1...12, width: Theme.Size.fieldSmall)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
        .fillingHeight()
    }

    /// One line saying what the figure above is, and what is not in it yet.
    private func headline(_ found: SideHustleAssessment) -> String {
        guard found.gross > 0 else {
            return found.outstanding > 0
                ? "Nothing has arrived yet. The \(Money.currency(found.outstanding, decimals: 2)) outstanding is not taxed until it does."
                : "Nothing recorded for \(year) yet."
        }
        var text = "to set aside from the \(Money.currency(found.gross, decimals: 2)) you received"
        if found.contributions > 0 {
            text += " — \(Money.currency(found.irs, decimals: 2)) IRS and \(Money.currency(found.contributions, decimals: 2)) social security"
        }
        if found.outstanding > 0 {
            text += ". A further \(Money.currency(found.outstanding, decimals: 2)) is owed to you and is not taxed until it arrives"
        }
        return text + "."
    }

    /// A line of working: smaller and quieter than an amount that is owed.
    private func contributionNote(_ found: SideHustleAssessment) -> String {
        switch found.contributionBasis {
        case .noIncome:
            "Nothing invoiced yet, so nothing is owed."
        case .exemptBelowCeiling:
            "No social security: your salary already pays it, and this averages \(Money.currency(found.monthlyRelevantIncome, decimals: 2)) a month — under the \(Money.currency(rules.exemptionCeiling, decimals: 2)) ceiling."
        case .exemptBySetting:
            "Set to exempt by hand, so no social security is counted."
        case .chargedBySetting:
            "Set to charged by hand, whatever the ceiling says."
        case .charged:
            "Social security is charged because this averages \(Money.currency(found.monthlyRelevantIncome, decimals: 2)) a month — over the \(Money.currency(rules.exemptionCeiling, decimals: 2)) ceiling."
        }
    }

    // MARK: - Pieces

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Color.ftInkTertiary)
    }

    private func value(_ amount: Double, tint: Color? = nil,
                       emphasis: Bool = false) -> some View {
        Text(Money.currency(amount, decimals: 2))
            .font(.figure(13, weight: emphasis ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(tint ?? (emphasis ? Color.ftInk : Color.ftInkSecondary))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func amountRow(_ title: String, _ amount: Double,
                           detail: String? = nil,
                           emphasised: Bool = false) -> some View {
        GridRow {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12.5, weight: emphasised ? .semibold : .regular))
                    .foregroundStyle(emphasised ? Color.ftInk : Color.ftInkSecondary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ftInkTertiary)
                }
            }
            Text(Money.currency(abs(amount) < 0.005 ? 0 : amount, decimals: 2))
                .font(.figure(13, weight: emphasised ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(amount < 0 ? Color.ftNegative : Color.ftInk)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
