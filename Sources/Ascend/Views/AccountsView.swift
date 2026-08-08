import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var records: [BalanceRecord]
    @Query(sort: \AccountCategory.sortOrder) private var categories: [AccountCategory]

    @State private var showingNewAccount = false
    @State private var newName = ""
    @State private var newNote = ""
    @State private var newCategoryID: UUID?
    @State private var newColor = Color(hex: Theme.accountPalette[0])
    @State private var errorMessage: String?
    @State private var pendingDeletion: Account?

    @State private var showingTypes = false

    private var active: [Account] { accounts.filter { !$0.isArchived } }
    private var archived: [Account] { accounts.filter(\.isArchived) }

    private var latest: DerivedRecord? {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records,
            settings: SeedData.settings(in: context))).last
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
            Button("New Account", systemImage: "plus") { showingNewAccount = true }
        }
        .sheet(isPresented: $showingNewAccount) { newAccountSheet }
        .sheet(isPresented: $showingTypes) { typeManagerSheet }
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
            VStack(alignment: .leading, spacing: 3) {
                Text("Account Types").font(.system(size: 17, weight: .semibold))
                Text("A type sets the defaults a new account starts with. Changing one never alters accounts that already exist.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ftInkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

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
                    Image(systemName: "plus").frame(width: 18)
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
        .frame(width: 620)
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
            Text("Name").frame(width: 176, alignment: .leading)
            Text("Usable").frame(width: 54)
            Text("Savings").frame(width: 58)
            Text("Return").frame(width: 86, alignment: .trailing)
            Text("Used by").frame(width: 74, alignment: .trailing)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .tracking(0.5)
        .foregroundStyle(Color.ftInkTertiary)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func typeRow(_ category: AccountCategory) -> some View {
        let inUse = AccountService.accountsUsing(category, accounts: accounts)
        return HStack(spacing: 12) {
            NameField(name: category.name, width: 176) { newValue in
                do { try AccountService.renameCategory(category, to: newValue, in: context) }
                catch { errorMessage = error.localizedDescription }
            }

            Toggle("", isOn: Binding(
                get: { category.defaultIncludeInUsable },
                set: { category.defaultIncludeInUsable = $0; try? context.save() }))
                .labelsHidden()
                .frame(width: 54)

            Toggle("", isOn: Binding(
                get: { category.defaultCountsAsSavings },
                set: { category.defaultCountsAsSavings = $0; try? context.save() }))
                .labelsHidden()
                .frame(width: 58)

            MoneyField(value: Binding(
                get: { category.defaultAnnualReturn * 100 },
                set: { category.defaultAnnualReturn = $0 / 100; try? context.save() }),
                decimals: 2, width: 86, suffix: "%")

            Text(inUse == 0 ? "—" : "\(inUse)")
                .font(.figure(12.5))
                .monospacedDigit()
                .foregroundStyle(inUse == 0 ? Color.ftInkTertiary : Color.ftInkSecondary)
                .frame(width: 74, alignment: .trailing)

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
                .frame(width: 4)

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

    private func category(for account: Account) -> AccountCategory? {
        categories.first { $0.id == account.categoryID }
    }

    /// Who the account is, and what it's worth. Nothing else competes here.
    private func identityRow(_ account: Account) -> some View {
        HStack(alignment: .top, spacing: 12) {
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

            Spacer(minLength: 16)

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
                            decimals: 0, width: 96, suffix: "€")
                            .gridColumnAlignment(.trailing)
                    }
                    GridRow {
                        Text("Expected annual return")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.ftInkSecondary)
                        MoneyField(value: Binding(
                            get: { account.expectedAnnualReturn * 100 },
                            set: { account.expectedAnnualReturn = $0 / 100; try? context.save() }),
                            decimals: 2, width: 96, suffix: "%")
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
                        Circle().fill(Color(hex: account.colorHex).opacity(0.5))
                            .frame(width: 9, height: 9)
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
            Text("New Account").font(.system(size: 17, weight: .semibold))

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Name").font(.system(size: 12.5)).foregroundStyle(Color.ftInkSecondary)
                    TextField("e.g. Trade Republic", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                GridRow {
                    Text("Type").font(.system(size: 12.5)).foregroundStyle(Color.ftInkSecondary)
                    Picker("", selection: $newCategoryID) {
                        ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                }
                GridRow {
                    Text("Description").font(.system(size: 12.5))
                        .foregroundStyle(Color.ftInkSecondary)
                    TextField("What is this account for?", text: $newNote)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
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
                                    .frame(width: 20, height: 20)
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
        .frame(width: 460)
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
