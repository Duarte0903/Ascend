import SwiftUI
import SwiftData
import Charts

/// A category being filled in, before it exists.
private struct DraftExpenseCategory {
    var name = ""
    var colorHex: String
}

struct ExpensesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.sortOrder) private var expenses: [Expense]
    @Query(sort: \ExpenseCategory.sortOrder) private var categories: [ExpenseCategory]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var errorMessage: String?
    @State private var showingCategories = false
    @State private var draftCategory: DraftExpenseCategory?
    @FocusState private var draftCategoryFocused: Bool
    @State private var hoveredRow: UUID?

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    private var metrics: ExpenseMetrics {
        ExpenseMetrics.compute(
            expenses: expenses.map { $0.toInput() },
            categoryNames: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) }),
            categoryOrder: categories.map(\.id))
    }

    var body: some View {
        FillingScreen {
            Callout(text: "These are your recurring commitments. Their monthly total is what Projections uses as monthly expenses — there is no separate figure to keep in sync.")

            if expenses.isEmpty {
                ContentUnavailableView("No expenses yet",
                                       systemImage: "creditcard",
                                       description: Text("Add what you pay every month to make projections realistic."))
                    .frame(maxWidth: .infinity)
                    .fillsHeight()
            } else {
                hero
                table
                if metrics.byCategory.count > 1 {
                    breakdown.fillsHeight(minimum: 260)
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .onHover { if !$0 { hoveredRow = nil } }
        .toolbar {
            ToolbarItemGroup {
                Button("Categories…", systemImage: "tag") { showingCategories = true }
                    .help("Create and edit expense categories")
                    .popover(isPresented: $showingCategories, arrowEdge: .bottom) {
                        categorySheet
                    }
                Button("Add Expense", systemImage: "plus") { addExpense() }
                    .keyboardShortcut("n")
            }
        }
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
        // The name column flexes so the table fills the window at any width,
        // while every numeric column keeps the same width as the field in it.
        CardSection("Commitments", subtitle: "Amounts are as billed; the monthly column normalises them") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Amount").frame(width: Theme.Size.field, alignment: .trailing)
                    Text("Frequency").frame(width: Theme.Size.picker, alignment: .leading)
                    Text("Category").frame(width: Theme.Size.picker, alignment: .leading)
                    Text("Paid from").frame(width: Theme.Size.picker, alignment: .leading)
                    Text("Per month").frame(width: Theme.Size.field, alignment: .trailing)
                    Text("Per year").frame(width: Theme.Size.field, alignment: .trailing)
                    Text("Active").frame(width: Theme.Size.control, alignment: .center)
                    Color.clear.frame(width: Theme.Size.iconButton)
                }
                .font(.tableHeader)
                .tracking(Theme.tableHeaderTracking)
                .foregroundStyle(Color.ftInkSecondary)
                .padding(.horizontal, 6)
                .padding(.bottom, 8)

                Divider()

                ForEach(Array(expenses.enumerated()), id: \.element.id) { index, expense in
                    row(expense)
                    if index < expenses.count - 1 { Divider().opacity(0.6) }
                }

                Divider()

                HStack(spacing: 14) {
                    Text("Total").font(.system(size: 12.5, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: Theme.Size.field, height: 1)
                    Color.clear.frame(width: Theme.Size.picker, height: 1)
                    Color.clear.frame(width: Theme.Size.picker, height: 1)
                    Color.clear.frame(width: Theme.Size.picker, height: 1)
                    DerivedText(text: Money.currency(metrics.monthlyTotal, decimals: 2),
                                width: Theme.Size.field, emphasis: true)
                    DerivedText(text: Money.currency(metrics.yearlyTotal, decimals: 2),
                                width: Theme.Size.field, emphasis: true)
                    Color.clear.frame(width: Theme.Size.control, height: 1)
                    Color.clear.frame(width: Theme.Size.iconButton)
                }
                .padding(.horizontal, 6)
                .padding(.top, 6)
            }
        }
    }

    private func row(_ expense: Expense) -> some View {
        HStack(spacing: 14) {
            NameField(name: expense.name) { newValue in
                do { try ExpenseService.rename(expense, to: newValue, in: context) }
                catch { errorMessage = error.localizedDescription }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MoneyField(value: Binding(
                get: { expense.amount },
                set: { expense.amount = max(0, $0); try? context.save() }))

            Picker("", selection: Binding(
                get: { expense.frequency },
                set: { expense.frequency = $0; try? context.save() })) {
                ForEach(ExpenseFrequency.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: Theme.Size.picker)

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
            .frame(width: Theme.Size.picker)

            Picker("", selection: Binding(
                get: { expense.accountID },
                set: { newID in
                    ExpenseService.assign(expense,
                                          toAccount: accounts.first { $0.id == newID },
                                          in: context)
                })) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(activeAccounts) { Text($0.name).tag(Optional($0.id)) }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: Theme.Size.picker)
            .help("The account this is paid from")

            DerivedText(text: Money.currency(expense.monthlyAmount, decimals: 2),
                        width: Theme.Size.field,
                        tint: expense.isActive ? nil : Color.ftInkTertiary)

            DerivedText(text: Money.currency(expense.yearlyAmount, decimals: 2),
                        width: Theme.Size.field,
                        tint: expense.isActive ? nil : Color.ftInkTertiary)

            Toggle("", isOn: Binding(
                get: { expense.isActive },
                set: { expense.isActive = $0; try? context.save() }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .frame(width: Theme.Size.control, alignment: .center)

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
            .frame(width: Theme.Size.iconButton)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(hoveredRow == expense.id ? Color.ftSurfaceAlt : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onHover { if $0 { hoveredRow = expense.id } }
    }

    // MARK: - Breakdown

    private var breakdown: some View {
        HStack(alignment: .top, spacing: Theme.gap) {
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
                .frame(maxHeight: .infinity)
            }
            .fillsHeight(minimum: 260)

            CardSection("By category") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                    GridRow {
                        Text("Category")
                        Text("Per month").gridColumnAlignment(.trailing)
                        Text("Share").gridColumnAlignment(.trailing)
                    }
                    .font(.tableHeader)
                    .tracking(Theme.tableHeaderTracking)
                    .foregroundStyle(Color.ftInkSecondary)

                    Divider().gridCellUnsizedAxes(.horizontal)

                    ForEach(metrics.byCategory) { slice in
                        GridRow {
                            HStack(spacing: 9) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(colour(for: slice))
                                    .frame(width: Theme.Size.dot, height: Theme.Size.dot)
                                Text(slice.name).font(.system(size: 12.5))
                            }
                            DerivedText(text: Money.currency(slice.monthlyAmount, decimals: 2))
                            DerivedText(text: Money.percent(slice.share))
                        }
                    }
                }
                // Pushes the card's spare height below the rows, so this card
                // matches the chart beside it instead of stopping short.
                Spacer(minLength: 0)
            }
            .fillsHeight(minimum: 260)
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
            DialogHeader(title: "Expense Categories",
                         subtitle: "Group your commitments. A category still in use can't be deleted.") {
                showingCategories = false
            }

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                        categoryRow(category)
                        if index < categories.count - 1 || draftCategory != nil {
                            Divider().padding(.leading, 20)
                        }
                    }
                    if draftCategory != nil { draftCategoryRow }
                }
            }
            .frame(height: 300)
            .background(Color.ftSurface)

            Divider()

            HStack(spacing: 8) {
                Button {
                    addCategory()
                } label: {
                    Image(systemName: "plus").frame(width: Theme.Size.iconButton)
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
        .frame(width: Theme.Size.sheetNarrow)
        .background(Color.ftCanvas)
    }

    private func categoryRow(_ category: ExpenseCategory) -> some View {
        let inUse = ExpenseService.expensesUsing(category, expenses: expenses)
        return HStack(spacing: 12) {
            ColorPicker("", selection: Binding(
                get: { Color(hex: category.colorHex) },
                set: { category.colorHex = $0.hexString; try? context.save() }))
                .labelsHidden()

            NameField(name: category.name) { newValue in
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

    /// Opens a row to fill in rather than inserting one called "New category".
    /// A placeholder is indistinguishable from a real category and is left
    /// behind whenever the button is pressed by accident.
    private func addCategory() {
        let palette = Theme.accountPalette
        draftCategory = DraftExpenseCategory(
            colorHex: palette[categories.count % palette.count])
    }

    /// The same columns as a real row, so nothing shifts when it is created.
    private var draftCategoryRow: some View {
        HStack(spacing: 12) {
            ColorPicker("", selection: Binding(
                get: { Color(hex: draftCategory?.colorHex ?? Theme.accountPalette[0]) },
                set: { draftCategory?.colorHex = $0.hexString }))
                .labelsHidden()

            TextField("Name", text: Binding(
                get: { draftCategory?.name ?? "" },
                set: { draftCategory?.name = $0 }))
                .textFieldStyle(.roundedBorder)
                .frame(width: Theme.Size.name)
                .focused($draftCategoryFocused)
                .onSubmit(commitDraftCategory)
                .onAppear { draftCategoryFocused = true }

            Spacer(minLength: 8)

            Button("Add", action: commitDraftCategory)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled((draftCategory?.name ?? "")
                    .trimmingCharacters(in: .whitespaces).isEmpty)

            Button("Cancel") { draftCategory = nil }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.ftSurfaceAlt)
    }

    private func commitDraftCategory() {
        guard let draft = draftCategory else { return }
        do {
            try ExpenseService.createCategory(name: draft.name,
                                              colorHex: draft.colorHex,
                                              in: context)
            draftCategory = nil
        } catch {
            // Kept open with what was typed, so a clash can be corrected.
            errorMessage = error.localizedDescription
        }
    }
}
