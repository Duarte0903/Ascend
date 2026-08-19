import SwiftUI
import SwiftData
import AppKit

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var records: [BalanceRecord]
    @Query(sort: \Expense.sortOrder) private var expenseItems: [Expense]
    @Query(sort: \AccountCategory.sortOrder) private var categories: [AccountCategory]

    @State private var showingNewAccount = false
    @State private var newName = ""
    @State private var newNote = ""
    @State private var newCategoryID: UUID?
    @State private var newColor = Color(hex: Theme.accountPalette[0])
    @State private var errorMessage: String?
    @State private var pendingDeletion: Account?

    @State private var showingTypes = false
    @State private var iconPickerFor: UUID?

    private var active: [Account] { accounts.filter { !$0.isArchived } }
    private var archived: [Account] { accounts.filter(\.isArchived) }

    private var latest: DerivedRecord? {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records,
            settings: SeedData.settings(in: context),
            expenses: expenseItems)).last
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                Callout(text: "Changes here re-derive every screen immediately. Archiving keeps an account's history intact; deleting rewrites it.")

                ForEach(active) { account in
                    accountCard(account)
                }

                if !archived.isEmpty { archivedCard }
            }
            .padding(Theme.screenPadding)
        }
        .toolbar {
            Button("Account Types…", systemImage: "tag") { showingTypes = true }
                .help("Create and edit the types accounts can have")
                .popover(isPresented: $showingTypes, arrowEdge: .bottom) {
                    typeManagerSheet
                }
            Button("New Account", systemImage: "plus") { showingNewAccount = true }
        }
        // New Account stays modal: it holds text you typed, and dismissing a
        // half-filled form on a stray click would throw that away.
        .sheet(isPresented: $showingNewAccount) { newAccountSheet }
        .alert("Couldn't do that",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(deletionPrompt,
                            isPresented: Binding(get: { pendingDeletion != nil },
                                                 set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) {
                if let account = pendingDeletion {
                    AccountService.delete(account, records: records, in: context)
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        }
    }

    private var deletionPrompt: String {
        guard let account = pendingDeletion else { return "" }
        let count = AccountService.affectedRecordCount(for: account, records: records)
        return "Deleting \(account.name) will change the totals of \(count) historical record\(count == 1 ? "" : "s"). Archiving keeps them intact instead."
    }

    // MARK: - Account card

    // MARK: - Account types dialog

    private var typeManagerSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            DialogHeader(title: "Account Types",
                         subtitle: "A type sets the defaults a new account starts with. Changing one never alters accounts that already exist.") {
                showingTypes = false
            }

            typeTableHeader

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                        typeRow(category)
                        if index < categories.count - 1 {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
            .frame(height: 232)
            .background(Color.ftSurface)

            Divider()

            HStack(spacing: 8) {
                Button {
                    addType()
                } label: {
                    Image(systemName: "plus").frame(width: Theme.Size.iconButton)
                }
                .buttonStyle(.borderless)
                .help("Add a type")

                Text(footerHint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ftInkTertiary)

                Spacer()

                Button("Done") { showingTypes = false }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: Theme.Size.sheetWide)
        .background(Color.ftCanvas)
    }

    private var footerHint: String {
        let unused = categories.filter {
            AccountService.accountsUsing($0, accounts: accounts) == 0
        }.count
        if categories.count == 1 { return "Your last type can't be deleted." }
        return unused == 0
            ? "Every type is in use."
            : "\(unused) type\(unused == 1 ? "" : "s") unused and safe to delete."
    }

    private var typeTableHeader: some View {
        HStack(spacing: 12) {
            Text("Name").frame(width: Theme.Size.name, alignment: .leading)
            Text("Usable").frame(width: Theme.Size.control)
            Text("Savings").frame(width: Theme.Size.control)
            Text("Return").frame(width: Theme.Size.fieldSmall, alignment: .trailing)
            Text("Used by").frame(width: Theme.Size.control, alignment: .trailing)
            Spacer(minLength: 0)
        }
        .font(.tableHeader)
        .tracking(Theme.tableHeaderTracking)
        .foregroundStyle(Color.ftInkSecondary)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func typeRow(_ category: AccountCategory) -> some View {
        let inUse = AccountService.accountsUsing(category, accounts: accounts)
        return HStack(spacing: 12) {
            NameField(name: category.name) { newValue in
                do { try AccountService.renameCategory(category, to: newValue, in: context) }
                catch { errorMessage = error.localizedDescription }
            }

            Toggle("", isOn: Binding(
                get: { category.defaultIncludeInUsable },
                set: { category.defaultIncludeInUsable = $0; try? context.save() }))
                .labelsHidden()
                .frame(width: Theme.Size.control)

            Toggle("", isOn: Binding(
                get: { category.defaultCountsAsSavings },
                set: { category.defaultCountsAsSavings = $0; try? context.save() }))
                .labelsHidden()
                .frame(width: Theme.Size.control)

            MoneyField(value: Binding(
                get: { category.defaultAnnualReturn * 100 },
                set: { category.defaultAnnualReturn = $0 / 100; try? context.save() }),
                decimals: 2, width: Theme.Size.fieldSmall, suffix: "%")

            Text(inUse == 0 ? "—" : "\(inUse)")
                .font(.figure(12.5))
                .monospacedDigit()
                .foregroundStyle(inUse == 0 ? Color.ftInkTertiary : Color.ftInkSecondary)
                .frame(width: Theme.Size.control, alignment: .trailing)

            Button {
                do {
                    try AccountService.deleteCategory(category, accounts: accounts, in: context)
                } catch {
                    errorMessage = error.localizedDescription
                }
            } label: {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(inUse > 0 || categories.count == 1)
            .help(inUse > 0
                  ? "\(inUse) account\(inUse == 1 ? "" : "s") use this type — move them first"
                  : "Delete this type")

            Spacer(minLength: 0)
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    /// Adds a type immediately with a free name, ready to be renamed in place —
    /// no second dialog stacked on top of this one.
    private func addType() {
        let existing = Set(categories.map { $0.name.lowercased() })
        var name = "New type"
        var suffix = 2
        while existing.contains(name.lowercased()) {
            name = "New type \(suffix)"
            suffix += 1
        }
        do {
            _ = try AccountService.createCategory(
                name: name, includeInUsable: true, countsAsSavings: false, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func accountCard(_ account: Account) -> some View {
        HStack(spacing: 0) {
            // Stripe is a plain rectangle clipped by the card, so its corners
            // follow the card's radius instead of pinching into a sliver.
            Rectangle()
                .fill(Color(hex: account.colorHex))
                .frame(width: Theme.Size.stripe)

            VStack(alignment: .leading, spacing: 0) {
                identityRow(account)
                Divider().padding(.vertical, 13)
                settingsRow(account)
                Divider().padding(.vertical, 11)
                footerRow(account)
            }
            .padding(Theme.cardPadding)
        }
        .background(Color.ftSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Color.ftHairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.055), radius: 12, y: 4)
    }

    /// Click to choose an image, or drop one straight onto it. With no custom
    /// image the account shows a symbol derived from its flags.
    private func iconPicker(_ account: Account) -> some View {
        // A plain button rather than a Menu: a borderless menu pads its label,
        // which made this icon a different size from the same icon elsewhere.
        Button { iconPickerFor = account.id } label: {
            AccountIcon(account, size: Theme.Size.iconLarge)
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(
            get: { iconPickerFor == account.id },
            set: { if !$0 && iconPickerFor == account.id { iconPickerFor = nil } }),
            arrowEdge: .bottom) {
            iconPickerPopover(account)
        }
        .contextMenu {
            Button("Choose Image…") { chooseIcon(for: account) }
            if account.iconData != nil {
                Button("Remove Image") {
                    AccountService.clearIcon(for: account, in: context)
                }
            }
        }
        .help(account.iconData == nil
              ? "Click to pick an image, or drop one here"
              : "Click to change this account's image")
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            let accepted = AccountService.setIcon(fromFileAt: url, for: account, in: context)
            if !accepted {
                errorMessage = "That file isn't an image Ascend can read. Try a PNG or JPEG."
            }
            return accepted
        }
    }

    private func iconPickerPopover(_ account: Account) -> some View {
        let library = AccountService.iconLibrary(accounts: accounts)
        return VStack(alignment: .leading, spacing: 12) {
            if library.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Text("No images loaded yet")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer(minLength: 0)
                    CloseButton { iconPickerFor = nil }
                }
                Text("Choose one and it will be offered here for your other accounts.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ftInkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 240, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Text("Already loaded")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer(minLength: 0)
                    CloseButton { iconPickerFor = nil }
                }
                Text("Accounts at the same bank can share one image.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ftInkTertiary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.Size.iconLarge + 10),
                                             spacing: 10)], spacing: 10) {
                    ForEach(library) { stored in
                        Button {
                            AccountService.reuseIcon(stored.data, for: account, in: context)
                            iconPickerFor = nil
                        } label: {
                            AccountIcon(iconData: stored.data,
                                        colorHex: account.colorHex,
                                        includeInUsable: account.includeInUsable,
                                        countsAsSavings: account.countsAsSavings,
                                        expectedAnnualReturn: account.expectedAnnualReturn,
                                        size: Theme.Size.iconLarge)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Size.iconLarge * 0.26,
                                                     style: .continuous)
                                        .strokeBorder(Color.ftAccent,
                                                      lineWidth: account.iconData == stored.data ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                        .help("Used by \(stored.usedBy.joined(separator: ", "))")
                    }
                }
                .frame(width: 260, alignment: .leading)
            }

            Divider()

            HStack {
                Button("Choose Image…") {
                    iconPickerFor = nil
                    chooseIcon(for: account)
                }
                Spacer()
                if account.iconData != nil {
                    Button("Remove", role: .destructive) {
                        AccountService.clearIcon(for: account, in: context)
                        iconPickerFor = nil
                    }
                }
            }
        }
        .padding(16)
    }

    private func chooseIcon(for account: Account) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !AccountService.setIcon(fromFileAt: url, for: account, in: context) {
            errorMessage = "That file isn't an image Ascend can read. Try a PNG or JPEG."
        }
    }

    private func category(for account: Account) -> AccountCategory? {
        categories.first { $0.id == account.categoryID }
    }

    /// Who the account is, and what it's worth. Nothing else competes here.
    private func identityRow(_ account: Account) -> some View {
        HStack(alignment: .top, spacing: 12) {
            iconPicker(account)

            VStack(alignment: .leading, spacing: 7) {
                NameField(name: account.name) { newValue in
                    do { try AccountService.rename(account, to: newValue, in: context) }
                    catch { errorMessage = error.localizedDescription }
                }

                HStack(spacing: 6) {
                    Picker("", selection: Binding(
                        get: { account.categoryID },
                        set: { newID in
                            AccountService.assign(account,
                                                  to: categories.first { $0.id == newID },
                                                  in: context)
                        })) {
                        ForEach(categories) { option in
                            Text(option.name).tag(Optional(option.id))
                        }
                        if account.categoryID == nil || category(for: account) == nil {
                            Text("No type").tag(Optional<UUID>.none)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()

                    if account.isLeftoverDestination {
                        Chip(text: "Receives leftover", highlighted: true)
                    }
                }
                .padding(.leading, 2)

                DescriptionField(note: account.note) { newValue in
                    account.note = newValue
                    try? context.save()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 1) {
                Eyebrow("Current balance")
                Text(Money.currency(latest?.amount(for: account.id)))
                    .font(.figure(20))
                    .monospacedDigit()
                    .foregroundStyle(Color.ftInk)
            }
        }
    }

    /// Two labelled groups. Each is its own Grid, so switches line up in one
    /// column and fields line up in another.
    private func settingsRow(_ account: Account) -> some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 9) {
                Eyebrow("Counts toward")
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                    switchRow("Usable cash", isOn: Binding(
                        get: { account.includeInUsable },
                        set: { account.includeInUsable = $0; try? context.save() }))
                    switchRow("Savings rate", isOn: Binding(
                        get: { account.countsAsSavings },
                        set: { account.countsAsSavings = $0; try? context.save() }))
                    switchRow("Monthly leftover", isOn: Binding(
                        get: { account.isLeftoverDestination },
                        set: { isOn in
                            AccountService.setLeftoverDestination(isOn ? account : nil,
                                                                  accounts: accounts)
                            try? context.save()
                        }))
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 9) {
                Eyebrow("Projections")
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                    GridRow {
                        Text("Monthly contribution")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.ftInkSecondary)
                        MoneyField(value: Binding(
                            get: { account.monthlyContribution },
                            set: { account.monthlyContribution = max(0, $0); try? context.save() }),
                            decimals: 2, width: Theme.Size.field, suffix: "€")
                            .gridColumnAlignment(.trailing)
                    }
                    GridRow {
                        Text("Expected annual return")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.ftInkSecondary)
                        MoneyField(value: Binding(
                            get: { account.expectedAnnualReturn * 100 },
                            set: { account.expectedAnnualReturn = $0 / 100; try? context.save() }),
                            decimals: 2, width: Theme.Size.field, suffix: "%")
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
        }
    }

    private func switchRow(_ label: String, isOn: Binding<Bool>) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.ftInkSecondary)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .gridColumnAlignment(.trailing)
        }
    }

    /// Reordering and destructive actions, kept away from the settings.
    private func footerRow(_ account: Account) -> some View {
        HStack(spacing: 10) {
            Button {
                AccountService.move(account, by: -1, accounts: accounts, in: context)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(!AccountService.canMove(account, by: -1, accounts: accounts))
            .help("Move earlier")

            Button {
                AccountService.move(account, by: 1, accounts: accounts, in: context)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(!AccountService.canMove(account, by: 1, accounts: accounts))
            .help("Move later")

            Text("Column order")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.ftInkTertiary)

            Spacer()

            ColorPicker("", selection: Binding(
                get: { Color(hex: account.colorHex) },
                set: { account.colorHex = $0.hexString; try? context.save() }))
                .labelsHidden()
                .help("Chart colour")

            Button("Archive") {
                do { try AccountService.archive(account, in: context) }
                catch { errorMessage = error.localizedDescription }
            }
            .controlSize(.small)
        }
    }

    private var archivedCard: some View {
        CardSection("Archived", subtitle: "Still counted in past records") {
            VStack(spacing: 10) {
                ForEach(archived) { account in
                    HStack(spacing: 10) {
                        AccountIcon(account, size: Theme.Size.iconMedium).opacity(0.6)
                        Text(account.name)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.ftInkSecondary)
                        if let date = account.archivedAt {
                            Text("archived \(date.formatted(.dateTime.day().month(.abbreviated).year()))")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.ftInkTertiary)
                        }
                        Spacer()
                        Button("Restore") { AccountService.restore(account, in: context) }
                            .controlSize(.small)
                        Button("Delete…", role: .destructive) { pendingDeletion = account }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - New account

    private var newAccountSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Text("New Account").font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
                CloseButton { resetSheet() }
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Name").font(.system(size: 12.5)).foregroundStyle(Color.ftInkSecondary)
                    TextField("e.g. Pension", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: Theme.Size.nameWide)
                }
                GridRow {
                    Text("Type").font(.system(size: 12.5)).foregroundStyle(Color.ftInkSecondary)
                    Picker("", selection: $newCategoryID) {
                        ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    .frame(width: Theme.Size.nameWide)
                }
                GridRow {
                    Text("Description").font(.system(size: 12.5))
                        .foregroundStyle(Color.ftInkSecondary)
                    TextField("What is this account for?", text: $newNote)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: Theme.Size.nameWide)
                }
                GridRow {
                    Text("Colour").font(.system(size: 12.5)).foregroundStyle(Color.ftInkSecondary)
                    HStack(spacing: 7) {
                        ForEach(Theme.accountPalette, id: \.self) { hex in
                            Button {
                                newColor = Color(hex: hex)
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: Theme.Size.iconButton - 4, height: Theme.Size.iconButton - 4)
                                    .overlay(Circle().strokeBorder(
                                        Color.ftInk.opacity(newColor.hexString == hex ? 0.55 : 0),
                                        lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Callout(text: kindExplanation)

            HStack {
                Spacer()
                Button("Cancel") { resetSheet() }
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: Theme.Size.sheetNarrow)
    }

    private var kindExplanation: String {
        guard let selected = categories.first(where: { $0.id == newCategoryID }) else {
            return "Pick a type to inherit its defaults, or set the flags yourself afterwards."
        }
        var parts: [String] = []
        parts.append(selected.defaultIncludeInUsable
            ? "Counts toward usable cash." : "Excluded from usable cash.")
        parts.append(selected.defaultCountsAsSavings
            ? "Counts toward your savings rate." : "Not treated as savings.")
        if selected.defaultAnnualReturn != 0 {
            parts.append("Starts at \(Money.percent(selected.defaultAnnualReturn)) expected annual return.")
        }
        return parts.joined(separator: " ")
    }

    private func create() {
        do {
            _ = try AccountService.create(
                name: newName,
                category: categories.first { $0.id == newCategoryID },
                colorHex: newColor.hexString,
                note: newNote,
                in: context)
            resetSheet()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetSheet() {
        newName = ""
        newNote = ""
        newCategoryID = categories.first?.id
        newColor = Color(hex: Theme.accountPalette[0])
        showingNewAccount = false
    }
}

/// A small state label — account type, or a role the account plays.
struct Chip: View {
    let text: String
    var highlighted = false

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(highlighted ? Color.ftAccent : Color.ftInkSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(highlighted ? Color.ftAccent.opacity(0.13) : Color.ftSurfaceAlt,
                        in: Capsule())
            .overlay(Capsule().strokeBorder(
                highlighted ? .clear : Color.ftHairline, lineWidth: 1))
    }
}
