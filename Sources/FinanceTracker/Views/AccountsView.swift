import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var records: [BalanceRecord]

    @State private var showingNewAccount = false
    @State private var newName = ""
    @State private var newKind: AccountKind = .savings
    @State private var newColor = Color.blue
    @State private var errorMessage: String?
    @State private var pendingDeletion: Account?

    private var active: [Account] { accounts.filter { !$0.isArchived } }
    private var archived: [Account] { accounts.filter(\.isArchived) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Changes here re-derive every screen immediately.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("New Account", systemImage: "plus") { showingNewAccount = true }
                }

                ForEach(active) { account in
                    accountCard(account)
                }

                if !archived.isEmpty {
                    CardSection("Archived", subtitle: "Still counted in past records.") {
                        VStack(spacing: 8) {
                            ForEach(archived) { account in
                                HStack {
                                    Circle().fill(Color(hex: account.colorHex))
                                        .frame(width: 10, height: 10)
                                    Text(account.name)
                                    Spacer()
                                    Button("Restore") {
                                        AccountService.restore(account, in: context)
                                    }
                                    Button("Delete…", role: .destructive) {
                                        pendingDeletion = account
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showingNewAccount) { newAccountSheet }
        .alert("Couldn't do that",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            deletionPrompt,
            isPresented: Binding(get: { pendingDeletion != nil },
                                 set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
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

    private func accountCard(_ account: Account) -> some View {
        CardSection(account.name, subtitle: account.kind.displayName) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Name", text: Binding(
                        get: { account.name },
                        set: { newValue in
                            do { try AccountService.rename(account, to: newValue, in: context) }
                            catch { errorMessage = error.localizedDescription }
                        }))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: account.colorHex) },
                        set: { account.colorHex = $0.hexString; try? context.save() }))
                        .labelsHidden()
                    Spacer()
                    Button("Archive") {
                        do { try AccountService.archive(account, in: context) }
                        catch { errorMessage = error.localizedDescription }
                    }
                }

                Toggle("Counts toward Usable Cash", isOn: Binding(
                    get: { account.includeInUsable },
                    set: { account.includeInUsable = $0; try? context.save() }))
                Toggle("Counts toward Savings Rate", isOn: Binding(
                    get: { account.countsAsSavings },
                    set: { account.countsAsSavings = $0; try? context.save() }))
                Toggle("Receives the monthly leftover in projections", isOn: Binding(
                    get: { account.isLeftoverDestination },
                    set: { isOn in
                        AccountService.setLeftoverDestination(isOn ? account : nil,
                                                              accounts: accounts)
                        try? context.save()
                    }))

                HStack(spacing: 24) {
                    LabeledContent("Monthly contribution") {
                        TextField("", value: Binding(
                            get: { account.monthlyContribution },
                            set: { account.monthlyContribution = $0; try? context.save() }),
                            format: .number.precision(.fractionLength(0)))
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                    LabeledContent("Expected annual return %") {
                        TextField("", value: Binding(
                            get: { account.expectedAnnualReturn * 100 },
                            set: { account.expectedAnnualReturn = $0 / 100; try? context.save() }),
                            format: .number.precision(.fractionLength(2)))
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                }
                .font(.callout)
            }
        }
    }

    private var newAccountSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Account").font(.title3.weight(.semibold))
            Form {
                TextField("Name", text: $newName)
                Picker("Type", selection: $newKind) {
                    ForEach(AccountKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                ColorPicker("Colour", selection: $newColor)
            }
            Text(kindExplanation)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { resetSheet() }
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var kindExplanation: String {
        switch newKind {
        case .main: "Counts toward Usable Cash. Not treated as savings."
        case .savings: "Counts toward Usable Cash and toward your Savings Rate."
        case .investment: "Counts toward Usable Cash and toward your Savings Rate. Set an expected return."
        case .restricted: "Excluded from Usable Cash — for food cards and similar."
        }
    }

    private func create() {
        do {
            _ = try AccountService.create(name: newName, kind: newKind,
                                          colorHex: newColor.hexString, in: context)
            resetSheet()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetSheet() {
        newName = ""
        newKind = .savings
        newColor = .blue
        showingNewAccount = false
    }
}
