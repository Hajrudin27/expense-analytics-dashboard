# Building the report — step by step

Everything below takes about 45–60 minutes the first time. Follow it in order.

---

## 0. Getting access to Power BI

Power BI Desktop is **Windows-only** — it does not run on macOS. Two viable routes:

| Route | How | Notes |
|---|---|---|
| **Browser (recommended)** | [app.powerbi.com](https://app.powerbi.com) with your `@student.sdu.dk` account | Free licence covers everything you need in **My Workspace**. Since the July 2026 update the browser can build semantic models, relationships and DAX measures. |
| **Windows** | Power BI Desktop on a Windows PC, Parallels, or a lab machine at SDU | Full feature set, and `.pbix` files save locally. |

**Test your access first — it takes three minutes:**

1. Go to `app.powerbi.com` and sign in with your SDU account.
2. Open **My Workspace** in the left sidebar.
3. Click **+ New** and see whether **Semantic model** / **Report** are available.

If those options are greyed out or you get a "your organisation has disabled" message, SDU's tenant has restricted Power BI. In that case ask SDU IT to enable it for your account, or use a Windows machine on campus. Don't burn a day fighting the tenant — the fallback in the main README works too.

---

## 1. Load the data

### In the browser — use Excel, not CSV

**Do not use the CSV button.** In the Power BI Service, each CSV upload creates its *own*
semantic model. Six CSVs means six isolated models that cannot be related to each other, and
the whole data model falls apart.

Use `ExpenseAnalytics.xlsx` instead. It holds all six tables in one workbook, each formatted
as a real Excel Table, which the Service reads into a **single** model.

1. **My workspace** → **New report** (or **+ Create**)
2. Choose **Excel**
3. Upload `powerbi/ExpenseAnalytics.xlsx`
4. When asked what to import, tick all six tables:
   `dim_person`, `dim_category`, `dim_date`, `fact_expense`, `fact_expense_share`, `fact_settlement`

### In Desktop

**Home** → **Get data** → **Excel workbook** → same file, tick all six tables.

Better still: **Get data** → **PostgreSQL database**, if you've loaded `sql/` into a local
database. Connecting to a real database rather than a flat file is the more impressive
version, and it's the same click path you'd use against a company data source.

### Check the column types after loading

Power BI usually guesses right, but confirm:

- `amount_dkk`, `share_amount_dkk` → **Decimal number**
- `expense_date`, `settlement_date`, `date_key`, `joined_date` → **Date**
- `is_weekend`, `is_payer` → **True/False**

Getting this wrong is the single most common reason measures return blank.

---

## 2. Wire up the relationships

In **Model view**, drag these connections. All are **one-to-many**, single direction, from the dimension to the fact:

| From (one side) | To (many side) | Active? |
|---|---|---|
| `dim_date[date_key]` | `fact_expense[expense_date]` | Yes |
| `dim_date[date_key]` | `fact_expense_share[expense_date]` | Yes |
| `dim_category[category_id]` | `fact_expense[category_id]` | Yes |
| `dim_category[category_id]` | `fact_expense_share[category_id]` | Yes |
| `dim_person[person_id]` | `fact_expense_share[person_id]` | Yes |
| `dim_person[person_id]` | `fact_expense[paid_by_person_id]` | **No — inactive** |

The last one matters. A person relates to an expense in two different ways — they *consumed* part of it, and separately they may have *paid* for it. Two active relationships between the same pair of tables is ambiguous, so Power BI won't allow it. Keep the "paid by" relationship inactive and activate it only inside the `Amount Paid` measure with `USERELATIONSHIP`.

**This is the thing to be able to explain in an interview.** It's the difference between having clicked through a tutorial and having actually modelled something.

Finally: select `dim_date`, then **Table tools** → **Mark as date table** → pick `date_key`. Time intelligence functions (`DATEADD`, `TOTALYTD`) silently misbehave without it.

---

## 3. Add the measures

Open `measures.dax` and add them one at a time: right-click `fact_expense_share` → **New measure** → paste → Enter.

Add them in the order they appear in the file — the later ones reference the earlier ones.

Then format them, because unformatted numbers look unfinished:

- `Total Spend`, `Person Share`, `Amount Paid`, `Net Balance`, `Variable Spend`, `Fixed Spend` → Currency, 0 decimals, `kr` symbol
- `Spend MoM %`, `Fixed Cost Ratio`, `Category % of Total`, `Weekend Spend %` → Percentage, 1 decimal
- `Expense Count`, `Active Housemates` → Whole number

---

## 4. Build the page

One page, four zones. Resist adding more — a focused single page reads as deliberate; six half-finished tabs read as a tutorial.

**Top row — KPI cards (four across):**

| Card | Measure |
|---|---|
| Total Spend | `[Total Spend]` |
| Spend per Housemate | `[Spend per Housemate]` |
| Fixed Cost Ratio | `[Fixed Cost Ratio]` |
| Data Quality | `[Reconciliation Status]` |

**Middle left — the trend.** Line chart (or line-and-clustered-column):

- X axis: `dim_date[year_month]`
- Lines: `[Total Spend]` and `[Variable Spend]`

Two lines, not one. The gap between them *is* the story: total is flat because rent dominates, while variable spend moves with the seasons.

**Middle right — where the money goes.** Bar chart, `dim_category[category_name]` by `[Total Spend]`, sorted descending. Add `[Category % of Total]` as a tooltip.

**Bottom left — who owes whom.** Table or diverging bar:

- Rows: `dim_person[person_name]`
- Values: `[Amount Paid]`, `[Person Share]`, `[Net Balance]`
- Conditional formatting on `[Net Balance]`: red below zero, green above

**Bottom right — detail.** Table from `v_expense_detail` columns: date, category, merchant, paid by, amount. This is the drill-down that proves the numbers are real.

**Slicers** across the top: `dim_date[year_month]`, `dim_category[category_group]`, `dim_person[person_name]`.

---

## 5. Polish (15 minutes, disproportionate payoff)

- **Title the page** something specific: "Shared Household Expenses — Sep 2025 to Aug 2026", not "Dashboard".
- **Pick one accent colour** and use it consistently. **View** → **Themes** → pick a restrained one.
- **Sort the bar chart** descending by value, not alphabetically.
- **Turn off** chart gridlines you don't need.
- **Check it in one glance:** can someone answer "are we overspending, and who owes money?" in five seconds? If not, something is too busy.

---

## 6. Export for GitHub

1. **Screenshot the page** at full width → save as `docs/screenshots/dashboard-overview.png`.
2. Screenshot the **Model view** showing the relationships → `docs/screenshots/data-model.png`. Reviewers who know Power BI look at this one first.
3. If you're on Desktop, save the `.pbix` into `powerbi/`.
4. If you're in the browser, **File** → **Download this file** to get the `.pbix`.

   If your Power BI runs through a Defender proxy — the URL reads `app.powerbi.com.mcas.ms`
   rather than `app.powerbi.com` — the download may be blocked by session policy. That's not
   worth fighting. Ship the screenshots; the README and SQL carry most of the weight either way.

A `.pbix` is a binary file, so nobody can read it on GitHub. **The screenshots and the README are what actually get looked at.** Spend your time there.
