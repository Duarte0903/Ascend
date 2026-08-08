<p align="center">
  <img src="docs/icon.png" width="132" alt="Ascend app icon" />
</p>

<h1 align="center">Ascend</h1>

<p align="center">
  A native macOS app for tracking your net worth over time.
</p>

---

Ascend records **balance snapshots**, not transactions. Whenever you feel like it, you
write down what each of your accounts is worth on that date — and it works out everything
else: what your net worth is, how much of it you can actually spend, how fast it is
growing, how much of your income you are putting away, when you will hit your target, and
where you will be in five years.

It began as a replacement for a spreadsheet that did the same job with four hardcoded
columns. The point of rewriting it was the thing a spreadsheet cannot do: **create,
rename, retype, reorder, archive and delete accounts** without touching a single formula,
and without ever silently changing the history you have already logged.

It is a single-user, local, offline app. No accounts, no sync, no bank connections, no
telemetry. Your data sits in a file on your Mac.

### What it is not

Not a budgeting app and not an expense tracker. There are no transactions or spending
categories, because it never asks where your money went — only what it adds up to today.

## Screens

| Screen | What it does |
|---|---|
| **Dashboard** | Nine headline figures, net worth against usable cash, change per record |
| **Balances** | The input table — one row per date, one column per account, everything else calculated |
| **Trends** | Stacked balances, account comparison, growth rate, savings rate |
| **Allocation** | Where your money sits right now, as a donut and a table |
| **Goals** | Set a target; see progress, what's left, and how many more records it will take |
| **Projections** | Your assumptions, the 1/3/5-year outlook, months to goal, and a month-by-month forecast |
| **Accounts** | Create, describe, retype, recolour, reorder, archive, restore and delete accounts |

Dashboard, Balances and Trends share a **period filter** — all time, 3, 6 or 12 months, or
year to date — and Trends can hide individual accounts. Filtering never rewrites history:
a visible record's change is still measured against the record that really preceded it,
even when that one falls outside the window.

Appearance follows macOS, with a manual override under **View ▸ Appearance** (⌃⌘1/2/3).

## How accounts work

Every account carries a description and a type, plus four properties that are pre-filled
from its type and then entirely its own:

- **Counts toward Usable Cash** — off for restricted accounts like a food card
- **Counts toward Savings Rate** — on for savings and investment accounts
- **Monthly contribution** — used by projections
- **Expected annual return** — used by projections

Exactly one account is the **leftover destination**: in projections it receives
`income − expenses − contributions` each month.

**Account types are yours to edit.** Main, Savings, Investment and Restricted are just the
starting rows — rename them, change their defaults, delete the ones you don't use, or add
your own (Crypto, Pension, Property) from **Account Types…** on the Accounts screen. A type
supplies defaults when an account is created and never rewrites an account afterwards,
because doing so would retroactively change historical Usable and Savings Rate figures.
A type still in use cannot be deleted.

Adding an account reads as 0 € in earlier records, so historical totals never change.
Archiving keeps history intact. Hard-deleting strips the account from past records, and
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
| Total invested / month | Σ contributions of accounts that are usable **or** savings |
| Leftover / month | income − expenses − total invested |
| Projection, monthly | `balance × (1+r)^(1/12) + contribution`, leftover account also gets the surplus |

A contribution to an account that is neither usable cash nor savings — an employer-loaded
food card, say — is not funded from your salary, so it counts toward neither the invested
total nor the leftover deduction. The balance still grows by it.

Values that are genuinely undefined — a change with no prior record, a percentage over a
zero total — render as `—`, never as `0`.

Records are ordered by date, then by creation time. Two records may share a date, and their
order decides the savings-rate column, so it is preserved explicitly rather than left to
chance.

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

## Build and install

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
./scripts/install.sh
```

Builds, ad-hoc signs, and copies the app to `/Applications/Ascend.app`. Ad-hoc signatures
do not expire and a locally built app carries no quarantine flag, so it just opens — no
Apple Developer account needed, ever.

Build without installing, run the tests, or regenerate the icon:

```bash
./scripts/build.sh
./scripts/test.sh
swift scripts/make-icon.swift
```

`Ascend.xcodeproj` is generated from `project.yml` and deliberately not committed.

## Data and backups

Data lives in a local SwiftData store on your Mac. **File → Export Backup…** (⇧⌘E) writes a
JSON file carrying accounts, types, records and settings; **File → Import Backup…**
replaces the store from one.

On first launch the app seeds itself with the four accounts and five records carried over
from the original spreadsheet, plus its goal and projection assumptions, so no screen starts
empty. Those figures are the author's own starting point — rename the accounts, delete the
records, or import a backup to make it yours.

## Tests

```bash
./scripts/test.sh
```

104 tests, none of which need the app to launch. They pin the engine's arithmetic value by
value, the account and type lifecycles (adding an account leaves historical totals
untouched; archiving preserves them; editing a type never rewrites existing accounts),
number parsing in both `1.234,56` and `1,234.56` conventions, period filtering, backup
round-trips, and the exact strings each screen renders.
