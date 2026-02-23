# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
npm run dev      # start dev server at http://localhost:3000
npm run build    # production build (also type-checks)
npm run lint     # ESLint via next lint
npm run start    # serve the production build
```

There is no test framework configured in this project.

## Architecture

**Next.js 14 App Router** single-page application. There is only one route (`/`). The entire app lives in `src/app/page.tsx`, which acts as the top-level orchestrator — it owns global state, connects hooks to components, and renders the two tab views (Dashboard and Expenses).

**No backend, no server state.** All data is persisted in `localStorage`. There are no API routes.

### Data flow

```
localStorage
    ↕ (via useExpenses hook)
src/app/page.tsx            ← owns all state: expenses[], filters, modal open flags
    ├── Dashboard            ← receives stats (derived), emits month/category click events
    ├── ExpenseList          ← receives filtered expenses + filter state
    ├── ExpenseForm          ← controlled form; emits ExpenseFormData on submit
    ├── ImportModal          ← reads a CSV file, emits ExpenseFormData[] to importExpenses()
    └── [export component]   ← receives expenses[], handles file generation internally
```

### Core types — `src/types/expense.ts`

The `Expense` type is the fundamental data unit. Key constraint: `date` is always a plain `YYYY-MM-DD` string (not an ISO datetime). When constructing a `Date` object from it, always append `T00:00:00` to avoid timezone offset shifting the date:

```ts
const d = new Date(expense.date + 'T00:00:00');
```

`Category` is a closed union (`'Food' | 'Transportation' | 'Entertainment' | 'Shopping' | 'Bills' | 'Other'`). The `CATEGORIES` array is the source of truth for iteration. Adding a category requires updating both.

`ExpenseFormData.amount` is a raw string (direct form input). It gets parsed to a float via `parseFloat()` inside `addExpense`/`updateExpense`/`importExpenses`. Never pass a pre-parsed number into these callbacks.

### Hooks — `src/hooks/useExpenses.ts`

Three hooks, all consumed in `page.tsx`:

- **`useExpenses()`** — manages the expense array in state, syncs to `localStorage` via two effects (one loads on mount, one saves on every change). Returns CRUD callbacks + `loaded: boolean` (used to prevent hydration flash).
- **`useFilteredExpenses(expenses, filters)`** — pure `useMemo` filter; no state.
- **`useExpenseStats(expenses)`** — pure `useMemo` that computes all dashboard stats (monthly trend for last 6 months, category breakdown, totals, daily average). Expensive but memoised correctly.

### Dependencies note

`date-fns` and `recharts` are listed in `package.json` but are not imported anywhere in the current source. All date formatting uses native `Intl` / `Date`, and charts are rendered with custom CSS bar/progress elements. `uuid` (via `uuidv4`) is actively used in `useExpenses.ts` to generate expense IDs.

### Library modules — `src/lib/`

- **`utils.ts`** — formatting helpers (`formatCurrency`, `formatDate`, `getTodayISO`, category color/emoji maps) and the generic `exportToCSV` utility. The `exportToCSV` function determines column order from `Object.keys(data[0])`, so insertion order of properties in the mapping object controls column order.
- **`csvImport.ts`** — full RFC-4180 CSV parser (handles quoted fields, escaped double-quotes) plus a `guessCategory()` function that matches descriptions against regex patterns tuned for German bank export formats (N26/DKB style: columns `Booking Date`, `Partner Name`, `Amount (EUR)`). Positive amounts are skipped (treated as income). The importer returns `ImportedExpense[]` with a `selected: boolean` flag for the pre-import review UI.
- **`cloudExport.ts`** (branch: `feature-data-export-v3`) — export templates, destination routing, localStorage-based export history, and report generators (CSV, Tax Report HTML, Monthly Summary HTML, Category JSON). **Important:** cloud destinations (`email`, `google-sheets`, `dropbox`, `onedrive`) are UI-only mockups. `executeExport()` only triggers real file operations for `download` (file save) and `link` (generates a placeholder URL). All other destinations simulate a delay and log to history without any real network call. Export history is capped at 50 entries.

### Styling

Tailwind CSS only — no component library. The modal pattern used throughout is: `fixed inset-0 z-50` backdrop + `relative bg-white` sheet, with `items-end sm:items-center` to render as a bottom sheet on mobile and a centred dialog on desktop.

### Custom commands

`/document-feature <file-or-feature>` — project-level slash command (`.claude/commands/document-feature.md`) that generates Doxygen-style documentation and saves it as `{filename}.documentation.md`.

### Export feature branches

Three branches implement progressively more complex export systems. See `code-analysis.md` for a full comparison. The `main` branch has no export functionality.

| Branch | Approach | New files |
|--------|----------|-----------|
| `feature-data-export-v1` | Inline CSV, one button | 0 |
| `feature-data-export-v2` | Multi-format modal with preview | `ExportModal.tsx`, `exporters.ts` |
| `feature-data-export-v3` | Cloud hub with history & scheduling UI | `CloudExportHub.tsx`, `cloudExport.ts` |
