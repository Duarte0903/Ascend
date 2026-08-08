# Ascend

A native macOS net-worth tracker that replaces the `net_worth_tracker_pro` Excel workbook,
and adds what a spreadsheet cannot do: creating, editing, archiving and deleting bank
accounts without rewriting any formulas.

## Build and install

```bash
./scripts/install.sh
```

Builds, ad-hoc signs, and copies the app to `/Applications/Ascend.app`.

To build without installing:

```bash
./scripts/build.sh
```

To run the tests:

```bash
./scripts/test.sh
```

### Why it never expires

The app is **ad-hoc signed** (`codesign -s -`). Unlike iOS free provisioning, an ad-hoc
signature has no expiry, so there is nothing to renew after 7 days. Gatekeeper only
challenges apps carrying a quarantine flag, which is attached at download — an app built
locally never gets one. No Apple Developer account is needed, not even a free one.

## The screens

| Screen | What it does |
|---|---|
| Dashboard | Nine KPIs, net worth vs usable cash, change per record |
| Balances | The input table — one row per recording date, one column per account |
| Trends | Stacked balances, account comparison, growth rate, savings rate |
| Allocation | Where your money sits, from the most recent record |
| Goals | Target, remaining, progress, estimated records to goal |
| Projections | Assumptions, 1/3/5-year outlook, months to goal, month-by-month table |
| Accounts | Create, edit, archive, restore, delete |

## How accounts work

Each account carries four independent properties, pre-filled from its type but always
editable:

- **Counts toward Usable Cash** — off for restricted accounts like a food card
- **Counts toward Savings Rate** — on for savings and investment accounts
- **Monthly contribution** — used by projections
- **Expected annual return** — used by projections

Exactly one account is the **leftover destination**: in projections it receives
`income − expenses − contributions` each month.

Adding an account reads as 0 € in earlier records, so historical totals never change.
Archiving keeps history intact; hard-deleting strips the account from past records and
says how many it will affect before you confirm.

## The formulas

| Value | Formula |
|---|---|
| Total | Σ all balances |
| Usable | Σ balances where *counts toward Usable Cash* |
| Change €, % | vs. the previous record |
| **Savings Rate** | Σ Δbalance of savings accounts ÷ **previous** total |
| Total Growth | latest total − first total |
| Est. records to goal | ⌈remaining ÷ average change⌉ |
| Projection, monthly | `balance × (1+r)^(1/12) + contribution`, leftover account also gets the surplus |

Values that are genuinely undefined — a change with no prior record, a percentage over a
zero total — render as `—`, never as `0`.

Records are ordered by date, then by creation time. Two records may share a date (the
source workbook has two on 01/07/2026) and their order decides the savings-rate column,
so it is preserved explicitly rather than left to chance.

## Architecture

```
Views (SwiftUI)  →  Engine (pure value types)  →  Models (SwiftData)
```

**`Engine/` must never import SwiftData or SwiftUI.** It holds every derived number as
plain structs, which is what makes the whole calculation suite testable without launching
the app. Only user input is persisted — Total, Usable, Change, Savings Rate and the
projections are recomputed on every read, so an account-flag edit re-derives all history
instantly and the dashboard can never disagree with the table.

`Services/PortfolioStore.swift` is the only bridge between the two worlds.

## Data and backups

Data lives in a local SwiftData store in the app's own container. **File → Export Backup…**
(⇧⌘E) writes a JSON file; **File → Import Backup…** replaces the store from one.

On first launch the app seeds itself with the original workbook: four accounts, five
records, the 25 000 € goal and the projection assumptions.

## Tests

```bash
./scripts/test.sh
```

62 tests. The suite asserts the engine against the source PDF value by value, checks the
account lifecycle (adding an account leaves historical totals untouched, archiving
preserves them, flags flow through to Usable and Savings Rate), round-trips backups, and
verifies the exact strings each screen renders — `8 410 €`, `12,2 %`, `2,8 %`, `82,8 %`,
`71` records to goal, `18` months to goal.
