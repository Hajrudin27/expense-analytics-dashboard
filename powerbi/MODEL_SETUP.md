# Building the report — step by step

Everything below takes about 45–60 minutes the first time. Follow it in order.

---

## 0. Getting access to Power BI

Use Power BI Desktop on Windows, or the Power BI service in a browser with an account and workspace that permit semantic-model editing. Access depends on tenant settings, permissions and licensing; this repository cannot guarantee university-account access.

Microsoft documents the [current browser model-editing workflow and permissions](https://learn.microsoft.com/en-us/power-bi/transform-model/service-edit-data-models). Check access before starting. The committed CSVs, SQL and Excel tables can be inspected independently of Power BI.

## 1. Load the data

### In the browser — use Excel, not CSV

Use `powerbi/ExpenseAnalytics.xlsx`, which contains six named Excel Tables, as a convenient single source. In the service's **Create / Get data** flow, choose the available Excel connector and load all six tables into one semantic model. Menus and local-file upload support depend on the current service experience and tenant configuration; do not create six unrelated semantic models.

If the service cannot import the local workbook in your environment, use Desktop or an approved connector. The workbook contains data tables, not the relationships, DAX measures or report layout; create those in the steps below.

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

A person consumed shares and may also have paid expenses. This model intentionally leaves the payer relationship inactive and activates it within `Amount Paid` using `USERELATIONSHIP`. Active relationships from a dimension to two different fact tables are not inherently invalid; the choice here keeps payer filtering explicit.

The six relationships above support the included DAX. Keep `fact_settlement` separate unless adding settlement measures deliberately; the screenshot also shows an optional date-to-settlement relationship.

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

**Bottom left — balances before settlements.** Table or diverging bar:

- Rows: `dim_person[person_name]`
- Values: `[Amount Paid]`, `[Person Share]`, `[Net Balance]`
- Conditional formatting on `[Net Balance]`: red below zero, green above

**Bottom right — detail.** With PostgreSQL, import `analytics.v_expense_detail` separately. It has one row per person-share, so do not sum its repeated expense total. With Excel only, build the detail table from the six imported tables; the SQL view is not in the workbook.

**Slicers** across the top: `dim_date[year_month]`, `dim_category[category_group]`, `dim_person[person_name]`.

---

The reconciliation card should be checked with the person slicer cleared. That slicer filters `fact_expense_share`, while the payer relationship to `fact_expense` remains inactive outside `Amount Paid`. A non-zero card in that context is not automatically corrupt source data. The SQL reconciliation view also misses expenses with no share rows; validate completeness separately for new imports.

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
