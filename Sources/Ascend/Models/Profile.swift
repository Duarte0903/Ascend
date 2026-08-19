import Foundation

/// Whether a profile's books belong to a person or to an organisation. It
/// changes which details are worth asking for, and nothing else — the accounts,
/// records and projections behave identically either way.
enum ProfileKind: String, CaseIterable, Identifiable, Codable {
    case person, organization

    var id: String { rawValue }

    var label: String {
        switch self {
        case .person: "Person"
        case .organization: "Organization"
        }
    }

    var defaultSymbol: String {
        switch self {
        case .person: "person.fill"
        case .organization: "building.2.fill"
        }
    }

    var detailsTitle: String {
        switch self {
        case .person: "Personal"
        case .organization: "Organisation"
        }
    }

    var detailsSubtitle: String {
        switch self {
        case .person: "Who these books belong to"
        case .organization: "The entity these books belong to"
        }
    }

    /// What to call the date the subject came into existence.
    var inceptionLabel: String {
        switch self {
        case .person: "Date of birth"
        case .organization: "Founded"
        }
    }

    var symbols: [String] {
        switch self {
        case .person:
            ["person.fill", "person.2.fill", "house.fill", "heart.fill", "leaf.fill",
             "star.fill", "graduationcap.fill", "pawprint.fill", "airplane", "bolt.fill"]
        case .organization:
            ["building.2.fill", "building.columns.fill", "briefcase.fill", "shippingbox.fill",
             "cart.fill", "globe", "gearshape.fill", "chart.pie.fill", "lightbulb.fill",
             "hammer.fill"]
        }
    }
}

/// How the owner earns. Kept as a closed list rather than free text so it can
/// be picked in one click, with `unspecified` meaning nobody has said.
enum EmploymentStatus: String, CaseIterable, Identifiable, Codable {
    case unspecified, employed, selfEmployed, businessOwner, student, retired, betweenRoles

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unspecified: "Not set"
        case .employed: "Employed"
        case .selfEmployed: "Self-employed"
        case .businessOwner: "Business owner"
        case .student: "Student"
        case .retired: "Retired"
        case .betweenRoles: "Between roles"
        }
    }
}


/// One person's books: their own accounts, records, expenses, goal and
/// settings, in their own store file.
///
/// Deliberately a plain value type rather than a SwiftData model. Profiles
/// cannot live inside a store, because the store is the thing a profile
/// selects — so the list of them is kept beside the stores as JSON.
struct Profile: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: ProfileKind
    var name: String
    var colorHex: String
    var symbol: String
    /// A custom picture, replacing the symbol when set. Downscaled to a
    /// thumbnail on the way in, the same as account images.
    var imageData: Data?
    /// What this set of books is for.
    var note: String
    /// Whose money it is. Blank for most people, useful once a profile is
    /// somebody else's.
    var ownerName: String
    /// What they do, who for, and how that work is arranged.
    var occupation: String
    var employer: String
    var employmentStatus: EmploymentStatus
    /// Optional. Its only job is to derive an age.
    var birthDate: Date?
    var location: String
    /// Organisations only: the registered name, what it does, its company
    /// number, and when it started trading.
    var legalName: String
    var industry: String
    var registrationNumber: String
    var foundedDate: Date?
    /// Every figure in the app is drawn with this. Per profile, so books kept
    /// in different countries read correctly.
    var currencySymbol: String
    /// Fixed at creation. Renaming a profile must never move its data.
    let fileName: String
    let createdAt: Date
    var lastOpenedAt: Date

    init(id: UUID = UUID(),
         kind: ProfileKind = .person,
         name: String,
         colorHex: String = "#1F6E8C",
         symbol: String = "person.fill",
         imageData: Data? = nil,
         note: String = "",
         ownerName: String = "",
         occupation: String = "",
         employer: String = "",
         employmentStatus: EmploymentStatus = .unspecified,
         birthDate: Date? = nil,
         location: String = "",
         legalName: String = "",
         industry: String = "",
         registrationNumber: String = "",
         foundedDate: Date? = nil,
         currencySymbol: String = Money.defaultSymbol,
         fileName: String? = nil,
         createdAt: Date = Date(),
         lastOpenedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.name = name
        self.colorHex = colorHex
        self.symbol = symbol
        self.imageData = imageData
        self.note = note
        self.ownerName = ownerName
        self.occupation = occupation
        self.employer = employer
        self.employmentStatus = employmentStatus
        self.birthDate = birthDate
        self.location = location
        self.legalName = legalName
        self.industry = industry
        self.registrationNumber = registrationNumber
        self.foundedDate = foundedDate
        self.currencySymbol = currencySymbol
        self.fileName = fileName ?? "\(id.uuidString).store"
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
    }

    /// Decoded field by field so a registry written before any of these
    /// existed still loads, rather than throwing and losing every profile.
    init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(UUID.self, forKey: .id)
        kind = try box.decodeIfPresent(ProfileKind.self, forKey: .kind) ?? .person
        name = try box.decode(String.self, forKey: .name)
        fileName = try box.decode(String.self, forKey: .fileName)
        colorHex = try box.decodeIfPresent(String.self, forKey: .colorHex) ?? "#1F6E8C"
        symbol = try box.decodeIfPresent(String.self, forKey: .symbol) ?? "person.fill"
        imageData = try box.decodeIfPresent(Data.self, forKey: .imageData)
        note = try box.decodeIfPresent(String.self, forKey: .note) ?? ""
        ownerName = try box.decodeIfPresent(String.self, forKey: .ownerName) ?? ""
        occupation = try box.decodeIfPresent(String.self, forKey: .occupation) ?? ""
        employer = try box.decodeIfPresent(String.self, forKey: .employer) ?? ""
        employmentStatus = try box.decodeIfPresent(EmploymentStatus.self,
                                                   forKey: .employmentStatus) ?? .unspecified
        birthDate = try box.decodeIfPresent(Date.self, forKey: .birthDate)
        location = try box.decodeIfPresent(String.self, forKey: .location) ?? ""
        legalName = try box.decodeIfPresent(String.self, forKey: .legalName) ?? ""
        industry = try box.decodeIfPresent(String.self, forKey: .industry) ?? ""
        registrationNumber = try box.decodeIfPresent(String.self,
                                                     forKey: .registrationNumber) ?? ""
        foundedDate = try box.decodeIfPresent(Date.self, forKey: .foundedDate)
        currencySymbol = try box.decodeIfPresent(String.self, forKey: .currencySymbol)
            ?? Money.defaultSymbol
        createdAt = try box.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastOpenedAt = try box.decodeIfPresent(Date.self, forKey: .lastOpenedAt) ?? Date()
    }

    /// The symbols offered for this profile's kind.
    var symbols: [String] { kind.symbols }
}

/// The list of profiles and which one is open.
///
/// Every operation is pure and total: there is always at least one profile and
/// `activeID` always names one of them, so no sequence of edits can leave the
/// app with nothing to open.
struct ProfileRegistry: Codable, Equatable {
    private(set) var profiles: [Profile]
    private(set) var activeID: UUID

    /// Falls back to the first profile rather than trapping, so a hand-edited
    /// or truncated registry file still opens.
    var active: Profile {
        profiles.first { $0.id == activeID } ?? profiles[0]
    }

    init(first: Profile) {
        profiles = [first]
        activeID = first.id
    }

    init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try box.decode([Profile].self, forKey: .profiles)
        // An empty list would make `active` unrepresentable; rebuild rather
        // than refuse to launch.
        profiles = decoded.isEmpty ? [Profile(name: "Personal")] : decoded
        let storedActive = try box.decode(UUID.self, forKey: .activeID)
        activeID = profiles.contains { $0.id == storedActive } ? storedActive : profiles[0].id
    }

    mutating func activate(_ id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        activeID = id
        profiles[index].lastOpenedAt = Date()
    }

    mutating func add(_ profile: Profile) {
        profiles.append(profile)
    }

    /// Ignores a blank name, so a cleared text field cannot leave a profile
    /// with no label at all.
    mutating func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = trimmed
    }

    mutating func setAppearance(_ id: UUID, colorHex: String, symbol: String) {
        update(id) { $0.colorHex = colorHex; $0.symbol = symbol }
    }

    /// The general editor. Everything except the name goes through here, so
    /// there is one place that knows how to find a profile and change it.
    mutating func update(_ id: UUID, _ transform: (inout Profile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        transform(&profiles[index])
    }

    /// Returns the removed profile so its store file can be cleaned up, or
    /// `nil` when the removal was refused. The last profile is never removed —
    /// an app with no profile has nothing to show.
    @discardableResult
    mutating func remove(_ id: UUID) -> Profile? {
        guard profiles.count > 1,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = profiles.remove(at: index)
        if activeID == removed.id {
            // Fall back to the neighbour, so deleting the open profile lands
            // somewhere predictable rather than always at the top.
            activate(profiles[max(0, index - 1)].id)
        }
        return removed
    }

    /// "Personal", then "Personal 2", "Personal 3"… Names are a label, not an
    /// identity, but two identically named profiles are impossible to tell
    /// apart in the switcher.
    func uniqueName(basedOn proposed: String) -> String {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Profile" : trimmed
        let taken = Set(profiles.map(\.name))
        guard taken.contains(base) else { return base }
        var suffix = 2
        while taken.contains("\(base) \(suffix)") { suffix += 1 }
        return "\(base) \(suffix)"
    }
}

extension Profile {
    /// When the subject came into existence: a birth date for a person, a
    /// founding date for an organisation.
    var inceptionDate: Date? {
        get { kind == .person ? birthDate : foundedDate }
        set { if kind == .person { birthDate = newValue } else { foundedDate = newValue } }
    }

    /// Whole years lived or traded, or `nil` when no date is set — and also
    /// when it is in the future, which is a typo rather than a negative age.
    func age(on date: Date = Date(),
             calendar: Calendar = Calendar(identifier: .gregorian)) -> Int? {
        guard let inceptionDate, inceptionDate <= date else { return nil }
        return calendar.dateComponents([.year], from: inceptionDate, to: date).year
    }

    /// How the derived age reads for this kind.
    func ageCaption(on date: Date = Date()) -> String? {
        guard let age = age(on: date) else { return nil }
        switch kind {
        case .person: return "\(age) years old"
        case .organization: return age == 1 ? "Trading 1 year" : "Trading \(age) years"
        }
    }

    /// The one-line summary shown under a profile's name in the switcher.
    var summary: String {
        var parts: [String] = []
        switch kind {
        case .person:
            if !occupation.isEmpty { parts.append(occupation) }
            if !employer.isEmpty { parts.append(employer) }
        case .organization:
            if !industry.isEmpty { parts.append(industry) }
            if !location.isEmpty { parts.append(location) }
        }
        if parts.isEmpty && !ownerName.isEmpty { parts.append(ownerName) }
        if parts.isEmpty && !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}
