import SwiftUI
import SwiftData
import Charts

struct ExpensesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.sortOrder) private var expenses: [Expense]
    @Query(sort: \ExpenseCategory.sortOrder) private var categories: [ExpenseCategory]

    @State private var errorMessage: String?
    @State private var showingCategories = false
    @State private var hoveredRow: UUID?

    private var metrics: ExpenseMetrics {
        ExpenseMetrics.compute(
            expenses: expenses.map { $0.toInput() },
            categoryNames: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) }),
            categoryOrder: categories.map(\.id))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Callout(text: "These are your recurring commitments. Their monthly total is what Projections uses as monthly expenses — there is no separate figure to keep in sync.")

                if expenses.isEmpty {
                    ContentUnavailableView("No expenses yet",
                                           systemImage: "creditcard",
                                           description: Text("Add what you pay every month to make projections realistic."))
                        .frame(height: 300)
                } else {
                    hero
                    table
                    if metrics.byCategory.count > 1 { breakdown }
                }
            }
            .padding(Theme.screenPadding)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Categories…", systemImage: "tag") { showingCategories = true }
                    .help("Create and edit expense categories")
                Button("Add Expense", systemImage: "plus") { addExpense() }
                    .keyboardShortcut("n")
            }
        }
        .sheet(isPresented: $showingCategories) { categorySheet }
        .alert("Couldn't do that",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 26) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Every month")
                HeroFigure(value: Money.currency(metrics.monthlyTotal))
                    .contentTransition(.numericText())
                    .padding(.top, 2)
                HStack(spacing: 8) {
                    DeltaPill(text: "\(Money.currency(metrics.yearlyTotal)) a year",
                              direction: .flat)
                    Text(countCaption)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.ftInkTertiary)
                }
                .padding(.top, 9)
            }

            Spacer(minLength: 12)

            if let largest = metrics.largest {
                VStack(alignment: .trailing, spacing: 1) {
                    Eyebrow("Largest")
                    Text(largest.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ftInkSecondary)
                    Text(Money.currency(largest.monthlyAmount, decimals: 2) + " / month")
                        .font(.figure(17))
                        .monospacedDigit()
                        .foregroundStyle(Color.ftInk)
                }
            }
        }
        .ftCard(padding: 20)
    }

    private var countCaption: String {
        var parts = ["\(metrics.activeCount) active"]
        if metrics.pausedCount > 0 { parts.append("\(metrics.pausedCount) paused") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Table

    private var table: some View {
        CardSection("Commitments", subtitle: "Amounts are as billed; the monthly column normalises them") {
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
                    GridRow {
                        Text("Name").frame(width: 190, alignment: .leading)
                        Text("Amount").frame(width: 104, alignment: .trailing)
                        Text("Frequency").frame(width: 104, alignment: .leading)
                        Text("Category").frame(width: 136, alignment: .leading)
                        Text("Per month").frame(width: 96, alignment: .trailing)
                        Text("Per year").frame(width: 100, alignment: .trailing)
                        Text("Active").frame(width: 52, alignment: .center)
                        Color.clear.frame(width: 22)
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.ftInkTertiary)
                    .padding(.bottom, 8)

                    Divider().gridCellUnsizedAxes(.horizontal)

                    ForEach(Array(expenses.enumerated()), id: \.element.id) { index, expense in
                        row(expense)
                        if index < expenses.count - 1 {
                            Divider().gridCellUnsizedAxes(.horizontal).opacity(0.6)
                        }
                    }

                    Divider().gridCellUnsizedAxes(.horizontal)

                    GridRow {
                        Text("Total").font(.system(size: 12.5, weight: .semibold))
                            .frame(width: 190, alignment: .leading)
                        Text("").frame(width: 104)
                        Text("").frame(width: 104)
                        Text("").frame(width: 136)
                        DerivedText(text: Money.currency(metrics.monthlyTotal, decimals: 2),
                                    width: 96, emphasis: true)
                        DerivedText(text: Money.currency(metrics.yearlyTotal, decimals: 2),
                                    width: 100, emphasis: true)
                        Text("").frame(width: 52)
                        Color.clear.frame(width: 22)
                    }
                    .padding(.top, 6)
                }
                .padding(Theme.cardPadding)
            }
        }
    }

    private func row(_ expense: Expense) -> some View {
        GridRow {
            NameField(name: expense.name, width: 190) { newValue in
                do { try ExpenseService.rename(expense, to: newValue, in: context) }
                catch { errorMessage = error.localizedDescription }
            }

            MoneyField(value: Binding(
                get: { expense.amount },
                set: { expense.amount = max(0, $0); try? context.save() }),
                width: 104)

            Picker("", selection: Binding(
                get: { expense.frequency },
                set: { expense.frequency = $0; try? context.save() })) {
                ForEach(ExpenseFrequency.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 104)

            Picker("", selection: Binding(
                get: { expense.categoryID },
                set: { newID in
                    ExpenseService.assign(expense,
                                          to: categories.first { $0.id == newID },
                                          in: context)
                })) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 136)

            DerivedText(text: Money.currency(expense.monthlyAmount, decimals: 2),
                        width: 96,
                        tint: expense.isActive ? nil : Color.ftInkTertiary)

            DerivedText(text: Money.currency(expense.yearlyAmount, decimals: 2),
                        width: 100,
                        tint: expense.isActive ? nil : Color.ftInkTertiary)

            Toggle("", isOn: Binding(
                get: { expense.isActive },
                set: { expense.isActive = $0; try? context.save() }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .frame(width: 52, alignment: .center)

            Button {
                ExpenseService.delete(expense, in: context)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(hoveredRow == expense.id
                                     ? Color.ftNegative
                                     : Color.ftInkTertiary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Delete this expense")
            .frame(width: 22)
        }
        .padding(.vertical, 5)
        .background(hoveredRow == expense.id ? Color.ftSurfaceAlt : .clear)
        .onHover { hoveredRow = $0 ? expense.id : (hoveredRow == expense.id ? nil : hoveredRow) }
    }

    // MARK: - Breakdown

    private var breakdown: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: Theme.gap)],
                  spacing: Theme.gap) {
            CardSection("Where it goes") {
                Chart(metrics.byCategory) { slice in
                    SectorMark(angle: .value("Amount", slice.monthlyAmount),
                               innerRadius: .ratio(0.62),
                               angularInset: 2)
                        .foregroundStyle(by: .value("Category", slice.name))
                        .cornerRadius(5)
                }
                .chartForegroundStyleScale(range: metrics.byCategory.map { colour(for: $0) })
                .chartLegend(.hidden)
                .frame(height: 240)
            }

            CardSection("By category") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                    GridRow {
                        Text("Category")
                        Text("Per month").gridColumnAlignment(.trailing)
                        Text("Share").gridColumnAlignment(.trailing)
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.ftInkTertiary)

                    Divider().gridCellUnsizedAxes(.horizontal)

                    ForEach(metrics.byCategory) { slice in
                        GridRow {
                            HStack(spacing: 9) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(colour(for: slice))
                                    .frame(width: 9, height: 9)
                                Text(slice.name).font(.system(size: 12.5))
                            }
                            DerivedText(text: Money.currency(slice.monthlyAmount, decimals: 2))
                            DerivedText(text: Money.percent(slice.share))
                        }
                    }
                }
            }
        }
    }

    private func colour(for slice: ExpenseCategoryTotal) -> Color {
        guard let id = slice.categoryID,
              let hex = categories.first(where: { $0.id == id })?.colorHex
        else { return Color.ftInkTertiary }
        return Color(hex: hex)
    }

    // MARK: - Categories dialog

    private var categorySheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Expense Categories").font(.system(size: 17, weight: .semibold))
                Text("Group your commitments. A category still in use can't be deleted.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ftInkTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                        categoryRow(category)
                        if index < categories.count - 1 {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
            .frame(height: 240)
            .background(Color.ftSurface)

            Divider()

            HStack(spacing: 8) {
                Button {
                    addCategory()
                } label: {
                    Image(systemName: "plus").frame(width: 18)
                }
                .buttonStyle(.borderless)
                .help("Add a category")

                Spacer()

                Button("Done") { showingCategories = false }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 520)
        .background(Color.ftCanvas)
    }

    private func categoryRow(_ category: ExpenseCategory) -> some View {
        let inUse = ExpenseService.expensesUsing(category, expenses: expenses)
        return HStack(spacing: 12) {
            ColorPicker("", selection: Binding(
                get: { Color(hex: category.colorHex) },
                set: { category.colorHex = $0.hexString; try? context.save() }))
                .labelsHidden()

            NameField(name: category.name, width: 220) { newValue in
                do { try ExpenseService.renameCategory(category, to: newValue, in: context) }
                catch { errorMessage = error.localizedDescription }
            }

            Spacer(minLength: 8)

            Text(inUse == 0 ? "unused" : "\(inUse) expense\(inUse == 1 ? "" : "s")")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.ftInkTertiary)

            Button {
                do { try ExpenseService.deleteCategory(category, expenses: expenses, in: context) }
                catch { errorMessage = error.localizedDescription }
            } label: {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(inUse > 0)
            .help(inUse > 0 ? "In use — move its expenses elsewhere first" : "Delete this category")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func addExpense() {
        do {
            try ExpenseService.create(name: "New expense", amount: 0,
                                      categoryID: categories.first?.id, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addCategory() {
        let existing = Set(categories.map { $0.name.lowercased() })
        var name = "New category"
        var suffix = 2
        while existing.contains(name.lowercased()) {
            name = "New category \(suffix)"
            suffix += 1
        }
        let palette = Theme.accountPalette
        do {
            try ExpenseService.createCategory(
                name: name,
                colorHex: palette[categories.count % palette.count],
                in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
