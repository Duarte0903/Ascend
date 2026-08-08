# Finance Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS app that reproduces the `net_worth_tracker_pro` workbook exactly, and adds full create/edit/archive/delete management of bank accounts.

**Architecture:** Three layers with a hard dependency rule — SwiftUI views read from a pure-Swift engine, which never imports SwiftData. Only user inputs are persisted (accounts, dated records, settings); every derived figure is recomputed on read, so an account-flag edit re-derives all history instantly and the dashboard can never disagree with the table.

**Tech Stack:** Swift 6.3, SwiftUI, SwiftData, Swift Charts, Swift Testing (`import Testing`), XcodeGen, macOS 26 SDK.

## Global Constraints

- Deployment target: macOS 26.0. Bundle id: `com.duarte.financetracker`. Display name: `Finance Tracker`.
- Build with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` — `xcode-select` points at CommandLineTools and must not be changed (needs sudo).
- **The `Engine/` directory must never `import SwiftData` or `import SwiftUI`.** It is pure value types. This is what makes it testable without launching the app.
- All money is `Double`, rounded to 2 decimals when user input is committed. Chosen over `Decimal` because projections need `pow()`; magnitudes here are far below `Double`'s exact-integer range, and all comparisons use tolerance.
- Currency formatting: `8 410 €` — U+202F narrow no-break space as thousands separator, comma decimal, trailing `€`. Percentages one decimal: `12,2 %`.
- Undefined values render as `—` (em dash), never `0`.
- No App Sandbox, no entitlements requiring a developer account. Ad-hoc signing only.
- Tests use Swift Testing (`@Test`, `#expect`), not XCTest.
- Commit after every task.

---

## Reference values (source of truth for all tests)

The five workbook records, oldest first. Accounts: Banco CTT (main), Revolut (savings),
XTB (investment), Edenred (restricted — excluded from Usable, not a savings account).

| # | Date | Banco CTT | Revolut | XTB | Edenred |
|---|---|---|---|---|---|
| 1 | 01/07/2026 | 6285.73 | 200.00 | 710.85 | 268.43 |
| 2 | 01/07/2026 | 6235.73 | 250.00 | 710.85 | 268.43 |
| 3 | 02/07/2026 | 6265.73 | 250.00 | 710.85 | 268.43 |
| 4 | 03/07/2026 | 6265.73 | 250.02 | 710.85 | 268.43 |
| 5 | 04/08/2026 | 6962.35 | 350.27 | 819.49 | 277.63 |

Derived (computed and verified against the source PDF):

| # | Total | Usable | Change € | Change % | Savings Rate |
|---|---|---|---|---|---|
| 1 | 7465.01 | 7196.58 | — | — | — |
| 2 | 7465.01 | 7196.58 | 0.00 | 0.0 % | 0.66979 % |
| 3 | 7495.01 | 7226.58 | 30.00 | 0.40188 % | 0 % |
| 4 | 7495.03 | 7226.60 | 0.02 | 0.000267 % | 0.000267 % |
| 5 | 8409.74 | 8132.11 | 914.71 | 12.20427 % | 2.78706 % |

Dashboard: net worth 8409.74 · usable 8132.11 · latest change 914.71 / 12.204 % ·
total growth 944.73 · best 914.71 · avg change 236.1825 · records 5 · avg savings rate 0.86429 %.

Allocation (record 5): CTT 82.788 % · Revolut 4.1651 % · XTB 9.7445 % · Edenred 3.3013 %.

Goals (target 25 000): remaining 16 590.26 · progress 33.639 % · est. records 71.

Projections (income 1117, expenses 200, Revolut +100, XTB +100, XTB 7 %/yr, Revolut 1.1 %/yr,
horizon 60): leftover 717 · savings rate of income 82.095 % · months to goal 18.

| Month | Banco CTT | Revolut | XTB | Edenred | Net worth |
|---|---|---|---|---|---|
| 0 | 6962.35 | 350.27 | 819.49 | 277.63 | 8409.74 |
| 1 | 7679.35 | 450.59 | 924.12 | 277.63 | 9331.69 |
| 12 | 15566.35 | 1560.16 | 2114.88 | 277.63 | 19519.03 |
| 18 | 19868.35 | 2170.09 | 2796.20 | 277.63 | 25112.27 |
| 60 | 49982.35 | 6534.29 | 8268.96 | 277.63 | 65063.23 |

Note: the source PDF prints month 12 as 19 516 € vs. our 19 519.03. The PDF's own rows are
internally inconsistent by 1 € (month 1 shows usable 9 054 + Edenred 278 = 9 332 but prints
net worth 9 331), so this is display rounding in the source, not a formula difference. Per-account
month-1 values match the PDF exactly. Tests assert full precision with tolerance.

---

## File structure

```
project.yml                                   XcodeGen spec
scripts/build.sh                              build + ad-hoc sign
scripts/install.sh                            copy to /Applications
Sources/FinanceTracker/
  App/FinanceTrackerApp.swift                 @main, model container
  App/RootView.swift                          NavigationSplitView + sidebar
  App/Section.swift                           sidebar enum
  Engine/Money.swift                          formatting helpers (pure)
  Engine/PortfolioInput.swift                 value types the engine consumes
  Engine/LedgerEngine.swift                   per-record derivation
  Engine/DashboardMetrics.swift               the 9 KPIs
  Engine/AllocationMetrics.swift              latest-record split
  Engine/GoalMetrics.swift                    target progress
  Engine/ProjectionEngine.swift               month-by-month forecast
  Models/Account.swift                        @Model
  Models/BalanceRecord.swift                  @Model + BalanceEntry
  Models/AppSettings.swift                    @Model singleton
  Models/SeedData.swift                       first-launch workbook import
  Services/PortfolioStore.swift               @Model -> engine value types
  Services/AccountService.swift               lifecycle rules + validation
  Services/BackupService.swift                JSON export/import
  Views/DashboardView.swift
  Views/BalancesView.swift
  Views/TrendsView.swift
  Views/AllocationView.swift
  Views/GoalsView.swift
  Views/ProjectionsView.swift
  Views/AccountsView.swift
  Views/Components/KPITile.swift
  Views/Components/CardSection.swift
  Resources/Info.plist
Tests/FinanceTrackerTests/
  WorkbookFixture.swift                       the five records as engine inputs
  LedgerEngineTests.swift
  DashboardMetricsTests.swift
  AllocationGoalTests.swift
  ProjectionEngineTests.swift
  MoneyFormattingTests.swift
  AccountLifecycleTests.swift
  SeedDataTests.swift
```

---

### Task 1: Project scaffolding that builds and runs one test

**Files:**
- Create: `project.yml`, `Sources/FinanceTracker/App/FinanceTrackerApp.swift`,
  `Sources/FinanceTracker/Resources/Info.plist`, `Tests/FinanceTrackerTests/SmokeTest.swift`,
  `scripts/build.sh`, `.gitignore`

**Interfaces:**
- Consumes: nothing
- Produces: a working `xcodebuild test` cycle every later task depends on

- [ ] **Step 1: Write `.gitignore`**

```
.DS_Store
build/
DerivedData/
*.xcodeproj
*.xcworkspace
```

`.xcodeproj` is ignored on purpose — it is generated from `project.yml`, which is the checked-in source of truth.

- [ ] **Step 2: Write `project.yml`**

```yaml
name: FinanceTracker
options:
  bundleIdPrefix: com.duarte
  deploymentTarget:
    macOS: "26.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGNING_REQUIRED: "NO"
    CODE_SIGNING_ALLOWED: "NO"
    ENABLE_HARDENED_RUNTIME: "NO"
targets:
  FinanceTracker:
    type: application
    platform: macOS
    sources:
      - path: Sources/FinanceTracker
    info:
      path: Sources/FinanceTracker/Resources/Info.plist
      properties:
        CFBundleName: Finance Tracker
        CFBundleDisplayName: Finance Tracker
        CFBundleIdentifier: com.duarte.financetracker
        CFBundleShortVersionString: "1.0"
        LSMinimumSystemVersion: "26.0"
        LSApplicationCategoryType: public.app-category.finance
        NSHumanReadableCopyright: ""
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.duarte.financetracker
        INFOPLIST_KEY_NSPrincipalClass: NSApplication
        ENABLE_APP_SANDBOX: "NO"
  FinanceTrackerTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests/FinanceTrackerTests
    dependencies:
      - target: FinanceTracker
schemes:
  FinanceTracker:
    build:
      targets:
        FinanceTracker: all
        FinanceTrackerTests: [test]
    test:
      targets:
        - FinanceTrackerTests
```

- [ ] **Step 3: Write the minimal app entry point**

`Sources/FinanceTracker/App/FinanceTrackerApp.swift`:

```swift
import SwiftUI

@main
struct FinanceTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Finance Tracker")
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
```

Create `Sources/FinanceTracker/Resources/Info.plist` as an empty plist dict — XcodeGen fills the
properties listed in `project.yml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

- [ ] **Step 4: Write the smoke test**

`Tests/FinanceTrackerTests/SmokeTest.swift`:

```swift
import Testing
@testable import FinanceTracker

@Test func testTargetIsWiredUp() {
    #expect(1 + 1 == 2)
}
```

- [ ] **Step 5: Write `scripts/build.sh`**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodegen generate
xcodebuild -project FinanceTracker.xcodeproj \
           -scheme FinanceTracker \
           -configuration Release \
           -derivedDataPath build \
           -destination 'platform=macOS' \
           build | tail -5

APP="build/Build/Products/Release/FinanceTracker.app"
codesign --force --deep --sign - "$APP"
echo "Built and ad-hoc signed: $APP"
```

Then `chmod +x scripts/build.sh`.

- [ ] **Step 6: Generate and run the test — verify the toolchain works**

```bash
cd /Users/duarte/finance_tracker && xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: `TEST SUCCEEDED`, 1 test passing. If XcodeGen rejects a key, fix `project.yml` — do not
hand-edit the `.xcodeproj`.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: scaffold macOS app project with XcodeGen and Swift Testing"
```

---

### Task 2: Money formatting

**Files:**
- Create: `Sources/FinanceTracker/Engine/Money.swift`, `Tests/FinanceTrackerTests/MoneyFormattingTests.swift`

**Interfaces:**
- Produces: `Money.currency(_ value: Double, decimals: Int = 0) -> String`,
  `Money.percent(_ fraction: Double?) -> String`, `Money.currency(_ value: Double?) -> String`,
  `Money.dash` — used by every view.

- [ ] **Step 1: Write the failing tests**

`Tests/FinanceTrackerTests/MoneyFormattingTests.swift`:

```swift
import Testing
@testable import FinanceTracker

private let nnbsp = "\u{202F}"

@Test func formatsWholeEurosWithNarrowSpaceSeparator() {
    #expect(Money.currency(8409.74) == "8\(nnbsp)410\(nnbsp)€")
}

@Test func formatsCentsWhenAsked() {
    #expect(Money.currency(6285.73, decimals: 2) == "6\(nnbsp)285,73\(nnbsp)€")
}

@Test func formatsSmallValuesWithoutSeparator() {
    #expect(Money.currency(915) == "915\(nnbsp)€")
}

@Test func formatsNegativeValues() {
    #expect(Money.currency(-50) == "-50\(nnbsp)€")
}

@Test func formatsPercentToOneDecimal() {
    #expect(Money.percent(0.1220427) == "12,2\(nnbsp)%")
}

@Test func nilValuesRenderAsEmDash() {
    #expect(Money.currency(nil) == "—")
    #expect(Money.percent(nil) == "—")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/duarte/finance_tracker && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'Money' in scope`.

- [ ] **Step 3: Implement**

`Sources/FinanceTracker/Engine/Money.swift`:

```swift
import Foundation

/// Currency and percentage formatting matching the source workbook:
/// narrow no-break space separators, comma decimal, trailing symbol.
enum Money {
    static let dash = "—"
    private static let nnbsp = "\u{202F}"

    private static func formatter(decimals: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = nnbsp
        f.decimalSeparator = ","
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        return f
    }

    static func currency(_ value: Double, decimals: Int = 0) -> String {
        let n = formatter(decimals: decimals).string(from: NSNumber(value: value)) ?? "0"
        return "\(n)\(nnbsp)€"
    }

    static func currency(_ value: Double?, decimals: Int = 0) -> String {
        guard let value else { return dash }
        return currency(value, decimals: decimals)
    }

    /// Takes a fraction (0.122 -> "12,2 %").
    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return dash }
        let n = formatter(decimals: 1).string(from: NSNumber(value: fraction * 100)) ?? "0"
        return "\(n)\(nnbsp)%"
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Same command as Step 2. Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add workbook-matching currency and percent formatting"
```

---

### Task 3: Engine input types and per-record derivation

This is the core of the app. Everything else reads from it.

**Files:**
- Create: `Sources/FinanceTracker/Engine/PortfolioInput.swift`,
  `Sources/FinanceTracker/Engine/LedgerEngine.swift`,
  `Tests/FinanceTrackerTests/WorkbookFixture.swift`,
  `Tests/FinanceTrackerTests/LedgerEngineTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `struct AccountInfo` — `id: UUID, name: String, kind: AccountKind, colorHex: String, sortOrder: Int, includeInUsable: Bool, countsAsSavings: Bool, expectedAnnualReturn: Double, monthlyContribution: Double, isLeftoverDestination: Bool`
  - `struct RecordInput` — `id: UUID, date: Date, balances: [UUID: Double]`
  - `struct PortfolioInput` — `accounts: [AccountInfo], records: [RecordInput], targetNetWorth: Double, monthlyNetIncome: Double, maxMonthlyExpenses: Double, projectionHorizonMonths: Int`
  - `struct DerivedRecord` — `id, date, balances, total, usable, changeAmount: Double?, changePercent: Double?, savingsRate: Double?`
  - `LedgerEngine.derive(_ input: PortfolioInput) -> [DerivedRecord]` (sorted oldest first)

- [ ] **Step 1: Write the input value types**

`Sources/FinanceTracker/Engine/PortfolioInput.swift`:

```swift
import Foundation

enum AccountKind: String, Codable, CaseIterable, Sendable {
    case main, savings, investment, restricted

    var displayName: String {
        switch self {
        case .main: "Main"
        case .savings: "Savings"
        case .investment: "Investment"
        case .restricted: "Restricted"
        }
    }

    /// Defaults applied at creation; every one stays editable afterwards.
    var defaultIncludeInUsable: Bool { self != .restricted }
    var defaultCountsAsSavings: Bool { self == .savings || self == .investment }
}

struct AccountInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var kind: AccountKind
    var colorHex: String
    var sortOrder: Int
    var includeInUsable: Bool
    var countsAsSavings: Bool
    var expectedAnnualReturn: Double
    var monthlyContribution: Double
    var isLeftoverDestination: Bool
}

struct RecordInput: Identifiable, Hashable, Sendable {
    let id: UUID
    var date: Date
    /// Missing entries read as 0.
    var balances: [UUID: Double]

    func amount(for accountID: UUID) -> Double { balances[accountID] ?? 0 }
}

struct PortfolioInput: Sendable {
    var accounts: [AccountInfo]
    var records: [RecordInput]
    var targetNetWorth: Double
    var monthlyNetIncome: Double
    var maxMonthlyExpenses: Double
    var projectionHorizonMonths: Int

    var activeAccountsSorted: [AccountInfo] {
        accounts.sorted { $0.sortOrder < $1.sortOrder }
    }
}
```

- [ ] **Step 2: Write the test fixture**

`Tests/FinanceTrackerTests/WorkbookFixture.swift`:

```swift
import Foundation
@testable import FinanceTracker

/// The source workbook, expressed as engine input. Every expected value in the
/// test suite is traceable to net_worth_tracker_pro.pdf.
enum WorkbookFixture {
    static let cttID = UUID()
    static let revolutID = UUID()
    static let xtbID = UUID()
    static let edenredID = UUID()

    static let accounts: [AccountInfo] = [
        AccountInfo(id: cttID, name: "Banco CTT", kind: .main, colorHex: "#2E7D32",
                    sortOrder: 0, includeInUsable: true, countsAsSavings: false,
                    expectedAnnualReturn: 0, monthlyContribution: 0,
                    isLeftoverDestination: true),
        AccountInfo(id: revolutID, name: "Revolut", kind: .savings, colorHex: "#1565C0",
                    sortOrder: 1, includeInUsable: true, countsAsSavings: true,
                    expectedAnnualReturn: 0.011, monthlyContribution: 100,
                    isLeftoverDestination: false),
        AccountInfo(id: xtbID, name: "XTB", kind: .investment, colorHex: "#EF6C00",
                    sortOrder: 2, includeInUsable: true, countsAsSavings: true,
                    expectedAnnualReturn: 0.07, monthlyContribution: 100,
                    isLeftoverDestination: false),
        AccountInfo(id: edenredID, name: "Edenred", kind: .restricted, colorHex: "#6A1B9A",
                    sortOrder: 3, includeInUsable: false, countsAsSavings: false,
                    expectedAnnualReturn: 0, monthlyContribution: 0,
                    isLeftoverDestination: false),
    ]

    static func date(_ day: Int, _ month: Int, _ year: Int) -> Date {
        var c = DateComponents()
        c.day = day; c.month = month; c.year = year
        c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    static let records: [RecordInput] = [
        RecordInput(id: UUID(), date: date(1, 7, 2026),
                    balances: [cttID: 6285.73, revolutID: 200.00, xtbID: 710.85, edenredID: 268.43]),
        RecordInput(id: UUID(), date: date(1, 7, 2026),
                    balances: [cttID: 6235.73, revolutID: 250.00, xtbID: 710.85, edenredID: 268.43]),
        RecordInput(id: UUID(), date: date(2, 7, 2026),
                    balances: [cttID: 6265.73, revolutID: 250.00, xtbID: 710.85, edenredID: 268.43]),
        RecordInput(id: UUID(), date: date(3, 7, 2026),
                    balances: [cttID: 6265.73, revolutID: 250.02, xtbID: 710.85, edenredID: 268.43]),
        RecordInput(id: UUID(), date: date(4, 8, 2026),
                    balances: [cttID: 6962.35, revolutID: 350.27, xtbID: 819.49, edenredID: 277.63]),
    ]

    static let portfolio = PortfolioInput(
        accounts: accounts,
        records: records,
        targetNetWorth: 25_000,
        monthlyNetIncome: 1_117,
        maxMonthlyExpenses: 200,
        projectionHorizonMonths: 60
    )
}
```

- [ ] **Step 3: Write the failing tests**

`Tests/FinanceTrackerTests/LedgerEngineTests.swift`:

```swift
import Testing
import Foundation
@testable import FinanceTracker

private let tol = 0.005

@Test func derivesTotalsForEveryWorkbookRecord() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    #expect(d.count == 5)
    let expected = [7465.01, 7465.01, 7495.01, 7495.03, 8409.74]
    for (i, e) in expected.enumerated() {
        #expect(abs(d[i].total - e) < tol, "record \(i + 1) total")
    }
}

@Test func usableExcludesRestrictedAccounts() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    let expected = [7196.58, 7196.58, 7226.58, 7226.60, 8132.11]
    for (i, e) in expected.enumerated() {
        #expect(abs(d[i].usable - e) < tol, "record \(i + 1) usable")
    }
}

@Test func firstRecordHasNoChangeOrSavingsRate() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    #expect(d[0].changeAmount == nil)
    #expect(d[0].changePercent == nil)
    #expect(d[0].savingsRate == nil)
}

@Test func derivesChangeAmounts() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    let expected: [Double] = [0.00, 30.00, 0.02, 914.71]
    for (i, e) in expected.enumerated() {
        #expect(abs(d[i + 1].changeAmount! - e) < tol, "record \(i + 2) change")
    }
}

@Test func derivesChangePercent() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    #expect(abs(d[4].changePercent! - 0.1220427) < 0.00001)
}

/// The workbook's least obvious formula: the increase in savings-flagged
/// accounts, over the PREVIOUS total. Record 5: (100.25 + 108.64) / 7495.03.
@Test func savingsRateUsesSavingsAccountDeltaOverPreviousTotal() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    #expect(abs(d[1].savingsRate! - 0.0066979) < 0.0000001)
    #expect(abs(d[2].savingsRate! - 0.0) < 0.0000001)
    #expect(abs(d[4].savingsRate! - 0.0278706) < 0.0000001)
}

@Test func percentagesAreNilWhenPreviousTotalIsZero() {
    let a = WorkbookFixture.accounts[0]
    let input = PortfolioInput(
        accounts: [a],
        records: [
            RecordInput(id: UUID(), date: WorkbookFixture.date(1, 1, 2026), balances: [a.id: 0]),
            RecordInput(id: UUID(), date: WorkbookFixture.date(2, 1, 2026), balances: [a.id: 100]),
        ],
        targetNetWorth: 1000, monthlyNetIncome: 0, maxMonthlyExpenses: 0, projectionHorizonMonths: 12)
    let d = LedgerEngine.derive(input)
    #expect(d[1].changeAmount == 100)
    #expect(d[1].changePercent == nil)
    #expect(d[1].savingsRate == nil)
}

@Test func recordsAreSortedOldestFirstRegardlessOfInputOrder() {
    var input = WorkbookFixture.portfolio
    input.records = input.records.reversed()
    let d = LedgerEngine.derive(input)
    #expect(abs(d[0].total - 7465.01) < tol)
    #expect(abs(d[4].total - 8409.74) < tol)
}

@Test func missingBalanceEntriesReadAsZero() {
    var input = WorkbookFixture.portfolio
    input.records = [RecordInput(id: UUID(), date: WorkbookFixture.date(1, 7, 2026),
                                 balances: [WorkbookFixture.cttID: 100])]
    let d = LedgerEngine.derive(input)
    #expect(d[0].total == 100)
}
```

- [ ] **Step 4: Run the tests to verify they fail**

```bash
cd /Users/duarte/finance_tracker && xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'LedgerEngine' in scope`.

- [ ] **Step 5: Implement**

`Sources/FinanceTracker/Engine/LedgerEngine.swift`:

```swift
import Foundation

struct DerivedRecord: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let balances: [UUID: Double]
    let total: Double
    let usable: Double
    /// nil for the first record — a change with nothing to compare to is
    /// undefined, not zero.
    let changeAmount: Double?
    /// nil when the previous total is zero.
    let changePercent: Double?
    let savingsRate: Double?

    func amount(for accountID: UUID) -> Double { balances[accountID] ?? 0 }
}

enum LedgerEngine {
    /// Derives every computed column for every record, oldest first.
    static func derive(_ input: PortfolioInput) -> [DerivedRecord] {
        let sorted = input.records.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let usableIDs = Set(input.accounts.filter(\.includeInUsable).map(\.id))
        let savingsIDs = Set(input.accounts.filter(\.countsAsSavings).map(\.id))
        let allIDs = input.accounts.map(\.id)

        var result: [DerivedRecord] = []
        var previous: RecordInput?

        for record in sorted {
            let total = allIDs.reduce(0) { $0 + record.amount(for: $1) }
            let usable = allIDs.filter(usableIDs.contains)
                .reduce(0) { $0 + record.amount(for: $1) }

            var changeAmount: Double?
            var changePercent: Double?
            var savingsRate: Double?

            if let previous {
                let previousTotal = allIDs.reduce(0) { $0 + previous.amount(for: $1) }
                changeAmount = total - previousTotal
                let savingsDelta = allIDs.filter(savingsIDs.contains)
                    .reduce(0) { $0 + record.amount(for: $1) - previous.amount(for: $1) }
                if previousTotal != 0 {
                    changePercent = (total - previousTotal) / previousTotal
                    savingsRate = savingsDelta / previousTotal
                }
            }

            result.append(DerivedRecord(
                id: record.id, date: record.date, balances: record.balances,
                total: total, usable: usable,
                changeAmount: changeAmount, changePercent: changePercent,
                savingsRate: savingsRate))
            previous = record
        }
        return result
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Same command as Step 4. Expected: 9 ledger tests pass.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: add ledger engine deriving totals, usable, change and savings rate"
```

---

### Task 4: Dashboard, allocation and goal metrics

**Files:**
- Create: `Sources/FinanceTracker/Engine/DashboardMetrics.swift`,
  `Sources/FinanceTracker/Engine/AllocationMetrics.swift`,
  `Sources/FinanceTracker/Engine/GoalMetrics.swift`,
  `Tests/FinanceTrackerTests/DashboardMetricsTests.swift`,
  `Tests/FinanceTrackerTests/AllocationGoalTests.swift`

**Interfaces:**
- Consumes: `LedgerEngine.derive`, `DerivedRecord`, `PortfolioInput`
- Produces:
  - `DashboardMetrics.compute(records: [DerivedRecord]) -> DashboardMetrics` with fields
    `currentNetWorth: Double?, usableCash: Double?, latestChangeAmount: Double?, latestChangePercent: Double?, totalGrowth: Double?, bestChange: Double?, averageChange: Double?, recordCount: Int, averageSavingsRate: Double?`
  - `AllocationMetrics.compute(accounts: [AccountInfo], records: [DerivedRecord]) -> AllocationMetrics`
    with `slices: [AllocationSlice]` (`accountID, name, colorHex, amount, share`), `total: Double`, `usable: Double`
  - `GoalMetrics.compute(target: Double, dashboard: DashboardMetrics) -> GoalMetrics` with
    `target, current, remaining, progress: Double?, estimatedRecordsToGoal: Int?`

- [ ] **Step 1: Write the failing dashboard tests**

`Tests/FinanceTrackerTests/DashboardMetricsTests.swift`:

```swift
import Testing
@testable import FinanceTracker

private let tol = 0.005

@Test func computesAllNineDashboardKPIs() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    let m = DashboardMetrics.compute(records: d)
    #expect(abs(m.currentNetWorth! - 8409.74) < tol)
    #expect(abs(m.usableCash! - 8132.11) < tol)
    #expect(abs(m.latestChangeAmount! - 914.71) < tol)
    #expect(abs(m.latestChangePercent! - 0.1220427) < 0.00001)
    #expect(abs(m.totalGrowth! - 944.73) < tol)
    #expect(abs(m.bestChange! - 914.71) < tol)
    #expect(abs(m.averageChange! - 236.1825) < tol)
    #expect(m.recordCount == 5)
    #expect(abs(m.averageSavingsRate! - 0.0086429) < 0.0000001)
}

@Test func emptyPortfolioYieldsUndefinedKPIs() {
    var input = WorkbookFixture.portfolio
    input.records = []
    let m = DashboardMetrics.compute(records: LedgerEngine.derive(input))
    #expect(m.currentNetWorth == nil)
    #expect(m.averageChange == nil)
    #expect(m.recordCount == 0)
}

@Test func singleRecordHasNetWorthButNoChangeStatistics() {
    var input = WorkbookFixture.portfolio
    input.records = [WorkbookFixture.records[0]]
    let m = DashboardMetrics.compute(records: LedgerEngine.derive(input))
    #expect(abs(m.currentNetWorth! - 7465.01) < tol)
    #expect(m.totalGrowth! == 0)
    #expect(m.averageChange == nil)
    #expect(m.bestChange == nil)
    #expect(m.recordCount == 1)
}
```

- [ ] **Step 2: Write the failing allocation and goal tests**

`Tests/FinanceTrackerTests/AllocationGoalTests.swift`:

```swift
import Testing
@testable import FinanceTracker

private let tol = 0.005

@Test func allocationSplitsLatestRecordByAccount() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    let a = AllocationMetrics.compute(accounts: WorkbookFixture.accounts, records: d)
    #expect(a.slices.count == 4)
    #expect(abs(a.total - 8409.74) < tol)
    #expect(abs(a.usable - 8132.11) < tol)

    let expected: [(String, Double, Double)] = [
        ("Banco CTT", 6962.35, 0.82788),
        ("Revolut", 350.27, 0.041651),
        ("XTB", 819.49, 0.097445),
        ("Edenred", 277.63, 0.033013),
    ]
    for (name, amount, share) in expected {
        let slice = a.slices.first { $0.name == name }!
        #expect(abs(slice.amount - amount) < tol, "\(name) amount")
        #expect(abs(slice.share - share) < 0.00001, "\(name) share")
    }
}

@Test func allocationSharesSumToOne() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    let a = AllocationMetrics.compute(accounts: WorkbookFixture.accounts, records: d)
    #expect(abs(a.slices.reduce(0) { $0 + $1.share } - 1.0) < 0.000001)
}

@Test func allocationOfEmptyPortfolioIsEmpty() {
    var input = WorkbookFixture.portfolio
    input.records = []
    let a = AllocationMetrics.compute(accounts: input.accounts,
                                      records: LedgerEngine.derive(input))
    #expect(a.slices.isEmpty)
    #expect(a.total == 0)
}

@Test func computesGoalProgress() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    let g = GoalMetrics.compute(target: 25_000,
                                dashboard: DashboardMetrics.compute(records: d))
    #expect(abs(g.remaining - 16_590.26) < tol)
    #expect(abs(g.progress! - 0.336390) < 0.00001)
    #expect(g.estimatedRecordsToGoal == 71)
}

@Test func goalReachedClampsRemainingToZero() {
    let d = LedgerEngine.derive(WorkbookFixture.portfolio)
    let g = GoalMetrics.compute(target: 5_000,
                                dashboard: DashboardMetrics.compute(records: d))
    #expect(g.remaining == 0)
    #expect(g.progress! > 1.0)
    #expect(g.estimatedRecordsToGoal == 0)
}

@Test func estimateIsUndefinedWhenAverageChangeIsNotPositive() {
    var input = WorkbookFixture.portfolio
    input.records = Array(WorkbookFixture.records.prefix(1))
    let g = GoalMetrics.compute(target: 25_000,
                                dashboard: DashboardMetrics.compute(records: LedgerEngine.derive(input)))
    #expect(g.estimatedRecordsToGoal == nil)
}
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
cd /Users/duarte/finance_tracker && xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'DashboardMetrics' in scope`.

- [ ] **Step 4: Implement the three metric types**

`Sources/FinanceTracker/Engine/DashboardMetrics.swift`:

```swift
import Foundation

struct DashboardMetrics: Sendable {
    var currentNetWorth: Double?
    var usableCash: Double?
    var latestChangeAmount: Double?
    var latestChangePercent: Double?
    var totalGrowth: Double?
    var bestChange: Double?
    var averageChange: Double?
    var recordCount: Int
    var averageSavingsRate: Double?

    static func compute(records: [DerivedRecord]) -> DashboardMetrics {
        guard let latest = records.last, let first = records.first else {
            return DashboardMetrics(recordCount: 0)
        }
        let changes = records.compactMap(\.changeAmount)
        let savingsRates = records.compactMap(\.savingsRate)

        return DashboardMetrics(
            currentNetWorth: latest.total,
            usableCash: latest.usable,
            latestChangeAmount: latest.changeAmount,
            latestChangePercent: latest.changePercent,
            totalGrowth: latest.total - first.total,
            bestChange: changes.max(),
            averageChange: changes.isEmpty ? nil : changes.reduce(0, +) / Double(changes.count),
            recordCount: records.count,
            averageSavingsRate: savingsRates.isEmpty
                ? nil
                : savingsRates.reduce(0, +) / Double(savingsRates.count))
    }
}
```

`Sources/FinanceTracker/Engine/AllocationMetrics.swift`:

```swift
import Foundation

struct AllocationSlice: Identifiable, Sendable {
    var id: UUID { accountID }
    let accountID: UUID
    let name: String
    let colorHex: String
    let amount: Double
    let share: Double
}

struct AllocationMetrics: Sendable {
    var slices: [AllocationSlice]
    var total: Double
    var usable: Double

    /// Splits the most recent record across accounts.
    static func compute(accounts: [AccountInfo], records: [DerivedRecord]) -> AllocationMetrics {
        guard let latest = records.last else {
            return AllocationMetrics(slices: [], total: 0, usable: 0)
        }
        let sorted = accounts.sorted { $0.sortOrder < $1.sortOrder }
        let slices = sorted.map { account in
            let amount = latest.amount(for: account.id)
            return AllocationSlice(
                accountID: account.id, name: account.name, colorHex: account.colorHex,
                amount: amount,
                share: latest.total == 0 ? 0 : amount / latest.total)
        }
        return AllocationMetrics(slices: slices, total: latest.total, usable: latest.usable)
    }
}
```

`Sources/FinanceTracker/Engine/GoalMetrics.swift`:

```swift
import Foundation

struct GoalMetrics: Sendable {
    var target: Double
    var current: Double
    var remaining: Double
    var progress: Double?
    /// nil when average change per record is not positive — the goal would
    /// never be reached at the current rate.
    var estimatedRecordsToGoal: Int?

    static func compute(target: Double, dashboard: DashboardMetrics) -> GoalMetrics {
        let current = dashboard.currentNetWorth ?? 0
        let remaining = max(0, target - current)
        var estimate: Int?
        if remaining == 0 {
            estimate = 0
        } else if let average = dashboard.averageChange, average > 0 {
            estimate = Int((remaining / average).rounded(.up))
        }
        return GoalMetrics(
            target: target, current: current, remaining: remaining,
            progress: target == 0 ? nil : current / target,
            estimatedRecordsToGoal: estimate)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Same command as Step 3. Expected: all dashboard, allocation and goal tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: add dashboard, allocation and goal metrics"
```

---

### Task 5: Projection engine

**Files:**
- Create: `Sources/FinanceTracker/Engine/ProjectionEngine.swift`,
  `Tests/FinanceTrackerTests/ProjectionEngineTests.swift`

**Interfaces:**
- Consumes: `PortfolioInput`, `DerivedRecord`
- Produces:
  - `struct ProjectionAssumptions` — `monthlyNetIncome, maxMonthlyExpenses, totalInvestedPerMonth, leftoverPerMonth, savingsRateOfIncome: Double, horizonMonths: Int, hasLeftoverDestination: Bool`
  - `struct ProjectionMonth` — `month: Int, date: Date, balances: [UUID: Double], netWorth: Double, usable: Double`
  - `struct Projection` — `assumptions: ProjectionAssumptions, months: [ProjectionMonth], monthsToGoal: Int?`, plus `netWorth(atMonth:) -> Double?`
  - `ProjectionEngine.project(_ input: PortfolioInput, records: [DerivedRecord], from startDate: Date) -> Projection`

- [ ] **Step 1: Write the failing tests**

`Tests/FinanceTrackerTests/ProjectionEngineTests.swift`:

```swift
import Testing
import Foundation
@testable import FinanceTracker

private let tol = 0.01

private func project() -> Projection {
    let input = WorkbookFixture.portfolio
    return ProjectionEngine.project(input,
                                    records: LedgerEngine.derive(input),
                                    from: WorkbookFixture.date(8, 8, 2026))
}

@Test func derivesAssumptionsFromInputsAndAccounts() {
    let a = project().assumptions
    #expect(abs(a.totalInvestedPerMonth - 200) < tol)
    #expect(abs(a.leftoverPerMonth - 717) < tol)
    #expect(abs(a.savingsRateOfIncome - 0.8209489) < 0.0000001)
    #expect(a.horizonMonths == 60)
    #expect(a.hasLeftoverDestination)
}

@Test func monthZeroIsTheLatestRecord() {
    let m = project().months[0]
    #expect(m.month == 0)
    #expect(abs(m.netWorth - 8409.74) < tol)
    #expect(abs(m.balances[WorkbookFixture.cttID]! - 6962.35) < tol)
}

@Test func monthOneMatchesTheWorkbook() {
    let m = project().months[1]
    #expect(abs(m.balances[WorkbookFixture.cttID]! - 7679.35) < tol)
    #expect(abs(m.balances[WorkbookFixture.revolutID]! - 450.59) < tol)
    #expect(abs(m.balances[WorkbookFixture.xtbID]! - 924.12) < tol)
    #expect(abs(m.balances[WorkbookFixture.edenredID]! - 277.63) < tol)
    #expect(abs(m.netWorth - 9331.69) < tol)
    #expect(abs(m.usable - 9054.06) < tol)
}

@Test func restrictedAccountsStayFlat() {
    let p = project()
    for m in p.months {
        #expect(abs(m.balances[WorkbookFixture.edenredID]! - 277.63) < tol)
    }
}

@Test func projectsOneThreeAndFiveYearHorizons() {
    let p = project()
    #expect(abs(p.netWorth(atMonth: 12)! - 19519.03) < 0.5)
    #expect(abs(p.netWorth(atMonth: 36)! - 42056.05) < 0.5)
    #expect(abs(p.netWorth(atMonth: 60)! - 65063.23) < 0.5)
}

@Test func horizonProducesMonthZeroThroughHorizonInclusive() {
    #expect(project().months.count == 61)
}

@Test func findsMonthsToGoal() {
    #expect(project().monthsToGoal == 18)
}

@Test func monthsToGoalIsNilWhenGoalIsNotReachedWithinHorizon() {
    var input = WorkbookFixture.portfolio
    input.targetNetWorth = 10_000_000
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(p.monthsToGoal == nil)
}

@Test func monthDatesAdvanceByOneMonth() {
    let p = project()
    let cal = Calendar(identifier: .gregorian)
    #expect(cal.component(.month, from: p.months[1].date) == 9)
    #expect(cal.component(.year, from: p.months[12].date) == 2027)
}

/// Without a leftover destination the surplus has nowhere to go. The engine
/// must report that rather than silently discarding the money.
@Test func flagsMissingLeftoverDestination() {
    var input = WorkbookFixture.portfolio
    input.accounts = input.accounts.map {
        var a = $0; a.isLeftoverDestination = false; return a
    }
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(p.assumptions.hasLeftoverDestination == false)
    #expect(abs(p.months[1].balances[WorkbookFixture.cttID]! - 6962.35) < tol)
}

@Test func projectingWithNoRecordsYieldsNoMonths() {
    var input = WorkbookFixture.portfolio
    input.records = []
    let p = ProjectionEngine.project(input, records: LedgerEngine.derive(input),
                                     from: WorkbookFixture.date(8, 8, 2026))
    #expect(p.months.isEmpty)
    #expect(p.monthsToGoal == nil)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/duarte/finance_tracker && xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'ProjectionEngine' in scope`.

- [ ] **Step 3: Implement**

`Sources/FinanceTracker/Engine/ProjectionEngine.swift`:

```swift
import Foundation

struct ProjectionAssumptions: Sendable {
    var monthlyNetIncome: Double
    var maxMonthlyExpenses: Double
    /// Sum of every account's monthly contribution — derived, never typed.
    var totalInvestedPerMonth: Double
    /// income - expenses - contributions — derived, never typed.
    var leftoverPerMonth: Double
    /// (income - expenses) / income — derived, never typed.
    var savingsRateOfIncome: Double
    var horizonMonths: Int
    var hasLeftoverDestination: Bool
}

struct ProjectionMonth: Identifiable, Sendable {
    var id: Int { month }
    let month: Int
    let date: Date
    let balances: [UUID: Double]
    let netWorth: Double
    let usable: Double
}

struct Projection: Sendable {
    var assumptions: ProjectionAssumptions
    var months: [ProjectionMonth]
    var monthsToGoal: Int?

    func netWorth(atMonth month: Int) -> Double? {
        months.first { $0.month == month }?.netWorth
    }
}

enum ProjectionEngine {
    /// Compounds each account at its own annual rate, monthly, then adds its
    /// fixed contribution. The leftover destination additionally receives
    /// income - expenses - contributions.
    static func project(_ input: PortfolioInput,
                        records: [DerivedRecord],
                        from startDate: Date) -> Projection {
        let accounts = input.activeAccountsSorted
        let totalInvested = accounts.reduce(0) { $0 + $1.monthlyContribution }
        let leftover = input.monthlyNetIncome - input.maxMonthlyExpenses - totalInvested
        let leftoverID = accounts.first(where: \.isLeftoverDestination)?.id

        let assumptions = ProjectionAssumptions(
            monthlyNetIncome: input.monthlyNetIncome,
            maxMonthlyExpenses: input.maxMonthlyExpenses,
            totalInvestedPerMonth: totalInvested,
            leftoverPerMonth: leftover,
            savingsRateOfIncome: input.monthlyNetIncome == 0
                ? 0
                : (input.monthlyNetIncome - input.maxMonthlyExpenses) / input.monthlyNetIncome,
            horizonMonths: input.projectionHorizonMonths,
            hasLeftoverDestination: leftoverID != nil)

        guard let latest = records.last else {
            return Projection(assumptions: assumptions, months: [], monthsToGoal: nil)
        }

        let usableIDs = Set(accounts.filter(\.includeInUsable).map(\.id))
        let calendar = Calendar(identifier: .gregorian)

        func snapshot(month: Int, balances: [UUID: Double]) -> ProjectionMonth {
            let netWorth = balances.values.reduce(0, +)
            let usable = balances.filter { usableIDs.contains($0.key) }.values.reduce(0, +)
            let date = calendar.date(byAdding: .month, value: month, to: startDate) ?? startDate
            return ProjectionMonth(month: month, date: date, balances: balances,
                                   netWorth: netWorth, usable: usable)
        }

        var balances = Dictionary(uniqueKeysWithValues:
            accounts.map { ($0.id, latest.amount(for: $0.id)) })
        var months = [snapshot(month: 0, balances: balances)]
        var monthsToGoal: Int? = months[0].netWorth >= input.targetNetWorth ? 0 : nil

        for month in 1...max(1, input.projectionHorizonMonths) {
            guard month <= input.projectionHorizonMonths else { break }
            for account in accounts {
                let monthlyGrowth = pow(1 + account.expectedAnnualReturn, 1.0 / 12.0)
                var value = (balances[account.id] ?? 0) * monthlyGrowth
                value += account.monthlyContribution
                if account.id == leftoverID { value += leftover }
                balances[account.id] = value
            }
            let snap = snapshot(month: month, balances: balances)
            months.append(snap)
            if monthsToGoal == nil, snap.netWorth >= input.targetNetWorth {
                monthsToGoal = month
            }
        }

        return Projection(assumptions: assumptions, months: months, monthsToGoal: monthsToGoal)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Same command as Step 2. Expected: all 11 projection tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add projection engine with per-account compounding"
```

---

### Task 6: SwiftData models, store mapping and seed data

**Files:**
- Create: `Sources/FinanceTracker/Models/Account.swift`,
  `Sources/FinanceTracker/Models/BalanceRecord.swift`,
  `Sources/FinanceTracker/Models/AppSettings.swift`,
  `Sources/FinanceTracker/Models/SeedData.swift`,
  `Sources/FinanceTracker/Services/PortfolioStore.swift`,
  `Tests/FinanceTrackerTests/SeedDataTests.swift`
- Modify: `Sources/FinanceTracker/App/FinanceTrackerApp.swift`

**Interfaces:**
- Consumes: `AccountKind`, `AccountInfo`, `RecordInput`, `PortfolioInput`
- Produces:
  - `@Model final class Account` — same stored properties as `AccountInfo`, plus `isArchived: Bool`, `archivedAt: Date?`; method `toInfo() -> AccountInfo`
  - `@Model final class BalanceRecord` — `id, date, note: String?, entries: [BalanceEntry]`
  - `@Model final class BalanceEntry` — `id, accountID: UUID, amount: Double`
  - `@Model final class AppSettings` — `targetNetWorth, monthlyNetIncome, maxMonthlyExpenses, projectionHorizonMonths`
  - `PortfolioStore.input(accounts:records:settings:) -> PortfolioInput` (filters archived accounts)
  - `SeedData.seedIfNeeded(_ context: ModelContext)`

- [ ] **Step 1: Write the models**

`Sources/FinanceTracker/Models/Account.swift`:

```swift
import Foundation
import SwiftData

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = AccountKind.main.rawValue
    var colorHex: String = "#1565C0"
    var sortOrder: Int = 0
    var includeInUsable: Bool = true
    var countsAsSavings: Bool = false
    var expectedAnnualReturn: Double = 0
    var monthlyContribution: Double = 0
    var isLeftoverDestination: Bool = false
    var isArchived: Bool = false
    var archivedAt: Date?

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .main }
        set { kindRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), name: String, kind: AccountKind, colorHex: String,
         sortOrder: Int, includeInUsable: Bool, countsAsSavings: Bool,
         expectedAnnualReturn: Double = 0, monthlyContribution: Double = 0,
         isLeftoverDestination: Bool = false) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.includeInUsable = includeInUsable
        self.countsAsSavings = countsAsSavings
        self.expectedAnnualReturn = expectedAnnualReturn
        self.monthlyContribution = monthlyContribution
        self.isLeftoverDestination = isLeftoverDestination
    }

    func toInfo() -> AccountInfo {
        AccountInfo(id: id, name: name, kind: kind, colorHex: colorHex,
                    sortOrder: sortOrder, includeInUsable: includeInUsable,
                    countsAsSavings: countsAsSavings,
                    expectedAnnualReturn: expectedAnnualReturn,
                    monthlyContribution: monthlyContribution,
                    isLeftoverDestination: isLeftoverDestination)
    }
}
```

`Sources/FinanceTracker/Models/BalanceRecord.swift`:

```swift
import Foundation
import SwiftData

@Model
final class BalanceRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    var note: String?
    @Relationship(deleteRule: .cascade) var entries: [BalanceEntry] = []

    init(id: UUID = UUID(), date: Date, note: String? = nil, entries: [BalanceEntry] = []) {
        self.id = id
        self.date = date
        self.note = note
        self.entries = entries
    }

    func amount(for accountID: UUID) -> Double {
        entries.first { $0.accountID == accountID }?.amount ?? 0
    }

    /// Rounds to cents — money is never stored with sub-cent noise.
    func setAmount(_ amount: Double, for accountID: UUID) {
        let rounded = (amount * 100).rounded() / 100
        if let existing = entries.first(where: { $0.accountID == accountID }) {
            existing.amount = rounded
        } else {
            entries.append(BalanceEntry(accountID: accountID, amount: rounded))
        }
    }

    func toInput() -> RecordInput {
        var balances: [UUID: Double] = [:]
        for entry in entries { balances[entry.accountID] = entry.amount }
        return RecordInput(id: id, date: date, balances: balances)
    }
}

@Model
final class BalanceEntry {
    var id: UUID = UUID()
    var accountID: UUID = UUID()
    var amount: Double = 0

    init(id: UUID = UUID(), accountID: UUID, amount: Double) {
        self.id = id
        self.accountID = accountID
        self.amount = amount
    }
}
```

`Sources/FinanceTracker/Models/AppSettings.swift`:

```swift
import Foundation
import SwiftData

@Model
final class AppSettings {
    var targetNetWorth: Double = 25_000
    var monthlyNetIncome: Double = 0
    var maxMonthlyExpenses: Double = 0
    var projectionHorizonMonths: Int = 60

    init(targetNetWorth: Double = 25_000, monthlyNetIncome: Double = 0,
         maxMonthlyExpenses: Double = 0, projectionHorizonMonths: Int = 60) {
        self.targetNetWorth = targetNetWorth
        self.monthlyNetIncome = monthlyNetIncome
        self.maxMonthlyExpenses = maxMonthlyExpenses
        self.projectionHorizonMonths = projectionHorizonMonths
    }
}
```

- [ ] **Step 2: Write the store mapping**

`Sources/FinanceTracker/Services/PortfolioStore.swift`:

```swift
import Foundation

/// Converts persisted models into the pure value types the engine consumes.
/// This is the only bridge between SwiftData and Engine.
enum PortfolioStore {
    static func input(accounts: [Account],
                      records: [BalanceRecord],
                      settings: AppSettings) -> PortfolioInput {
        PortfolioInput(
            accounts: accounts.filter { !$0.isArchived }
                              .sorted { $0.sortOrder < $1.sortOrder }
                              .map { $0.toInfo() },
            records: records.map { $0.toInput() },
            targetNetWorth: settings.targetNetWorth,
            monthlyNetIncome: settings.monthlyNetIncome,
            maxMonthlyExpenses: settings.maxMonthlyExpenses,
            projectionHorizonMonths: settings.projectionHorizonMonths)
    }

    /// Includes archived accounts, so historical totals stay intact after an
    /// account is archived.
    static func historicalInput(accounts: [Account],
                                records: [BalanceRecord],
                                settings: AppSettings) -> PortfolioInput {
        var input = self.input(accounts: accounts, records: records, settings: settings)
        input.accounts = accounts.sorted { $0.sortOrder < $1.sortOrder }.map { $0.toInfo() }
        return input
    }
}
```

- [ ] **Step 3: Write the seed data**

`Sources/FinanceTracker/Models/SeedData.swift`:

```swift
import Foundation
import SwiftData

/// Populates the store with the source workbook on first launch.
enum SeedData {
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard existing.isEmpty else { return }

        let ctt = Account(name: "Banco CTT", kind: .main, colorHex: "#2E7D32", sortOrder: 0,
                          includeInUsable: true, countsAsSavings: false,
                          isLeftoverDestination: true)
        let revolut = Account(name: "Revolut", kind: .savings, colorHex: "#1565C0", sortOrder: 1,
                              includeInUsable: true, countsAsSavings: true,
                              expectedAnnualReturn: 0.011, monthlyContribution: 100)
        let xtb = Account(name: "XTB", kind: .investment, colorHex: "#EF6C00", sortOrder: 2,
                          includeInUsable: true, countsAsSavings: true,
                          expectedAnnualReturn: 0.07, monthlyContribution: 100)
        let edenred = Account(name: "Edenred", kind: .restricted, colorHex: "#6A1B9A", sortOrder: 3,
                              includeInUsable: false, countsAsSavings: false)
        for account in [ctt, revolut, xtb, edenred] { context.insert(account) }

        let rows: [(Int, Int, Int, Double, Double, Double, Double)] = [
            (1, 7, 2026, 6285.73, 200.00, 710.85, 268.43),
            (1, 7, 2026, 6235.73, 250.00, 710.85, 268.43),
            (2, 7, 2026, 6265.73, 250.00, 710.85, 268.43),
            (3, 7, 2026, 6265.73, 250.02, 710.85, 268.43),
            (4, 8, 2026, 6962.35, 350.27, 819.49, 277.63),
        ]
        let calendar = Calendar(identifier: .gregorian)
        for (day, month, year, a, b, c, d) in rows {
            var comps = DateComponents()
            comps.day = day; comps.month = month; comps.year = year; comps.hour = 12
            let record = BalanceRecord(date: calendar.date(from: comps)!)
            context.insert(record)
            record.setAmount(a, for: ctt.id)
            record.setAmount(b, for: revolut.id)
            record.setAmount(c, for: xtb.id)
            record.setAmount(d, for: edenred.id)
        }

        context.insert(AppSettings(targetNetWorth: 25_000, monthlyNetIncome: 1_117,
                                   maxMonthlyExpenses: 200, projectionHorizonMonths: 60))
        try? context.save()
    }

    static func settings(in context: ModelContext) -> AppSettings {
        if let existing = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            return existing
        }
        let created = AppSettings()
        context.insert(created)
        return created
    }
}
```

- [ ] **Step 4: Write the failing seed test**

`Tests/FinanceTrackerTests/SeedDataTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import FinanceTracker

@MainActor
private func inMemoryContext() throws -> ModelContext {
    let schema = Schema([Account.self, BalanceRecord.self, BalanceEntry.self, AppSettings.self])
    let container = try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return ModelContext(container)
}

@MainActor
@Test func seedingCreatesTheWorkbookContents() throws {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)

    let accounts = try context.fetch(FetchDescriptor<Account>())
    let records = try context.fetch(FetchDescriptor<BalanceRecord>())
    #expect(accounts.count == 4)
    #expect(records.count == 5)
    #expect(accounts.filter(\.isLeftoverDestination).count == 1)
    #expect(accounts.first { $0.name == "Edenred" }?.includeInUsable == false)
    #expect(accounts.first { $0.name == "XTB" }?.countsAsSavings == true)
}

@MainActor
@Test func seedingIsIdempotent() throws {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)
    SeedData.seedIfNeeded(context)
    #expect(try context.fetch(FetchDescriptor<Account>()).count == 4)
}

@MainActor
@Test func seededDataReproducesTheWorkbookNumbers() throws {
    let context = try inMemoryContext()
    SeedData.seedIfNeeded(context)
    let input = PortfolioStore.input(
        accounts: try context.fetch(FetchDescriptor<Account>()),
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context))

    let metrics = DashboardMetrics.compute(records: LedgerEngine.derive(input))
    #expect(abs(metrics.currentNetWorth! - 8409.74) < 0.005)
    #expect(abs(metrics.usableCash! - 8132.11) < 0.005)
    #expect(abs(metrics.averageSavingsRate! - 0.0086429) < 0.0000001)
}
```

- [ ] **Step 5: Wire the container into the app**

Replace `Sources/FinanceTracker/App/FinanceTrackerApp.swift`:

```swift
import SwiftUI
import SwiftData

@main
struct FinanceTrackerApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Account.self, BalanceRecord.self, BalanceEntry.self, AppSettings.self])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("Could not create the data store: \(error)")
        }
        SeedData.seedIfNeeded(ModelContext(container))
    }

    var body: some Scene {
        WindowGroup {
            Text("Finance Tracker")
                .frame(minWidth: 900, minHeight: 600)
        }
        .modelContainer(container)
        .defaultSize(width: 1180, height: 800)
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd /Users/duarte/finance_tracker && xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: all 3 seed tests pass alongside the earlier suites.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: add SwiftData models, store mapping and workbook seed data"
```

---

### Task 7: Account lifecycle service

**Files:**
- Create: `Sources/FinanceTracker/Services/AccountService.swift`,
  `Tests/FinanceTrackerTests/AccountLifecycleTests.swift`

**Interfaces:**
- Consumes: `Account`, `BalanceRecord`, `AccountKind`
- Produces:
  - `enum AccountError: LocalizedError` — `.emptyName`, `.duplicateName`, `.cannotArchiveLeftoverDestination`, `.cannotArchiveLastAccount`, `.needsLeftoverDestination`
  - `AccountService.create(name:kind:colorHex:in:) throws -> Account`
  - `AccountService.archive(_:in:) throws`, `.restore(_:in:)`
  - `AccountService.delete(_:records:in:)`
  - `AccountService.setLeftoverDestination(_:accounts:)`
  - `AccountService.affectedRecordCount(for:records:) -> Int`
  - `AccountService.rename(_:to:in:) throws`

- [ ] **Step 1: Write the failing tests**

`Tests/FinanceTrackerTests/AccountLifecycleTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import FinanceTracker

@MainActor
private func seededContext() throws -> ModelContext {
    let schema = Schema([Account.self, BalanceRecord.self, BalanceEntry.self, AppSettings.self])
    let container = try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    SeedData.seedIfNeeded(context)
    return context
}

@MainActor
private func netWorth(_ context: ModelContext) throws -> Double {
    let input = PortfolioStore.input(
        accounts: try context.fetch(FetchDescriptor<Account>()),
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context))
    return LedgerEngine.derive(input).last?.total ?? 0
}

@MainActor
@Test func addingAnAccountLeavesHistoricalTotalsUnchanged() throws {
    let context = try seededContext()
    let before = try netWorth(context)
    _ = try AccountService.create(name: "Trade Republic", kind: .investment,
                                  colorHex: "#00838F", in: context)
    #expect(abs(try netWorth(context) - before) < 0.005)
}

@MainActor
@Test func newAccountsReadAsZeroInExistingRecords() throws {
    let context = try seededContext()
    let account = try AccountService.create(name: "Trade Republic", kind: .investment,
                                            colorHex: "#00838F", in: context)
    let records = try context.fetch(FetchDescriptor<BalanceRecord>())
    #expect(records.allSatisfy { $0.amount(for: account.id) == 0 })
}

@MainActor
@Test func createdAccountsInheritTypeDefaults() throws {
    let context = try seededContext()
    let restricted = try AccountService.create(name: "Meal card", kind: .restricted,
                                               colorHex: "#AD1457", in: context)
    #expect(restricted.includeInUsable == false)
    #expect(restricted.countsAsSavings == false)

    let savings = try AccountService.create(name: "Emergency", kind: .savings,
                                            colorHex: "#00695C", in: context)
    #expect(savings.includeInUsable == true)
    #expect(savings.countsAsSavings == true)
}

@MainActor
@Test func rejectsEmptyAndDuplicateNames() throws {
    let context = try seededContext()
    #expect(throws: AccountError.emptyName) {
        _ = try AccountService.create(name: "  ", kind: .main, colorHex: "#000000", in: context)
    }
    #expect(throws: AccountError.duplicateName) {
        _ = try AccountService.create(name: "revolut", kind: .savings,
                                      colorHex: "#000000", in: context)
    }
}

@MainActor
@Test func archivingPreservesHistoricalTotals() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let edenred = accounts.first { $0.name == "Edenred" }!
    let records = try context.fetch(FetchDescriptor<BalanceRecord>())
    let settings = SeedData.settings(in: context)
    let before = LedgerEngine.derive(
        PortfolioStore.historicalInput(accounts: accounts, records: records,
                                       settings: settings)).last!.total

    try AccountService.archive(edenred, in: context)

    let after = LedgerEngine.derive(
        PortfolioStore.historicalInput(
            accounts: try context.fetch(FetchDescriptor<Account>()),
            records: try context.fetch(FetchDescriptor<BalanceRecord>()),
            settings: settings)).last!.total
    #expect(abs(after - before) < 0.005)
    #expect(edenred.isArchived)
    #expect(edenred.archivedAt != nil)
}

@MainActor
@Test func cannotArchiveTheLeftoverDestination() throws {
    let context = try seededContext()
    let ctt = try context.fetch(FetchDescriptor<Account>()).first { $0.name == "Banco CTT" }!
    #expect(throws: AccountError.cannotArchiveLeftoverDestination) {
        try AccountService.archive(ctt, in: context)
    }
}

@MainActor
@Test func cannotArchiveTheLastActiveAccount() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let ctt = accounts.first { $0.name == "Banco CTT" }!
    for account in accounts where account !== ctt {
        try AccountService.archive(account, in: context)
    }
    AccountService.setLeftoverDestination(nil, accounts: accounts)
    #expect(throws: AccountError.cannotArchiveLastAccount) {
        try AccountService.archive(ctt, in: context)
    }
}

@MainActor
@Test func leftoverDestinationIsExclusive() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    let revolut = accounts.first { $0.name == "Revolut" }!
    AccountService.setLeftoverDestination(revolut, accounts: accounts)
    #expect(accounts.filter(\.isLeftoverDestination).count == 1)
    #expect(revolut.isLeftoverDestination)
}

@MainActor
@Test func togglingIncludeInUsableFlowsThroughToEveryRecord() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    accounts.first { $0.name == "Edenred" }!.includeInUsable = true
    let input = PortfolioStore.input(
        accounts: accounts,
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context))
    let derived = LedgerEngine.derive(input)
    #expect(abs(derived.last!.usable - 8409.74) < 0.005)
}

@MainActor
@Test func togglingCountsAsSavingsFlowsThroughToSavingsRate() throws {
    let context = try seededContext()
    let accounts = try context.fetch(FetchDescriptor<Account>())
    for account in accounts { account.countsAsSavings = false }
    let input = PortfolioStore.input(
        accounts: accounts,
        records: try context.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: context))
    #expect(LedgerEngine.derive(input).last!.savingsRate == 0)
}

@MainActor
@Test func hardDeleteRemovesTheAccountAndItsEntries() throws {
    let context = try seededContext()
    let edenred = try context.fetch(FetchDescriptor<Account>()).first { $0.name == "Edenred" }!
    let records = try context.fetch(FetchDescriptor<BalanceRecord>())
    #expect(AccountService.affectedRecordCount(for: edenred, records: records) == 5)

    AccountService.delete(edenred, records: records, in: context)

    #expect(try context.fetch(FetchDescriptor<Account>()).count == 3)
    let after = try context.fetch(FetchDescriptor<BalanceRecord>())
    #expect(after.allSatisfy { $0.amount(for: edenred.id) == 0 })
    let input = PortfolioStore.input(accounts: try context.fetch(FetchDescriptor<Account>()),
                                     records: after, settings: SeedData.settings(in: context))
    #expect(abs(LedgerEngine.derive(input).last!.total - 8132.11) < 0.005)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/duarte/finance_tracker && xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'AccountService' in scope`.

- [ ] **Step 3: Implement**

`Sources/FinanceTracker/Services/AccountService.swift`:

```swift
import Foundation
import SwiftData

enum AccountError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case cannotArchiveLeftoverDestination
    case cannotArchiveLastAccount
    case needsLeftoverDestination

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Give the account a name."
        case .duplicateName:
            "An account with that name already exists."
        case .cannotArchiveLeftoverDestination:
            "This account receives the monthly leftover in projections. Choose a different leftover destination first."
        case .cannotArchiveLastAccount:
            "You need at least one active account."
        case .needsLeftoverDestination:
            "Pick an account to receive the monthly leftover."
        }
    }
}

enum AccountService {
    static func create(name: String, kind: AccountKind, colorHex: String,
                       in context: ModelContext) throws -> Account {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AccountError.emptyName }

        let existing = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard !existing.contains(where: {
            !$0.isArchived && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) else { throw AccountError.duplicateName }

        let account = Account(
            name: trimmed, kind: kind, colorHex: colorHex,
            sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1,
            includeInUsable: kind.defaultIncludeInUsable,
            countsAsSavings: kind.defaultCountsAsSavings)
        context.insert(account)
        try? context.save()
        return account
    }

    static func rename(_ account: Account, to name: String, in context: ModelContext) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AccountError.emptyName }
        let existing = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard !existing.contains(where: {
            $0.id != account.id && !$0.isArchived
                && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) else { throw AccountError.duplicateName }
        account.name = trimmed
        try? context.save()
    }

    static func archive(_ account: Account, in context: ModelContext) throws {
        guard !account.isLeftoverDestination else {
            throw AccountError.cannotArchiveLeftoverDestination
        }
        let active = ((try? context.fetch(FetchDescriptor<Account>())) ?? [])
            .filter { !$0.isArchived }
        guard active.count > 1 else { throw AccountError.cannotArchiveLastAccount }

        account.isArchived = true
        account.archivedAt = Date()
        try? context.save()
    }

    static func restore(_ account: Account, in context: ModelContext) {
        account.isArchived = false
        account.archivedAt = nil
        try? context.save()
    }

    /// Exactly one account can be the leftover destination. Pass nil to clear.
    static func setLeftoverDestination(_ account: Account?, accounts: [Account]) {
        for candidate in accounts {
            candidate.isLeftoverDestination = (candidate.id == account?.id)
        }
    }

    static func affectedRecordCount(for account: Account, records: [BalanceRecord]) -> Int {
        records.filter { record in
            record.entries.contains { $0.accountID == account.id }
        }.count
    }

    /// Permanent: removes the account and strips its entries from history,
    /// which changes past totals. Always confirm before calling.
    static func delete(_ account: Account, records: [BalanceRecord], in context: ModelContext) {
        for record in records {
            record.entries.removeAll { $0.accountID == account.id }
        }
        context.delete(account)
        try? context.save()
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Same command as Step 2. Expected: all 11 lifecycle tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add account lifecycle service with archive and delete rules"
```

---

### Task 8: App shell, sidebar and shared components

**Files:**
- Create: `Sources/FinanceTracker/App/Section.swift`,
  `Sources/FinanceTracker/App/RootView.swift`,
  `Sources/FinanceTracker/Views/Components/KPITile.swift`,
  `Sources/FinanceTracker/Views/Components/CardSection.swift`
- Modify: `Sources/FinanceTracker/App/FinanceTrackerApp.swift`

**Interfaces:**
- Consumes: `PortfolioStore`, all engine types
- Produces:
  - `enum Section: String, CaseIterable, Identifiable` — `dashboard, balances, trends, allocation, goals, projections, accounts`, each with `title` and `icon`
  - `struct RootView: View`
  - `struct KPITile: View` — `init(title: String, value: String, caption: String? = nil, tint: Color = .primary)`
  - `struct CardSection<Content: View>: View` — `init(_ title: String, subtitle: String? = nil, @ViewBuilder content:)`
  - `extension Color { init(hex: String) }`

- [ ] **Step 1: Write the sidebar sections**

`Sources/FinanceTracker/App/Section.swift`:

```swift
import Foundation

enum Section: String, CaseIterable, Identifiable {
    case dashboard, balances, trends, allocation, goals, projections, accounts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .balances: "Balances"
        case .trends: "Trends"
        case .allocation: "Allocation"
        case .goals: "Goals"
        case .projections: "Projections"
        case .accounts: "Accounts"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .balances: "tablecells"
        case .trends: "chart.xyaxis.line"
        case .allocation: "chart.pie"
        case .goals: "target"
        case .projections: "chart.line.uptrend.xyaxis"
        case .accounts: "building.columns"
        }
    }
}
```

- [ ] **Step 2: Write the shared components**

`Sources/FinanceTracker/Views/Components/KPITile.swift`:

```swift
import SwiftUI

struct KPITile: View {
    let title: String
    let value: String
    var caption: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
```

`Sources/FinanceTracker/Views/Components/CardSection.swift`:

```swift
import SwiftUI

struct CardSection<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
    }
}
```

- [ ] **Step 3: Write the root view with placeholder destinations**

`Sources/FinanceTracker/App/RootView.swift`:

```swift
import SwiftUI
import SwiftData

struct RootView: View {
    @State private var selection: Section = .dashboard

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selection {
                case .dashboard: DashboardView()
                case .balances: BalancesView()
                case .trends: TrendsView()
                case .allocation: AllocationView()
                case .goals: GoalsView()
                case .projections: ProjectionsView()
                case .accounts: AccountsView()
                }
            }
            .navigationTitle(selection.title)
            .frame(minWidth: 720, minHeight: 560)
        }
    }
}
```

Create each of the seven views as a temporary stub in its final file so the project compiles —
for example `Sources/FinanceTracker/Views/DashboardView.swift`:

```swift
import SwiftUI

struct DashboardView: View {
    var body: some View { Text("Dashboard").foregroundStyle(.secondary) }
}
```

Repeat for `BalancesView`, `TrendsView`, `AllocationView`, `GoalsView`, `ProjectionsView`,
`AccountsView`. Later tasks replace each body.

- [ ] **Step 4: Point the app at RootView**

In `Sources/FinanceTracker/App/FinanceTrackerApp.swift`, replace the `WindowGroup` body
`Text("Finance Tracker")...` with:

```swift
            RootView()
```

- [ ] **Step 5: Build, launch and confirm the shell renders**

```bash
cd /Users/duarte/finance_tracker && ./scripts/build.sh && open build/Build/Products/Release/FinanceTracker.app
```

Expected: a window with a 7-item sidebar; clicking each item swaps the placeholder text.
Take a screenshot to confirm before moving on.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: add app shell with sidebar navigation and shared components"
```

---

### Task 9: Balances screen — the input table

**Files:**
- Modify: `Sources/FinanceTracker/Views/BalancesView.swift`

**Interfaces:**
- Consumes: `Account`, `BalanceRecord`, `PortfolioStore`, `LedgerEngine`, `Money`, `CardSection`
- Produces: nothing consumed by later tasks

- [ ] **Step 1: Implement the screen**

Replace `Sources/FinanceTracker/Views/BalancesView.swift`:

```swift
import SwiftUI
import SwiftData

struct BalancesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    private var derived: [DerivedRecord] {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records,
            settings: SeedData.settings(in: context)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 8) {
                    headerRow
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(derived) { row in
                        rowView(row)
                    }
                }
                .padding(16)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fill one row per recording date, oldest first.")
                    .font(.callout)
                Text("Editable columns are white; derived columns are grey and update automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Duplicate Last", systemImage: "doc.on.doc") { duplicateLast() }
                .disabled(records.isEmpty)
            Button("Add Record", systemImage: "plus") { addRecord() }
                .keyboardShortcut("n")
        }
        .padding(16)
    }

    private var headerRow: some View {
        GridRow {
            Text("Date").frame(width: 100, alignment: .leading)
            ForEach(activeAccounts) { account in
                Text(account.name).frame(width: 110, alignment: .trailing)
            }
            Text("Total").frame(width: 100)
            Text("Usable").frame(width: 100)
            Text("Change").frame(width: 90)
            Text("Change %").frame(width: 80)
            Text("Savings Rate").frame(width: 90)
            Color.clear.frame(width: 24)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func rowView(_ row: DerivedRecord) -> some View {
        if let record = records.first(where: { $0.id == row.id }) {
            GridRow {
                DatePicker("", selection: Binding(
                    get: { record.date },
                    set: { record.date = $0; try? context.save() }),
                    displayedComponents: .date)
                    .labelsHidden()
                    .frame(width: 100)

                ForEach(activeAccounts) { account in
                    TextField("", value: Binding(
                        get: { record.amount(for: account.id) },
                        set: { record.setAmount($0, for: account.id); try? context.save() }),
                        format: .number.precision(.fractionLength(2)))
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }

                derivedCell(Money.currency(row.total), width: 100)
                derivedCell(Money.currency(row.usable), width: 100)
                derivedCell(Money.currency(row.changeAmount), width: 90,
                            tint: (row.changeAmount ?? 0) < 0 ? .red : .primary)
                derivedCell(Money.percent(row.changePercent), width: 80)
                derivedCell(Money.percent(row.savingsRate), width: 90)

                Button {
                    context.delete(record)
                    try? context.save()
                } label: {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 24)
            }
        }
    }

    private func derivedCell(_ text: String, width: CGFloat, tint: Color = .primary) -> some View {
        Text(text)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: width, alignment: .trailing)
    }

    private func addRecord() {
        let record = BalanceRecord(date: Date())
        context.insert(record)
        for account in activeAccounts { record.setAmount(0, for: account.id) }
        try? context.save()
    }

    private func duplicateLast() {
        guard let last = records.max(by: { $0.date < $1.date }) else { return }
        let record = BalanceRecord(date: Date())
        context.insert(record)
        for account in activeAccounts {
            record.setAmount(last.amount(for: account.id), for: account.id)
        }
        try? context.save()
    }
}
```

- [ ] **Step 2: Build, launch and verify against the PDF**

```bash
cd /Users/duarte/finance_tracker && ./scripts/build.sh && open build/Build/Products/Release/FinanceTracker.app
```

Screenshot the Balances screen. Confirm five rows, and that row 5 reads
Total `8 410 €`, Usable `8 132 €`, Change `915 €`, Change % `12,2 %`, Savings Rate `2,8 %`,
and that row 1's three derived columns show `—`.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add balances input table with derived columns"
```

---

### Task 10: Dashboard screen

**Files:**
- Modify: `Sources/FinanceTracker/Views/DashboardView.swift`

**Interfaces:**
- Consumes: `DashboardMetrics`, `LedgerEngine`, `KPITile`, `CardSection`, `Money`

- [ ] **Step 1: Implement**

Replace `Sources/FinanceTracker/Views/DashboardView.swift`:

```swift
import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]

    private var derived: [DerivedRecord] {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records,
            settings: SeedData.settings(in: context)))
    }

    private var metrics: DashboardMetrics { DashboardMetrics.compute(records: derived) }

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Live summary of everything you log on the Balances screen.")
                    .font(.callout).foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 12) {
                    KPITile(title: "Current Net Worth",
                            value: Money.currency(metrics.currentNetWorth))
                    KPITile(title: "Usable Cash",
                            value: Money.currency(metrics.usableCash),
                            caption: "Excludes restricted accounts")
                    KPITile(title: "Latest Change (€)",
                            value: Money.currency(metrics.latestChangeAmount),
                            tint: (metrics.latestChangeAmount ?? 0) < 0 ? .red : .green)
                    KPITile(title: "Latest Change (%)",
                            value: Money.percent(metrics.latestChangePercent),
                            tint: (metrics.latestChangePercent ?? 0) < 0 ? .red : .green)
                    KPITile(title: "Total Growth",
                            value: Money.currency(metrics.totalGrowth),
                            caption: "Since first record")
                    KPITile(title: "Best Month",
                            value: Money.currency(metrics.bestChange))
                    KPITile(title: "Avg Monthly Change",
                            value: Money.currency(metrics.averageChange))
                    KPITile(title: "Records Tracked",
                            value: "\(metrics.recordCount)")
                    KPITile(title: "Avg Savings Rate",
                            value: Money.percent(metrics.averageSavingsRate))
                }

                CardSection("Net Worth vs Usable Cash") {
                    Chart {
                        ForEach(derived) { row in
                            LineMark(x: .value("Date", row.date),
                                     y: .value("Total", row.total))
                                .foregroundStyle(by: .value("Series", "Total"))
                                .symbol(.circle)
                            LineMark(x: .value("Date", row.date),
                                     y: .value("Usable", row.usable))
                                .foregroundStyle(by: .value("Series", "Usable"))
                                .symbol(.square)
                        }
                    }
                    .chartYAxis { AxisMarks(format: .number.notation(.compactName)) }
                    .frame(height: 240)
                }

                CardSection("Change per Record") {
                    Chart {
                        ForEach(derived.filter { $0.changeAmount != nil }) { row in
                            BarMark(x: .value("Date", row.date, unit: .day),
                                    y: .value("Change", row.changeAmount ?? 0))
                                .foregroundStyle((row.changeAmount ?? 0) < 0 ? .red : .green)
                        }
                    }
                    .frame(height: 200)
                }

                if derived.isEmpty {
                    ContentUnavailableView("No records yet",
                                           systemImage: "tablecells",
                                           description: Text("Add your first record on the Balances screen."))
                }
            }
            .padding(20)
        }
    }
}
```

- [ ] **Step 2: Build, launch and verify against the PDF**

```bash
cd /Users/duarte/finance_tracker && ./scripts/build.sh && open build/Build/Products/Release/FinanceTracker.app
```

Screenshot. Confirm the nine tiles read: `8 410 €`, `8 132 €`, `915 €`, `12,2 %`, `945 €`,
`915 €`, `236 €`, `5`, `0,9 %`.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add dashboard with KPI tiles and charts"
```

---

### Task 11: Trends and Allocation screens

**Files:**
- Modify: `Sources/FinanceTracker/Views/TrendsView.swift`,
  `Sources/FinanceTracker/Views/AllocationView.swift`

**Interfaces:**
- Consumes: `LedgerEngine`, `AllocationMetrics`, `CardSection`, `Money`, `Color(hex:)`

- [ ] **Step 1: Implement Trends**

Replace `Sources/FinanceTracker/Views/TrendsView.swift`:

```swift
import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    private var derived: [DerivedRecord] {
        LedgerEngine.derive(PortfolioStore.input(
            accounts: accounts, records: records,
            settings: SeedData.settings(in: context)))
    }

    private var palette: KeyValuePairs<String, Color> { [:] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Deeper visual breakdowns across your accounts.")
                    .font(.callout).foregroundStyle(.secondary)

                CardSection("Account Balances Over Time (stacked)") {
                    Chart {
                        ForEach(derived) { row in
                            ForEach(activeAccounts) { account in
                                AreaMark(x: .value("Date", row.date),
                                         y: .value("Amount", row.amount(for: account.id)))
                                    .foregroundStyle(by: .value("Account", account.name))
                            }
                        }
                    }
                    .chartForegroundStyleScale(range: activeAccounts.map { Color(hex: $0.colorHex) })
                    .frame(height: 240)
                }

                CardSection("Account Comparison") {
                    Chart {
                        ForEach(derived) { row in
                            ForEach(activeAccounts) { account in
                                LineMark(x: .value("Date", row.date),
                                         y: .value("Amount", row.amount(for: account.id)))
                                    .foregroundStyle(by: .value("Account", account.name))
                                    .symbol(by: .value("Account", account.name))
                            }
                        }
                    }
                    .chartForegroundStyleScale(range: activeAccounts.map { Color(hex: $0.colorHex) })
                    .frame(height: 240)
                }

                CardSection("Growth Rate per Record") {
                    Chart(derived.filter { $0.changePercent != nil }) { row in
                        LineMark(x: .value("Date", row.date),
                                 y: .value("Change %", (row.changePercent ?? 0) * 100))
                            .symbol(.circle)
                    }
                    .chartYAxis { AxisMarks(format: .number.precision(.fractionLength(1))) }
                    .frame(height: 200)
                }

                CardSection("Savings Rate per Record") {
                    Chart(derived.filter { $0.savingsRate != nil }) { row in
                        BarMark(x: .value("Date", row.date, unit: .day),
                                y: .value("Savings Rate", (row.savingsRate ?? 0) * 100))
                            .foregroundStyle(.teal)
                    }
                    .chartYAxis { AxisMarks(format: .number.precision(.fractionLength(1))) }
                    .frame(height: 200)
                }
            }
            .padding(20)
        }
    }
}
```

- [ ] **Step 2: Implement Allocation**

Replace `Sources/FinanceTracker/Views/AllocationView.swift`:

```swift
import SwiftUI
import SwiftData
import Charts

struct AllocationView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]

    private var allocation: AllocationMetrics {
        let input = PortfolioStore.input(accounts: accounts, records: records,
                                         settings: SeedData.settings(in: context))
        return AllocationMetrics.compute(accounts: input.accounts,
                                         records: LedgerEngine.derive(input))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Split of your most recently filled record.")
                    .font(.callout).foregroundStyle(.secondary)

                if allocation.slices.isEmpty {
                    ContentUnavailableView("Nothing to allocate yet",
                                           systemImage: "chart.pie",
                                           description: Text("Add a record on the Balances screen."))
                } else {
                    CardSection("Where your money sits") {
                        Chart(allocation.slices) { slice in
                            SectorMark(angle: .value("Amount", slice.amount),
                                       innerRadius: .ratio(0.55),
                                       angularInset: 1.5)
                                .foregroundStyle(by: .value("Account", slice.name))
                                .cornerRadius(4)
                        }
                        .chartForegroundStyleScale(
                            range: allocation.slices.map { Color(hex: $0.colorHex) })
                        .frame(height: 280)
                    }

                    CardSection("Breakdown") {
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                            GridRow {
                                Text("Account"); Text("Amount").gridColumnAlignment(.trailing)
                                Text("Share").gridColumnAlignment(.trailing)
                            }
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Divider().gridCellUnsizedAxes(.horizontal)
                            ForEach(allocation.slices) { slice in
                                GridRow {
                                    HStack(spacing: 8) {
                                        Circle().fill(Color(hex: slice.colorHex))
                                            .frame(width: 10, height: 10)
                                        Text(slice.name)
                                    }
                                    Text(Money.currency(slice.amount))
                                    Text(Money.percent(slice.share))
                                }
                            }
                            Divider().gridCellUnsizedAxes(.horizontal)
                            GridRow {
                                Text("Total").fontWeight(.semibold)
                                Text(Money.currency(allocation.total)).fontWeight(.semibold)
                                Text("100,0\u{202F}%").fontWeight(.semibold)
                            }
                            GridRow {
                                Text("Usable").foregroundStyle(.secondary)
                                Text(Money.currency(allocation.usable)).foregroundStyle(.secondary)
                                Text("")
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}
```

- [ ] **Step 3: Build, launch and verify against the PDF**

```bash
cd /Users/duarte/finance_tracker && ./scripts/build.sh && open build/Build/Products/Release/FinanceTracker.app
```

Screenshot both screens. Allocation must read 82,8 % / 4,2 % / 9,7 % / 3,3 %, total `8 410 €`,
usable `8 132 €`.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add trends charts and allocation breakdown"
```

---

### Task 12: Goals screen

**Files:**
- Modify: `Sources/FinanceTracker/Views/GoalsView.swift`

**Interfaces:**
- Consumes: `GoalMetrics`, `DashboardMetrics`, `AppSettings`, `KPITile`, `CardSection`, `Money`

- [ ] **Step 1: Implement**

Replace `Sources/FinanceTracker/Views/GoalsView.swift`:

```swift
import SwiftUI
import SwiftData
import Charts

struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]

    private var settings: AppSettings { SeedData.settings(in: context) }

    private var dashboard: DashboardMetrics {
        DashboardMetrics.compute(records: LedgerEngine.derive(
            PortfolioStore.input(accounts: accounts, records: records, settings: settings)))
    }

    private var goal: GoalMetrics {
        GoalMetrics.compute(target: settings.targetNetWorth, dashboard: dashboard)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Set a target and track progress towards it.")
                    .font(.callout).foregroundStyle(.secondary)

                CardSection("Target") {
                    HStack {
                        Text("Target Net Worth")
                        Spacer()
                        TextField("", value: Binding(
                            get: { settings.targetNetWorth },
                            set: { settings.targetNetWorth = $0; try? context.save() }),
                            format: .number.precision(.fractionLength(0)))
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                        Text("€")
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    KPITile(title: "Current Net Worth", value: Money.currency(goal.current))
                    KPITile(title: "Remaining to Goal", value: Money.currency(goal.remaining))
                    KPITile(title: "Progress", value: Money.percent(goal.progress),
                            tint: (goal.progress ?? 0) >= 1 ? .green : .primary)
                    KPITile(title: "Avg Change per Record",
                            value: Money.currency(dashboard.averageChange))
                    KPITile(title: "Est. Records to Goal",
                            value: goal.estimatedRecordsToGoal.map(String.init) ?? Money.dash,
                            caption: goal.estimatedRecordsToGoal == nil
                                ? "Needs a positive average change" : nil)
                }

                CardSection("Goal Progress") {
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView(value: min(goal.progress ?? 0, 1))
                            .progressViewStyle(.linear)
                        Chart {
                            BarMark(x: .value("Amount", goal.current),
                                    y: .value("Goal", "Progress"))
                                .foregroundStyle(.green)
                            BarMark(x: .value("Amount", goal.remaining),
                                    y: .value("Goal", "Progress"))
                                .foregroundStyle(.gray.opacity(0.35))
                        }
                        .frame(height: 90)
                        HStack {
                            Label(Money.currency(goal.current), systemImage: "square.fill")
                                .foregroundStyle(.green)
                            Label(Money.currency(goal.remaining), systemImage: "square.fill")
                                .foregroundStyle(.gray)
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(20)
        }
    }
}
```

- [ ] **Step 2: Build, launch and verify**

```bash
cd /Users/duarte/finance_tracker && ./scripts/build.sh && open build/Build/Products/Release/FinanceTracker.app
```

Expected: target `25 000`, current `8 410 €`, remaining `16 590 €`, progress `33,6 %`,
avg change `236 €`, est. records `71`.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add goals screen with progress tracking"
```

---

### Task 13: Projections screen

**Files:**
- Modify: `Sources/FinanceTracker/Views/ProjectionsView.swift`

**Interfaces:**
- Consumes: `ProjectionEngine`, `Projection`, `AppSettings`, `Account`, `KPITile`, `CardSection`, `Money`

- [ ] **Step 1: Implement**

Replace `Sources/FinanceTracker/Views/ProjectionsView.swift`:

```swift
import SwiftUI
import SwiftData
import Charts

struct ProjectionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BalanceRecord.date) private var records: [BalanceRecord]

    private var settings: AppSettings { SeedData.settings(in: context) }
    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    private var projection: Projection {
        let input = PortfolioStore.input(accounts: accounts, records: records, settings: settings)
        return ProjectionEngine.project(input,
                                        records: LedgerEngine.derive(input),
                                        from: Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Set your assumptions. The forecast updates automatically.")
                    .font(.callout).foregroundStyle(.secondary)

                if !projection.assumptions.hasLeftoverDestination {
                    Label("No leftover destination is set, so the monthly surplus is not being allocated. Pick one on the Accounts screen.",
                          systemImage: "exclamationmark.triangle.fill")
                        .padding(12)
                        .background(.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                }

                HStack(alignment: .top, spacing: 16) {
                    assumptionsCard
                    outlookCard
                }

                CardSection("Projected Net Worth") {
                    Chart(projection.months) { month in
                        LineMark(x: .value("Month", month.month),
                                 y: .value("Net Worth", month.netWorth))
                        RuleMark(y: .value("Target", settings.targetNetWorth))
                            .foregroundStyle(.gray)
                            .lineStyle(StrokeStyle(dash: [4, 4]))
                    }
                    .chartYAxis { AxisMarks(format: .number.notation(.compactName)) }
                    .frame(height: 250)
                }

                CardSection("Month by Month") {
                    ScrollView(.vertical) {
                        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
                            GridRow {
                                Text("Month").gridColumnAlignment(.leading)
                                Text("Date").gridColumnAlignment(.leading)
                                ForEach(activeAccounts) { Text($0.name) }
                                Text("Net Worth")
                                Text("Usable")
                            }
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Divider().gridCellUnsizedAxes(.horizontal)
                            ForEach(projection.months) { month in
                                GridRow {
                                    Text("\(month.month)").gridColumnAlignment(.leading)
                                    Text(month.date, format: .dateTime.month(.abbreviated).year())
                                        .gridColumnAlignment(.leading)
                                    ForEach(activeAccounts) { account in
                                        Text(Money.currency(month.balances[account.id] ?? 0))
                                    }
                                    Text(Money.currency(month.netWorth)).fontWeight(.medium)
                                    Text(Money.currency(month.usable))
                                }
                                .font(.system(.caption, design: .rounded))
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }
            }
            .padding(20)
        }
    }

    private var assumptionsCard: some View {
        CardSection("Assumptions", subtitle: "Grey rows are derived from the others.") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Monthly Net Income")
                    numberField(get: { settings.monthlyNetIncome },
                                set: { settings.monthlyNetIncome = $0 })
                }
                GridRow {
                    Text("Max Monthly Expenses")
                    numberField(get: { settings.maxMonthlyExpenses },
                                set: { settings.maxMonthlyExpenses = $0 })
                }
                GridRow {
                    Text("Projection Horizon (months)")
                    TextField("", value: Binding(
                        get: { settings.projectionHorizonMonths },
                        set: { settings.projectionHorizonMonths = max(1, min(600, $0));
                               try? context.save() }),
                        format: .number)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                derivedRow("Total Invested / month",
                           Money.currency(projection.assumptions.totalInvestedPerMonth))
                derivedRow("Leftover / month",
                           Money.currency(projection.assumptions.leftoverPerMonth))
                derivedRow("Savings Rate (of income)",
                           Money.percent(projection.assumptions.savingsRateOfIncome))
            }
            Text("Per-account contributions and expected returns live on the Accounts screen.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var outlookCard: some View {
        CardSection("Outlook") {
            VStack(spacing: 12) {
                KPITile(title: "Projected in 1 Year",
                        value: Money.currency(projection.netWorth(atMonth: 12)))
                KPITile(title: "Projected in 3 Years",
                        value: Money.currency(projection.netWorth(atMonth: 36)))
                KPITile(title: "Projected in 5 Years",
                        value: Money.currency(projection.netWorth(atMonth: 60)))
                KPITile(title: "At Horizon (\(settings.projectionHorizonMonths) mo)",
                        value: Money.currency(projection.months.last?.netWorth))
                KPITile(title: "Months to Goal",
                        value: projection.monthsToGoal.map(String.init) ?? Money.dash,
                        caption: projection.monthsToGoal == nil
                            ? "Not reached within the horizon" : nil)
            }
        }
        .frame(width: 260)
    }

    private func numberField(get: @escaping () -> Double,
                             set: @escaping (Double) -> Void) -> some View {
        TextField("", value: Binding(get: get, set: { set($0); try? context.save() }),
                  format: .number.precision(.fractionLength(0)))
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(width: 120)
    }

    private func derivedRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
        }
    }
}
```

- [ ] **Step 2: Build, launch and verify against the PDF**

```bash
cd /Users/duarte/finance_tracker && ./scripts/build.sh && open build/Build/Products/Release/FinanceTracker.app
```

Expected: total invested `200 €`, leftover `717 €`, savings rate of income `82,1 %`,
months to goal `18`, and month 1 showing Banco CTT `7 679 €`, Revolut `451 €`, XTB `924 €`.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add projections screen with assumptions and forecast table"
```

---

### Task 14: Accounts screen

**Files:**
- Modify: `Sources/FinanceTracker/Views/AccountsView.swift`

**Interfaces:**
- Consumes: `AccountService`, `AccountError`, `Account`, `AccountKind`, `CardSection`, `Money`

- [ ] **Step 1: Implement**

Replace `Sources/FinanceTracker/Views/AccountsView.swift`:

```swift
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
                    Text("Create accounts, change how they are treated, or archive the ones you no longer use.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("New Account", systemImage: "plus") { showingNewAccount = true }
                }

                ForEach(active) { account in
                    accountCard(account)
                }

                if !archived.isEmpty {
                    CardSection("Archived", subtitle: "Still counted in past records.") {
                        ForEach(archived) { account in
                            HStack {
                                Text(account.name)
                                Spacer()
                                Button("Restore") { AccountService.restore(account, in: context) }
                                Button("Delete…", role: .destructive) { pendingDeletion = account }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showingNewAccount) { newAccountSheet }
        .alert("Couldn't do that", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            deletionPrompt,
            isPresented: .constant(pendingDeletion != nil),
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
                        set: { try? AccountService.rename(account, to: $0, in: context) }))
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

                HStack(spacing: 20) {
                    LabeledContent("Monthly contribution") {
                        TextField("", value: Binding(
                            get: { account.monthlyContribution },
                            set: { account.monthlyContribution = $0; try? context.save() }),
                            format: .number.precision(.fractionLength(0)))
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                    LabeledContent("Expected annual return") {
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
                Text(kindExplanation)
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { resetSheet() }
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
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
            let account = try AccountService.create(
                name: newName, kind: newKind, colorHex: newColor.hexString, in: context)
            _ = account
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

extension Color {
    var hexString: String {
        let native = NSColor(self).usingColorSpace(.sRGB) ?? .systemBlue
        return String(format: "#%02X%02X%02X",
                      Int(native.redComponent * 255),
                      Int(native.greenComponent * 255),
                      Int(native.blueComponent * 255))
    }
}
```

- [ ] **Step 2: Build, launch and exercise the lifecycle by hand**

```bash
cd /Users/duarte/finance_tracker && ./scripts/build.sh && open build/Build/Products/Release/FinanceTracker.app
```

Verify, taking screenshots: creating an account adds a column on Balances with 0 values and
leaves the dashboard net worth at `8 410 €`; archiving Banco CTT is refused with the
leftover-destination message; toggling Edenred's "Counts toward Usable Cash" moves Usable to
`8 410 €`; the delete confirmation names 5 records.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add accounts screen with create, edit, archive and delete"
```

---

### Task 15: JSON export and import

**Files:**
- Create: `Sources/FinanceTracker/Services/BackupService.swift`,
  `Tests/FinanceTrackerTests/BackupServiceTests.swift`
- Modify: `Sources/FinanceTracker/App/FinanceTrackerApp.swift`

**Interfaces:**
- Consumes: `Account`, `BalanceRecord`, `AppSettings`
- Produces: `BackupService.export(accounts:records:settings:) throws -> Data`,
  `BackupService.restore(from:into:) throws` (replaces all data)

- [ ] **Step 1: Write the failing test**

`Tests/FinanceTrackerTests/BackupServiceTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import FinanceTracker

@MainActor
private func context() throws -> ModelContext {
    let schema = Schema([Account.self, BalanceRecord.self, BalanceEntry.self, AppSettings.self])
    return ModelContext(try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
}

@MainActor
@Test func exportThenRestoreRoundTripsEveryNumber() throws {
    let source = try context()
    SeedData.seedIfNeeded(source)
    let data = try BackupService.export(
        accounts: try source.fetch(FetchDescriptor<Account>()),
        records: try source.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: source))

    let target = try context()
    try BackupService.restore(from: data, into: target)

    let input = PortfolioStore.input(
        accounts: try target.fetch(FetchDescriptor<Account>()),
        records: try target.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: target))
    let metrics = DashboardMetrics.compute(records: LedgerEngine.derive(input))
    #expect(abs(metrics.currentNetWorth! - 8409.74) < 0.005)
    #expect(abs(metrics.averageSavingsRate! - 0.0086429) < 0.0000001)
    #expect(try target.fetch(FetchDescriptor<Account>()).count == 4)
}

@MainActor
@Test func restoreReplacesExistingData() throws {
    let source = try context()
    SeedData.seedIfNeeded(source)
    let data = try BackupService.export(
        accounts: try source.fetch(FetchDescriptor<Account>()),
        records: try source.fetch(FetchDescriptor<BalanceRecord>()),
        settings: SeedData.settings(in: source))

    let target = try context()
    SeedData.seedIfNeeded(target)
    try BackupService.restore(from: data, into: target)
    #expect(try target.fetch(FetchDescriptor<Account>()).count == 4)
    #expect(try target.fetch(FetchDescriptor<BalanceRecord>()).count == 5)
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/duarte/finance_tracker && xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'BackupService' in scope`.

- [ ] **Step 3: Implement**

`Sources/FinanceTracker/Services/BackupService.swift`:

```swift
import Foundation
import SwiftData

struct BackupFile: Codable {
    struct AccountDTO: Codable {
        var id: UUID, name: String, kind: String, colorHex: String, sortOrder: Int
        var includeInUsable: Bool, countsAsSavings: Bool
        var expectedAnnualReturn: Double, monthlyContribution: Double
        var isLeftoverDestination: Bool, isArchived: Bool
    }
    struct RecordDTO: Codable {
        var id: UUID, date: Date, note: String?, balances: [String: Double]
    }
    struct SettingsDTO: Codable {
        var targetNetWorth: Double, monthlyNetIncome: Double
        var maxMonthlyExpenses: Double, projectionHorizonMonths: Int
    }
    var version = 1
    var accounts: [AccountDTO]
    var records: [RecordDTO]
    var settings: SettingsDTO
}

enum BackupService {
    static func export(accounts: [Account], records: [BalanceRecord],
                       settings: AppSettings) throws -> Data {
        let file = BackupFile(
            accounts: accounts.map {
                .init(id: $0.id, name: $0.name, kind: $0.kind.rawValue, colorHex: $0.colorHex,
                      sortOrder: $0.sortOrder, includeInUsable: $0.includeInUsable,
                      countsAsSavings: $0.countsAsSavings,
                      expectedAnnualReturn: $0.expectedAnnualReturn,
                      monthlyContribution: $0.monthlyContribution,
                      isLeftoverDestination: $0.isLeftoverDestination,
                      isArchived: $0.isArchived)
            },
            records: records.map { record in
                var balances: [String: Double] = [:]
                for entry in record.entries { balances[entry.accountID.uuidString] = entry.amount }
                return .init(id: record.id, date: record.date, note: record.note,
                             balances: balances)
            },
            settings: .init(targetNetWorth: settings.targetNetWorth,
                            monthlyNetIncome: settings.monthlyNetIncome,
                            maxMonthlyExpenses: settings.maxMonthlyExpenses,
                            projectionHorizonMonths: settings.projectionHorizonMonths))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    /// Replaces everything in the store with the backup's contents.
    static func restore(from data: Data, into context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(BackupFile.self, from: data)

        for account in (try? context.fetch(FetchDescriptor<Account>())) ?? [] {
            context.delete(account)
        }
        for record in (try? context.fetch(FetchDescriptor<BalanceRecord>())) ?? [] {
            context.delete(record)
        }
        for settings in (try? context.fetch(FetchDescriptor<AppSettings>())) ?? [] {
            context.delete(settings)
        }

        for dto in file.accounts {
            let account = Account(
                id: dto.id, name: dto.name, kind: AccountKind(rawValue: dto.kind) ?? .main,
                colorHex: dto.colorHex, sortOrder: dto.sortOrder,
                includeInUsable: dto.includeInUsable, countsAsSavings: dto.countsAsSavings,
                expectedAnnualReturn: dto.expectedAnnualReturn,
                monthlyContribution: dto.monthlyContribution,
                isLeftoverDestination: dto.isLeftoverDestination)
            account.isArchived = dto.isArchived
            context.insert(account)
        }
        for dto in file.records {
            let record = BalanceRecord(id: dto.id, date: dto.date, note: dto.note)
            context.insert(record)
            for (key, amount) in dto.balances {
                if let accountID = UUID(uuidString: key) {
                    record.setAmount(amount, for: accountID)
                }
            }
        }
        context.insert(AppSettings(
            targetNetWorth: file.settings.targetNetWorth,
            monthlyNetIncome: file.settings.monthlyNetIncome,
            maxMonthlyExpenses: file.settings.maxMonthlyExpenses,
            projectionHorizonMonths: file.settings.projectionHorizonMonths))
        try context.save()
    }
}
```

- [ ] **Step 4: Add File menu commands**

In `Sources/FinanceTracker/App/FinanceTrackerApp.swift`, add after `.defaultSize(...)`:

```swift
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Export Backup…") { exportBackup() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Import Backup…") { importBackup() }
            }
        }
```

And add these methods to `FinanceTrackerApp`:

```swift
    @MainActor
    private func exportBackup() {
        let context = ModelContext(container)
        guard let accounts = try? context.fetch(FetchDescriptor<Account>()),
              let records = try? context.fetch(FetchDescriptor<BalanceRecord>()),
              let data = try? BackupService.export(accounts: accounts, records: records,
                                                   settings: SeedData.settings(in: context))
        else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "finance-tracker-backup.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    @MainActor
    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        try? BackupService.restore(from: data, into: ModelContext(container))
    }
```

Add `import AppKit` and `import UniformTypeIdentifiers` at the top of the file.

- [ ] **Step 5: Run the tests to verify they pass**

Same command as Step 2. Expected: both backup tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: add JSON backup export and import"
```

---

### Task 16: Full verification and install

**Files:**
- Create: `scripts/install.sh`, `README.md`

- [ ] **Step 1: Run the complete test suite**

```bash
cd /Users/duarte/finance_tracker && xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `TEST SUCCEEDED`, zero failures. Record the exact test count.

- [ ] **Step 2: Write the install script**

`scripts/install.sh`:

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
rm -rf "/Applications/Finance Tracker.app"
cp -R build/Build/Products/Release/FinanceTracker.app "/Applications/Finance Tracker.app"
echo "Installed to /Applications/Finance Tracker.app"
```

Then `chmod +x scripts/install.sh`.

- [ ] **Step 3: Verify every screen against the PDF by hand**

Build, launch, and screenshot all seven screens. Check each value in the
"Reference values" table at the top of this plan. Any mismatch is a bug — fix it and
re-run the suite before continuing.

- [ ] **Step 4: Verify account management end to end**

In the running app: create an account, confirm the dashboard net worth is unchanged and a
new column appears on Balances; archive it; restore it; delete it and confirm the dialog
names the affected record count. Export a backup, import it back, confirm the numbers survive.

- [ ] **Step 5: Write the README**

`README.md` covering: what the app is, how to build (`./scripts/build.sh`), how to install
(`./scripts/install.sh`), where data lives, how backups work, and the engine/models/views
layering rule.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "docs: add README and install script"
```

---

## Self-review

**Spec coverage:** All six workbook sheets map to tasks 10–14; account management to tasks 7
and 14; storage and seeding to task 6; export/import to task 15 (spec: "Export/Import to CSV
or JSON" — JSON only, which satisfies it); formatting to task 2; error handling to tasks 4, 5,
7 and 13.

**Placeholders:** None — every step contains the code or command it needs.

**Type consistency:** `AccountInfo`, `RecordInput`, `PortfolioInput`, `DerivedRecord`,
`DashboardMetrics`, `AllocationMetrics`/`AllocationSlice`, `GoalMetrics`,
`ProjectionAssumptions`/`ProjectionMonth`/`Projection`, `Money`, `Color(hex:)`/`hexString`,
`AccountService`/`AccountError`, `PortfolioStore.input`/`historicalInput`,
`SeedData.seedIfNeeded`/`settings(in:)`, `BackupService.export`/`restore` — each defined once
and used with matching signatures throughout.
