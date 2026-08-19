import SwiftUI
import SwiftData
import AppKit

/// Everything about the open profile: who or what it is, how it looks, what it
/// holds. Switching and creating profiles stay in the sidebar switcher.
struct ProfileView: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]
    @Query(sort: \Expense.sortOrder) private var expenseItems: [Expense]

    @State private var errorMessage: String?

    private var active: Profile { profiles.registry.active }

    private var netWorth: Double? {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records,
            settings: SeedData.settings(in: context),
            expenses: expenseItems)).last?.total
    }

    var body: some View {
        FillingScreen {
            identity
            statistics
            // Fixed vertically so the row is only as tall as the taller card:
            // both stretch to match it, without also swallowing the leftover
            // height of the screen.
            HStack(alignment: .top, spacing: Theme.gap) {
                appearance
                preferences
            }
            .fixedSize(horizontal: false, vertical: true)
            details.fillsHeight(minimum: 260)
        }
        .alert("Couldn't do that",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Identity

    private var identity: some View {
        CardSection("Identity", subtitle: "The name and picture this profile is known by") {
            // The setter is written out rather than passed as `set: changeKind`:
            // a bare method reference there matches Binding's two-argument
            // setter overload and crashes the compiler in IRGen (Swift 6.3.3).
            Picker("", selection: Binding(get: { active.kind },
                                          set: { changeKind($0) })) {
                ForEach(ProfileKind.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 210)
        } content: {
            HStack(alignment: .top, spacing: 18) {
                avatarButton

                VStack(alignment: .leading, spacing: 12) {
                    labelled("Name") {
                        NameField(name: active.name, width: nil) { newName in
                            profiles.rename(active.id, to: newName)
                        }
                    }
                    labelled("What these books are for") {
                        DescriptionField(note: active.note, width: nil) { newNote in
                            profiles.update(active.id) { $0.note = newNote }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Switching kind also moves the symbol onto the new palette, so it can't
    /// be left selected but absent from the choices shown.
    private func changeKind(_ kind: ProfileKind) {
        profiles.update(active.id) { profile in
            profile.kind = kind
            if !kind.symbols.contains(profile.symbol) {
                profile.symbol = kind.defaultSymbol
            }
        }
    }

    private var avatarButton: some View {
        VStack(spacing: 6) {
            Button(action: chooseImage) {
                ProfileBadge(profile: active, size: Theme.Size.avatar)
                    .overlay(Circle().strokeBorder(Color.ftHairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(active.imageData == nil
                  ? "Click to pick a picture, or drop one here"
                  : "Click to change this profile's picture")
            .contextMenu {
                Button("Choose Picture…") { chooseImage() }
                if active.imageData != nil {
                    Button("Remove Picture") { profiles.clearImage(for: active.id) }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                let accepted = profiles.setImage(fromFileAt: url, for: active.id)
                if !accepted {
                    errorMessage = "That file isn't an image Ascend can read. Try a PNG or JPEG."
                }
                return accepted
            }

            if active.imageData != nil {
                Button("Remove") { profiles.clearImage(for: active.id) }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
        }
        .frame(width: Theme.Size.avatar)
    }

    // MARK: - Details

    /// Which questions are worth asking depends on whether these books belong
    /// to somebody or to something.
    ///
    /// A two-column table rather than a flowing grid: one field per row, so a
    /// new field is one more row and never leaves a ragged gap. `Grid` sizes
    /// the label column to the longest label on its own, and a bare `Divider`
    /// between rows spans both columns.
    private var details: some View {
        CardSection(active.kind.detailsTitle, subtitle: active.kind.detailsSubtitle) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 11) {
                if active.kind == .person {
                    row("Owner") {
                        editable(active.ownerName) { value in
                            profiles.update(active.id) { $0.ownerName = value }
                        }
                    }
                    Divider()
                    row("Occupation") {
                        editable(active.occupation) { value in
                            profiles.update(active.id) { $0.occupation = value }
                        }
                    }
                    Divider()
                    row("Employer") {
                        editable(active.employer) { value in
                            profiles.update(active.id) { $0.employer = value }
                        }
                    }
                    Divider()
                    row("Employment") { employmentPicker }
                } else {
                    row("Legal name") {
                        editable(active.legalName) { value in
                            profiles.update(active.id) { $0.legalName = value }
                        }
                    }
                    Divider()
                    row("Industry") {
                        editable(active.industry) { value in
                            profiles.update(active.id) { $0.industry = value }
                        }
                    }
                    Divider()
                    row("Company number") {
                        editable(active.registrationNumber) { value in
                            profiles.update(active.id) { $0.registrationNumber = value }
                        }
                    }
                    Divider()
                    row("Contact") {
                        editable(active.ownerName) { value in
                            profiles.update(active.id) { $0.ownerName = value }
                        }
                    }
                }
                Divider()
                row("Location") {
                    editable(active.location) { value in
                        profiles.update(active.id) { $0.location = value }
                    }
                }
                Divider()
                row(active.kind.inceptionLabel) { inceptionControl }
            }
        }
    }

    /// One table row. The modifiers go on each cell rather than the `GridRow`,
    /// because a `GridRow` applies what it is given to every cell separately.
    private func row<Content: View>(_ title: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.ftInkSecondary)
                .gridColumnAlignment(.leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The editable cell every text row uses, so they are all the same shape.
    private func editable(_ value: String,
                          onCommit: @escaping (String) -> Void) -> some View {
        NameField(name: value, width: Theme.Size.detailValue, onCommit: onCommit)
    }

    private var employmentPicker: some View {
        Picker("", selection: Binding(
            get: { active.employmentStatus },
            set: { status in profiles.update(active.id) { $0.employmentStatus = status } })) {
            ForEach(EmploymentStatus.allCases) { Text($0.label).tag($0) }
        }
        .labelsHidden()
        .frame(width: Theme.Size.detailValue, alignment: .leading)
    }

    /// Optional, so it is a button until there is a date. A date picker sitting
    /// on today would read as a real answer.
    private var inceptionControl: some View {
        Group {
            if let date = active.inceptionDate {
                // Laid out along the row rather than stacked, so this row is
                // the same height as every other one.
                HStack(spacing: 10) {
                    DatePicker("", selection: Binding(
                        get: { date },
                        set: { newDate in
                            profiles.update(active.id) { $0.inceptionDate = newDate }
                        }),
                               displayedComponents: .date)
                        .labelsHidden()
                    if let caption = active.ageCaption() {
                        Text(caption)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ftInkTertiary)
                    }
                    Button("Clear") {
                        profiles.update(active.id) { $0.inceptionDate = nil }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
            } else {
                Button("Set \(active.kind.inceptionLabel.lowercased())") {
                    profiles.update(active.id) { $0.inceptionDate = Self.defaultInception }
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Somewhere plausible to start scrolling from, rather than today.
    private static var defaultInception: Date {
        Calendar(identifier: .gregorian)
            .date(byAdding: .year, value: -30, to: Date()) ?? Date()
    }

    // MARK: - Appearance and preferences

    private var appearance: some View {
        CardSection("Appearance",
                    subtitle: "Used when no picture is set, and behind one that is") {
            ProfileAppearancePicker(
                colorHex: Binding(get: { active.colorHex },
                                  set: { hex in profiles.update(active.id) { $0.colorHex = hex } }),
                symbol: Binding(get: { active.symbol },
                                set: { symbol in
                                    profiles.update(active.id) { $0.symbol = symbol }
                                }),
                kind: active.kind)
        }
        .fillingHeight()
    }

    private var preferences: some View {
        CardSection("Preferences", subtitle: "How money is shown in this profile") {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Currency")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6,
                                             alignment: .leading)],
                          alignment: .leading, spacing: 6) {
                    ForEach(Money.commonSymbols, id: \.self) { option in
                        currencyChip(option)
                    }
                }
                Text("Every figure in this profile is shown with this symbol.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ftInkTertiary)
            }
        }
        .fillingHeight()
    }

    private func currencyChip(_ option: String) -> some View {
        let isSelected = active.currencySymbol == option
        return Button {
            profiles.update(active.id) { $0.currencySymbol = option }
        } label: {
            Text(option)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : Color.ftInkSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.ftAccent : Color.ftSurfaceAlt, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? .clear : Color.ftHairline,
                                                lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Statistics

    private var statistics: some View {
        HStack(spacing: Theme.gap) {
            MetricTile(title: "Net worth", value: Money.currency(netWorth),
                       caption: records.isEmpty ? "No records yet" : "Latest record")
            MetricTile(title: "Accounts", value: "\(accounts.count)",
                       caption: accounts.isEmpty ? "None yet" : "\(expenseItems.count) expenses")
            MetricTile(title: "Records", value: "\(records.count)",
                       caption: firstRecordCaption)
            MetricTile(title: "Created", value: Self.shortDate(active.createdAt),
                       caption: "Opened \(Self.shortDate(active.lastOpenedAt))")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var firstRecordCaption: String {
        guard let first = records.first else { return "Nothing logged yet" }
        return "Since \(Self.shortDate(first.date))"
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    // MARK: - Shared field shapes

    private func field(_ title: String, value: String,
                       onCommit: @escaping (String) -> Void) -> some View {
        labelled(title) {
            NameField(name: value, width: nil, onCommit: onCommit)
        }
    }

    private func labelled<Content: View>(_ title: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Eyebrow(title)
            content()
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !profiles.setImage(fromFileAt: url, for: active.id) {
            errorMessage = "That file isn't an image Ascend can read. Try a PNG or JPEG."
        }
    }
}
