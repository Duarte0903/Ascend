import SwiftUI

/// Creating a profile. Modal like New Account, and for the same reason: it
/// holds text you typed that nothing has saved yet.
struct NewProfileSheet: View {
    @Environment(ProfileStore.self) private var store
    @Binding var isPresented: Bool

    @State private var name = ""
    @State private var kind: ProfileKind = .person
    @State private var colorHex = Theme.accountPalette[0]
    @State private var symbol = ProfileKind.person.defaultSymbol
    @State private var content: NewProfileContent = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DialogHeader(title: "New Profile",
                         subtitle: "A profile is a separate set of books — its own accounts, records, expenses and goal. Nothing is shared between them.") {
                isPresented = false
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ProfileBadge(profile: preview, size: Theme.Size.iconLarge)
                    TextField("e.g. Personal", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(create)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Kind")
                    Picker("", selection: $kind) {
                        ForEach(ProfileKind.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _, new in
                        // The old symbol belongs to the other palette, so it
                        // would sit there selected but not shown.
                        symbol = new.defaultSymbol
                    }
                    Text(kind == .person
                         ? "Books for one person: occupation, employer, date of birth."
                         : "Books for a company or club: industry, company number, founding date.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.ftInkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Appearance")
                    ProfileAppearancePicker(colorHex: $colorHex, symbol: $symbol, kind: kind)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Start with")
                    Picker("", selection: $content) {
                        ForEach(NewProfileContent.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    Text(content.explanation)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.ftInkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button("Cancel") { isPresented = false }
                    Button("Create", action: create)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: Theme.Size.sheetNarrow)
        .background(Color.ftCanvas)
    }

    /// Lets the badge show the chosen colour and symbol before the profile
    /// exists.
    private var preview: Profile {
        Profile(kind: kind, name: name, colorHex: colorHex, symbol: symbol)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.create(kind: kind, name: trimmed, colorHex: colorHex,
                     symbol: symbol, content: content)
        isPresented = false
    }
}

/// Renaming, restyling and deleting. A popover, so clicking away closes it —
/// every edit here is committed as you make it.
struct ProfileManager: View {
    @Environment(ProfileStore.self) private var store
    @Binding var isPresented: Bool
    @Binding var showingNew: Bool

    @State private var pendingDeletion: Profile?
    @State private var expanded: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DialogHeader(title: "Profiles",
                         subtitle: "Deleting a profile deletes its accounts and its whole history. Export a backup first if you might want it back.") {
                isPresented = false
            }

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(store.registry.profiles.enumerated()), id: \.element.id) { index, profile in
                        row(profile)
                        if index < store.registry.profiles.count - 1 {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
            .frame(height: 260)
            .background(Color.ftSurface)

            Divider()

            HStack(spacing: 8) {
                Button {
                    isPresented = false
                    showingNew = true
                } label: {
                    Image(systemName: "plus").frame(width: Theme.Size.iconButton)
                }
                .buttonStyle(.borderless)
                .help("Add a profile")

                Text(store.canDelete
                     ? "The open profile is ticked."
                     : "Your only profile — add another before you can delete this one.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ftInkTertiary)

                Spacer()

                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: Theme.Size.sheetWide)
        .background(Color.ftCanvas)
        .confirmationDialog("Delete “\(pendingDeletion?.name ?? "")”?",
                            isPresented: Binding(get: { pendingDeletion != nil },
                                                 set: { if !$0 { pendingDeletion = nil } })) {
            Button("Delete Profile", role: .destructive) {
                if let pendingDeletion { store.delete(pendingDeletion.id) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Its accounts, records and expenses are removed for good. This can't be undone.")
        }
    }

    private func row(_ profile: Profile) -> some View {
        let isActive = profile.id == store.registry.activeID
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.ftAccent)
                    .opacity(isActive ? 1 : 0)
                    .frame(width: 14)

                ProfileBadge(profile: profile, size: Theme.Size.iconMedium + 6)

                NameField(name: profile.name, width: Theme.Size.name) { newName in
                    store.rename(profile.id, to: newName)
                }

                Spacer(minLength: 12)

                if !isActive {
                    Button("Open") { store.activate(profile.id) }
                        .controlSize(.small)
                }

                Button {
                    expanded = expanded == profile.id ? nil : profile.id
                } label: {
                    Image(systemName: "paintpalette")
                        .frame(width: Theme.Size.iconButton)
                }
                .buttonStyle(.borderless)
                .help("Change this profile's colour and symbol")

                Button {
                    pendingDeletion = profile
                } label: {
                    Image(systemName: "trash").frame(width: Theme.Size.iconButton)
                }
                .buttonStyle(.borderless)
                .disabled(!store.canDelete)
                .help(store.canDelete ? "Delete this profile"
                                      : "You can't delete your only profile")
            }

            if expanded == profile.id {
                ProfileAppearancePicker(
                    colorHex: Binding(get: { profile.colorHex },
                                      set: { store.setAppearance(profile.id, colorHex: $0,
                                                                 symbol: profile.symbol) }),
                    symbol: Binding(get: { profile.symbol },
                                    set: { store.setAppearance(profile.id,
                                                               colorHex: profile.colorHex,
                                                               symbol: $0) }),
                    kind: profile.kind)
                    .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
