# Finance Tracker — Design

Date: 2026-08-08
Status: Approved

## Purpose

Replace a spreadsheet-based net-worth tracker with a native macOS app that keeps every
piece of the workbook's functionality, and adds what the spreadsheet cannot do: creating,
editing, reordering, archiving and deleting bank accounts without rewriting formulas.

The workbook has six sheets — Dashboard, Monthly Balances, Trends & Charts, Current
Allocation, Goals, Projections — all driven by four hardcoded account columns. The app
generalises those hardcoded columns into an arbitrary set of
user-managed accounts, while reproducing the workbook's numbers exactly.

## Decisions

| Decision | Choice |
|---|---|
| Stack | Native SwiftUI + SwiftData + Swift Charts, macOS 26 |
| Project generation | XcodeGen (`project.yml`) → `.xcodeproj` → `xcodebuild` |
| Storage | Local SwiftData store in the app container, plus JSON export/import |
| Distribution | Ad-hoc codesigned local `.app`; no Apple Developer account, no expiry |
| Account model | Type preset fills defaults; all flags individually editable |
| Adding an account | Reads as 0 € in pre-existing records; historical totals unchanged |
| Removing an account | Archive by default (history preserved); hard delete behind confirmation |
| Navigation | Sidebar, one item per sheet, plus Accounts |
| Seed data | Full workbook contents on first launch |

## Architecture

Three layers, with a hard dependency rule: **the engine must not import SwiftData.**

```
Views (SwiftUI)  →  Engine (pure value types)  →  Models (SwiftData)
       └───────────────── reads ──────────────────────┘
```

- **Models** — persistence only. `Account`, `BalanceRecord`, `BalanceEntry`, `AppSettings`.
- **Engine** — every derived number. Plain structs and functions over value-type snapshots,
  unit-testable with no store, no app launch, no UI.
- **Views** — one screen per sidebar item; they render engine output and write to models.

Nothing derived is ever persisted. Total, Usable, Change, Savings Rate, allocation shares,
goal progress and projections are recomputed from inputs on every read. This is what makes
an account flag edit re-derive all history instantly, and what makes it impossible for the
dashboard to disagree with the table.

### Why not store computed columns

The spreadsheet caches formula results because that is what spreadsheets do. Persisting them
here would buy render speed at a dataset size (hundreds of records, lifetime) where speed is
already free, and would introduce staleness bugs on every account-flag edit. Rejected.

## Data model

### Account

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `name` | String | Non-empty, unique among non-archived accounts |
| `kind` | enum | `main`, `savings`, `investment`, `restricted` |
| `colorHex` | String | Chart colour |
| `sortOrder` | Int | Column order on Balances |
| `includeInUsable` | Bool | False for restricted accounts such as a food-only card |
| `countsAsSavings` | Bool | Feeds the Savings Rate numerator |
| `expectedAnnualReturn` | Double | Decimal fraction, e.g. `0.07` |
| `monthlyContribution` | Decimal | Projection contribution |
| `isLeftoverDestination` | Bool | Exactly one across all active accounts |
| `isArchived` | Bool | |
| `archivedAt` | Date? | |

Type presets, applied at creation and freely overridable afterwards:

| Kind | includeInUsable | countsAsSavings | return | leftover |
|---|---|---|---|---|
| `main` | true | false | 0 % | candidate |
| `savings` | true | true | user-set | no |
| `investment` | true | true | user-set | no |
| `restricted` | **false** | false | 0 % | no |

### BalanceRecord

`id`, `date`, optional `note`, and `entries: [BalanceEntry]`.

Dates are **not** unique — the source workbook contains two records on 01/07/2026, and that
must remain legal.

### BalanceEntry

`id`, `accountID`, `amount: Decimal`. A missing entry for an active account reads as 0.

### AppSettings (singleton)

`targetNetWorth`, `monthlyNetIncome`, `maxMonthlyExpenses`, `projectionHorizonMonths`.

## Engine formulas

All verified against the source PDF.

### Per record

Given records sorted by date ascending, with `prev` the preceding record:

- `total = Σ entries.amount`
- `usable = Σ entries.amount where account.includeInUsable`
- `change€ = total − prev.total` — undefined for the first record
- `change% = change€ ÷ prev.total` — undefined if `prev.total == 0`
- `savingsRate = Σ (entry.amount − prev.entry.amount) for accounts where countsAsSavings ÷ prev.total`

Worked example, using the sample portfolio: Savings 700 → 800 (+100), Brokerage 600 → 700
(+100); (100 + 100) ÷ 2 500 = **8 %** ✓

### Dashboard KPIs

| KPI | Formula | Expected |
|---|---|---|
| Current Net Worth | latest total | 8 410 € |
| Usable Cash | latest usable | 8 132 € |
| Latest Change € / % | latest record's change | 915 € / 12,2 % |
| Total Growth | latest total − first total | 945 € |
| Best Month | max change€ | 915 € |
| Avg Monthly Change | mean of defined change€ | 236 € |
| Records Tracked | count | 5 |
| Avg Savings Rate | mean of defined savings rates | 0,9 % |

### Allocation

Latest record only. Per account: `amount`, `share = amount ÷ total`. Plus total and usable.

### Goals

- `remaining = max(0, target − currentNetWorth)`
- `progress% = currentNetWorth ÷ target`
- `estRecordsToGoal = ⌈remaining ÷ avgChangePerRecord⌉` → 16 590 ÷ 236,25 = **71** ✓
- Undefined when `avgChangePerRecord <= 0`; renders as "—" with an explanation.

### Projections

Derived assumption cells, never typed:

- `totalInvestedPerMonth = Σ account.monthlyContribution` → 200 €
- `leftoverPerMonth = monthlyNetIncome − maxMonthlyExpenses − totalInvestedPerMonth` → 717 €
- `savingsRateOfIncome = (monthlyNetIncome − maxMonthlyExpenses) ÷ monthlyNetIncome` → 82,1 %

Month 0 = latest record's balances. For each subsequent month, per account:

```
balance = balance × (1 + expectedAnnualReturn)^(1/12)
        + monthlyContribution
        + (isLeftoverDestination ? leftoverPerMonth : 0)
```

Verified against the sample portfolio: month 1 Current Account = 1 500 + 1 700 − 500 =
**2 700 €** ✓; Brokerage = 700 × 1,06^(1/12) + 150 = **853 €** ✓; Savings = 800 ×
1,01^(1/12) + 150 = **951 €** ✓; Meal Card flat at **100 €** ✓.

Outputs: month-by-month table, net worth at months 12 / 36 / 60, value at horizon, and
`monthsToGoal` = first month where net worth ≥ target → **18** ✓.

## Screens

1. **Dashboard** — 9 KPI tiles; Net Worth vs Usable line chart; Change per Record bars.
2. **Balances** — editable table, one column per active account, derived columns read-only
   and visually muted (the workbook's "fill the blue cells" convention). Add, duplicate and
   delete rows; new rows default to today's date.
3. **Trends** — stacked balances over time, account comparison, growth rate %, savings rate.
4. **Allocation** — latest-record table plus donut chart.
5. **Goals** — target input, remaining, progress %, est. records to goal, progress bar.
6. **Projections** — assumptions panel with typed and derived cells visually distinguished;
   1/3/5-year and horizon figures; months to goal; full month table and chart.
7. **Accounts** — create, edit, reorder, archive/restore, hard-delete.

## Error and edge-case handling

| Situation | Behaviour |
|---|---|
| 0 or 1 record | Change and Savings Rate render "—", not 0 |
| Previous total is 0 | Percentages render "—" (no division by zero) |
| No leftover destination | Projections shows an inline prompt to pick one; no silent loss |
| Archiving the leftover account | Blocked, with an explanation |
| Archiving the last active account | Blocked |
| Hard delete | Confirmation naming how many records will be altered |
| Non-numeric input | Rejected at the field |
| Negative balances | Allowed — overdrafts are real |
| Avg change ≤ 0 | Est. records to goal renders "—" |

## Formatting

EUR throughout, matching the workbook: `8 410 €` — narrow-space thousands separator, comma
decimal, symbol trailing. Percentages to one decimal (`12,2 %`). Currency in tables shows
cents where the source does (`6 285,73 €`); KPI tiles round to whole euros.

## Testing

Engine tests, asserting against the source PDF value by value:

- All 5 records: total, usable, change €, change %, savings rate
- All 9 dashboard KPIs
- Allocation amounts and shares (82,8 % / 4,2 % / 9,7 % / 3,3 %)
- Goals: remaining 16 590 €, progress 33,6 %, 71 records
- Projections: months 0, 1, 12, 18, 60 and months-to-goal

Behavioural tests for the account lifecycle:

- Adding an account leaves all historical totals unchanged
- Archiving preserves historical totals
- Toggling `includeInUsable` flows through to Usable on every record
- Toggling `countsAsSavings` flows through to Savings Rate
- Leftover-destination uniqueness is enforced

Plus a manual verification pass: build, launch, screenshot every screen, and compare
rendered numbers against the PDF. Green tests alone do not count as done.

## Out of scope

Transaction-level tracking, bank API sync, multi-currency, budgets and spending categories,
iOS/iPad, multi-user, cloud sync.
