import Foundation
import Testing
@testable import Ascend

@Suite("Profile registry")
struct ProfileRegistryTests {

    private func registry(_ names: String...) -> ProfileRegistry {
        var registry = ProfileRegistry(first: Profile(name: names[0]))
        for name in names.dropFirst() { registry.add(Profile(name: name)) }
        return registry
    }

    @Test("The first profile is the active one")
    func firstIsActive() {
        let registry = self.registry("Personal")
        #expect(registry.active.name == "Personal")
        #expect(registry.profiles.count == 1)
    }

    @Test("Renaming leaves the store file alone")
    func renameKeepsFile() {
        var registry = self.registry("Personal")
        let fileBefore = registry.active.fileName
        registry.rename(registry.activeID, to: "Household")
        #expect(registry.active.name == "Household")
        #expect(registry.active.fileName == fileBefore)
    }

    @Test("A blank rename is ignored rather than clearing the name")
    func blankRenameIgnored() {
        var registry = self.registry("Personal")
        registry.rename(registry.activeID, to: "   ")
        #expect(registry.active.name == "Personal")
    }

    @Test("Duplicate names are numbered so the switcher stays readable")
    func uniqueNames() {
        let registry = self.registry("Personal", "Personal 2")
        #expect(registry.uniqueName(basedOn: "Work") == "Work")
        #expect(registry.uniqueName(basedOn: "Personal") == "Personal 3")
        #expect(registry.uniqueName(basedOn: "  ") == "Profile")
    }

    @Test("The last profile can never be deleted")
    func lastProfileSurvives() {
        var registry = self.registry("Personal")
        #expect(registry.remove(registry.activeID) == nil)
        #expect(registry.profiles.count == 1)
    }

    @Test("Deleting the open profile falls back to its neighbour")
    func deletingActiveMovesOn() {
        var registry = self.registry("A", "B", "C")
        let b = registry.profiles[1].id
        registry.activate(b)
        let removed = registry.remove(b)
        #expect(removed?.name == "B")
        #expect(registry.active.name == "A")
        #expect(registry.profiles.map(\.name) == ["A", "C"])
    }

    @Test("Deleting a profile that isn't open leaves the open one alone")
    func deletingInactiveKeepsSelection() {
        var registry = self.registry("A", "B")
        let a = registry.activeID
        registry.remove(registry.profiles[1].id)
        #expect(registry.activeID == a)
    }

    @Test("Activating an id that isn't there changes nothing")
    func unknownActivationIgnored() {
        var registry = self.registry("A", "B")
        let before = registry.activeID
        registry.activate(UUID())
        #expect(registry.activeID == before)
    }

    @Test("A registry survives a round trip through JSON")
    func codableRoundTrip() throws {
        var original = registry("A", "B")
        original.activate(original.profiles[1].id)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProfileRegistry.self, from: data)
        #expect(decoded.profiles.map(\.name) == ["A", "B"])
        #expect(decoded.active.name == "B")
    }

    @Test("A registry naming an active profile that is gone still opens")
    func danglingActiveIDRecovers() throws {
        let json = """
        {"profiles":[{"id":"\(UUID().uuidString)","name":"A","colorHex":"#1F6E8C",
        "symbol":"person.fill","fileName":"a.store",
        "createdAt":0,"lastOpenedAt":0}],"activeID":"\(UUID().uuidString)"}
        """
        let decoded = try JSONDecoder().decode(ProfileRegistry.self, from: Data(json.utf8))
        #expect(decoded.active.name == "A")
    }

    @Test("An empty profile list is rebuilt rather than left unopenable")
    func emptyListRecovers() throws {
        let json = #"{"profiles":[],"activeID":"\#(UUID().uuidString)"}"#
        let decoded = try JSONDecoder().decode(ProfileRegistry.self, from: Data(json.utf8))
        #expect(decoded.profiles.count == 1)
        #expect(decoded.activeID == decoded.profiles[0].id)
    }

    @Test("A registry written before the extra fields existed still loads")
    func decodesOlderRegistry() throws {
        // Exactly the shape the first version wrote: no note, owner, currency
        // or picture. Losing every profile over a added field is not acceptable.
        let id = UUID()
        let json = """
        {"profiles":[{"id":"\(id.uuidString)","name":"Personal","colorHex":"#1F6E8C",
        "symbol":"person.fill","fileName":"\(id.uuidString).store",
        "createdAt":808853552.09,"lastOpenedAt":808853552.09}],
        "activeID":"\(id.uuidString)"}
        """
        let decoded = try JSONDecoder().decode(ProfileRegistry.self, from: Data(json.utf8))
        #expect(decoded.active.name == "Personal")
        #expect(decoded.active.fileName == "\(id.uuidString).store")
        #expect(decoded.active.note.isEmpty)
        #expect(decoded.active.ownerName.isEmpty)
        #expect(decoded.active.currencySymbol == Money.defaultSymbol)
        #expect(decoded.active.imageData == nil)
    }

    @Test("The general editor reaches every field")
    func updateEditsMetadata() {
        var registry = self.registry("Personal")
        registry.update(registry.activeID) {
            $0.note = "Day to day"
            $0.ownerName = "Alex"
            $0.currencySymbol = "£"
        }
        #expect(registry.active.note == "Day to day")
        #expect(registry.active.ownerName == "Alex")
        #expect(registry.active.currencySymbol == "£")
    }

    @Test("Each profile gets its own store file")
    func distinctFiles() {
        let registry = self.registry("A", "B", "C")
        #expect(Set(registry.profiles.map(\.fileName)).count == 3)
    }
}

@Suite("Profile metadata")
struct ProfileMetadataTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func profile(bornOn birth: Date?) -> Profile {
        Profile(name: "Personal", birthDate: birth)
    }

    @Test("No birth date means no age rather than a wrong one")
    func ageUnsetIsNil() {
        #expect(profile(bornOn: nil).age(on: day(2026, 8, 19)) == nil)
    }

    @Test("On the birthday the age has ticked over")
    func ageOnBirthday() {
        let subject = profile(bornOn: day(1990, 8, 19))
        #expect(subject.age(on: day(2026, 8, 19), calendar: calendar) == 36)
    }

    @Test("The day before the birthday is still the younger age")
    func ageDayBeforeBirthday() {
        let subject = profile(bornOn: day(1990, 8, 19))
        #expect(subject.age(on: day(2026, 8, 18), calendar: calendar) == 35)
    }

    @Test("Someone born on a leap day ages on the 28th in ordinary years")
    func ageAcrossLeapDay() {
        // Foundation clamps the anniversary of 29 February to the 28th when the
        // year has no 29th, so that is the day the age ticks over. Pinned here
        // because it is a real choice among several defensible ones.
        let subject = profile(bornOn: day(2000, 2, 29))
        #expect(subject.age(on: day(2025, 2, 27), calendar: calendar) == 24)
        #expect(subject.age(on: day(2025, 2, 28), calendar: calendar) == 25)
        #expect(subject.age(on: day(2024, 2, 29), calendar: calendar) == 24)
    }

    @Test("A birth date in the future is a typo, not a negative age")
    func ageInFutureIsNil() {
        let subject = profile(bornOn: day(2030, 1, 1))
        #expect(subject.age(on: day(2026, 8, 19), calendar: calendar) == nil)
    }

    @Test("The switcher summary leads with what someone does")
    func summaryPrefersWork() {
        var subject = Profile(name: "Personal", note: "Day to day", ownerName: "Alex")
        #expect(subject.summary == "Alex")

        subject.occupation = "Engineer"
        #expect(subject.summary == "Engineer")

        subject.employer = "Acme"
        #expect(subject.summary == "Engineer · Acme")
    }

    @Test("With nothing filled in there is no summary to show")
    func summaryEmpty() {
        #expect(Profile(name: "Personal").summary.isEmpty)
    }

    @Test("A registry written before the personal fields existed still loads")
    func decodesWithoutPersonalFields() throws {
        let id = UUID()
        let json = """
        {"profiles":[{"id":"\(id.uuidString)","name":"Personal","colorHex":"#1F6E8C",
        "symbol":"person.fill","fileName":"\(id.uuidString).store",
        "createdAt":808853552.09,"lastOpenedAt":808853552.09}],
        "activeID":"\(id.uuidString)"}
        """
        let decoded = try JSONDecoder().decode(ProfileRegistry.self, from: Data(json.utf8))
        #expect(decoded.active.occupation.isEmpty)
        #expect(decoded.active.employer.isEmpty)
        #expect(decoded.active.location.isEmpty)
        #expect(decoded.active.employmentStatus == .unspecified)
        #expect(decoded.active.birthDate == nil)
    }

    @Test("Every field survives a round trip through JSON")
    func metadataRoundTrip() throws {
        var subject = Profile(name: "Personal")
        subject.occupation = "Engineer"
        subject.employer = "Acme"
        subject.employmentStatus = .selfEmployed
        subject.birthDate = day(1990, 8, 19)
        subject.location = "Lisbon"

        let decoded = try JSONDecoder().decode(
            Profile.self, from: try JSONEncoder().encode(subject))
        #expect(decoded.occupation == "Engineer")
        #expect(decoded.employer == "Acme")
        #expect(decoded.employmentStatus == .selfEmployed)
        #expect(decoded.location == "Lisbon")
        #expect(decoded.birthDate == subject.birthDate)
    }
}

@Suite("Profile kinds")
struct ProfileKindTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test("A person's inception date is their birth date")
    func personInception() {
        var subject = Profile(kind: .person, name: "Personal")
        subject.inceptionDate = day(1990, 8, 19)
        #expect(subject.birthDate == day(1990, 8, 19))
        #expect(subject.foundedDate == nil)
        #expect(subject.age(on: day(2026, 8, 19), calendar: calendar) == 36)
    }

    @Test("An organisation's inception date is when it was founded")
    func organizationInception() {
        var subject = Profile(kind: .organization, name: "Acme")
        subject.inceptionDate = day(2016, 1, 1)
        #expect(subject.foundedDate == day(2016, 1, 1))
        #expect(subject.birthDate == nil)
        #expect(subject.age(on: day(2026, 8, 19), calendar: calendar) == 10)
    }

    @Test("The age reads differently for a person and an organisation")
    func ageCaptionWording() {
        var person = Profile(kind: .person, name: "Personal")
        person.birthDate = day(1990, 8, 19)
        #expect(person.ageCaption(on: day(2026, 8, 19)) == "36 years old")

        var company = Profile(kind: .organization, name: "Acme")
        company.foundedDate = day(2025, 8, 19)
        #expect(company.ageCaption(on: day(2026, 8, 19)) == "Trading 1 year")

        company.foundedDate = day(2016, 1, 1)
        #expect(company.ageCaption(on: day(2026, 8, 19)) == "Trading 10 years")
    }

    @Test("With no date set there is no age caption to show")
    func noCaptionWithoutDate() {
        #expect(Profile(name: "Personal").ageCaption() == nil)
    }

    @Test("An organisation summarises by what it does and where it is")
    func organizationSummary() {
        var subject = Profile(kind: .organization, name: "Acme")
        subject.occupation = "ignored for a company"
        subject.industry = "Logistics"
        subject.location = "Porto"
        #expect(subject.summary == "Logistics · Porto")
    }

    @Test("Each kind offers its own symbols, led by its default")
    func symbolPalettes() {
        #expect(ProfileKind.person.symbols.first == ProfileKind.person.defaultSymbol)
        #expect(ProfileKind.organization.symbols.first == ProfileKind.organization.defaultSymbol)
        #expect(!ProfileKind.person.symbols.contains(ProfileKind.organization.defaultSymbol))
    }

    @Test("A profile written before kinds existed is a person")
    func decodesWithoutKind() throws {
        let id = UUID()
        let json = """
        {"profiles":[{"id":"\(id.uuidString)","name":"Personal","colorHex":"#1F6E8C",
        "symbol":"person.fill","fileName":"\(id.uuidString).store",
        "createdAt":808853552.09,"lastOpenedAt":808853552.09}],
        "activeID":"\(id.uuidString)"}
        """
        let decoded = try JSONDecoder().decode(ProfileRegistry.self, from: Data(json.utf8))
        #expect(decoded.active.kind == .person)
    }
}
