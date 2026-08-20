"""
Generate a realistic 12-month dataset of shared household expenses.

Produces a small star schema ready for Power BI:
  dim_person, dim_category, dim_date, fact_expense, fact_expense_share, fact_settlement

Deterministic (fixed seed) so the CSVs and the SQL seed always agree.
"""

import csv
import os
import random
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP

SEED = 27
random.seed(SEED)

OUT = os.path.join(os.path.dirname(__file__), "..", "data")
os.makedirs(OUT, exist_ok=True)

START = date(2025, 9, 1)
END = date(2026, 8, 31)

# --------------------------------------------------------------------------
# Dimensions
# --------------------------------------------------------------------------

PEOPLE = [
    (1, "Hajrudin", "hajrudin@example.com", date(2025, 9, 1)),
    (2, "Sofie",    "sofie@example.com",    date(2025, 9, 1)),
    (3, "Mikkel",   "mikkel@example.com",   date(2025, 9, 1)),
    (4, "Amina",    "amina@example.com",    date(2025, 9, 1)),
    (5, "Jonas",    "jonas@example.com",    date(2026, 1, 15)),  # moves in mid-year
]

# category_id, name, group, monthly cadence, typical amount range (DKK), merchants
CATEGORIES = [
    (1, "Rent",              "Fixed",     "monthly",  (8400, 8400),  ["Boligforening Vejle"]),
    (2, "Utilities",         "Fixed",     "monthly",  (620, 1750),   ["Norlys", "Ørsted", "TREFOR"]),
    (3, "Internet",          "Fixed",     "monthly",  (299, 349),    ["Hiper", "Fibia"]),
    (4, "Groceries",         "Variable",  "frequent", (95, 780),     ["Netto", "Føtex", "Rema 1000", "Lidl", "Bilka"]),
    (5, "Household Supplies","Variable",  "weekly",   (45, 320),     ["Matas", "Normal", "IKEA", "Silvan"]),
    (6, "Dining Out",        "Discretionary", "weekly", (120, 690),  ["Cafe Vivaldi", "Sunset Boulevard", "Jensens", "Kebabhouse"]),
    (7, "Transport",         "Variable",  "biweekly", (60, 480),     ["DSB", "Sydtrafik", "Circle K", "GoMore"]),
    (8, "Repairs",           "Irregular", "rare",     (350, 2600),   ["Stark", "jem & fix", "Elektriker Vejle"]),
]

SPLIT_EQUAL = "EQUAL"
SPLIT_CUSTOM = "CUSTOM"


def dkk(x):
    """Round to 2 decimals, half-up, as Decimal."""
    return Decimal(str(x)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def active_people(on):
    return [p for p in PEOPLE if p[3] <= on]


# --------------------------------------------------------------------------
# dim_date
# --------------------------------------------------------------------------

def build_dim_date():
    rows = []
    d = START
    while d <= END:
        q = (d.month - 1) // 3 + 1
        rows.append({
            "date_key": d.isoformat(),
            "year": d.year,
            "quarter": f"Q{q}",
            "month_number": d.month,
            "month_name": d.strftime("%B"),
            "year_month": d.strftime("%Y-%m"),
            "day_of_month": d.day,
            "day_name": d.strftime("%A"),
            "is_weekend": d.weekday() >= 5,
        })
        d += timedelta(days=1)
    return rows


# --------------------------------------------------------------------------
# Expenses
# --------------------------------------------------------------------------

def should_generate(cadence, d):
    if cadence == "monthly":
        return d.day == 1
    if cadence == "frequent":          # groceries: most days, heavier at weekends
        return random.random() < (0.62 if d.weekday() >= 5 else 0.38)
    if cadence == "weekly":
        return random.random() < 0.17
    if cadence == "biweekly":
        return random.random() < 0.09
    if cadence == "rare":
        return random.random() < 0.012
    return False


def seasonal_factor(cat_id, d):
    """Utilities spike in winter; dining out dips in exam months."""
    if cat_id == 2:  # Utilities
        return {12: 1.55, 1: 1.70, 2: 1.50, 3: 1.25, 11: 1.30}.get(d.month, 0.80)
    if cat_id == 6:  # Dining Out
        return {1: 0.65, 6: 0.70, 12: 1.35, 7: 1.20}.get(d.month, 1.0)
    if cat_id == 4:  # Groceries
        return 1.18 if d.month == 12 else 1.0
    return 1.0


def build_expenses():
    expenses, shares = [], []
    expense_id, share_id = 1, 1
    d = START

    while d <= END:
        people = active_people(d)
        ids = [p[0] for p in people]

        for cat_id, cat_name, _grp, cadence, (lo, hi), merchants in CATEGORIES:
            if not should_generate(cadence, d):
                continue

            base = random.uniform(lo, hi) * seasonal_factor(cat_id, d)
            amount = dkk(round(base, 2))
            payer = random.choice(ids)
            merchant = random.choice(merchants)

            # Rent and fixed bills split equally; occasionally someone covers
            # a different share of a discretionary expense.
            if cat_id in (6, 7) and random.random() < 0.30:
                split_type = SPLIT_CUSTOM
                participants = random.sample(ids, k=random.randint(2, len(ids)))
            else:
                split_type = SPLIT_EQUAL
                participants = ids

            expenses.append({
                "expense_id": expense_id,
                "expense_date": d.isoformat(),
                "category_id": cat_id,
                "paid_by_person_id": payer,
                "merchant": merchant,
                "description": f"{cat_name} - {merchant}",
                "amount_dkk": str(amount),
                "split_type": split_type,
                "participant_count": len(participants),
            })

            # Split with remainder handling so shares always sum to the total.
            n = len(participants)
            per = (amount / n).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
            allocated = per * n
            remainder = amount - allocated

            for i, pid in enumerate(participants):
                share_amt = per + (remainder if i == 0 else Decimal("0.00"))
                shares.append({
                    "share_id": share_id,
                    "expense_id": expense_id,
                    "person_id": pid,
                    "expense_date": d.isoformat(),
                    "category_id": cat_id,
                    "share_amount_dkk": str(share_amt),
                    "is_payer": pid == payer,
                })
                share_id += 1

            expense_id += 1
        d += timedelta(days=1)

    return expenses, shares


def build_settlements(shares):
    """Monthly settle-up transfers between housemates."""
    rows = []
    sid = 1
    d = date(2025, 10, 5)
    while d <= END:
        people = [p[0] for p in active_people(d)]
        for _ in range(random.randint(1, 3)):
            frm, to = random.sample(people, 2)
            rows.append({
                "settlement_id": sid,
                "settlement_date": d.isoformat(),
                "from_person_id": frm,
                "to_person_id": to,
                "amount_dkk": str(dkk(round(random.uniform(150, 2200), 2))),
                "method": random.choice(["MobilePay", "Bank transfer", "Cash"]),
            })
            sid += 1
        # first week of next month
        d = (d.replace(day=1) + timedelta(days=32)).replace(day=random.randint(3, 8))
    return rows


# --------------------------------------------------------------------------

def write_csv(name, rows, fields):
    path = os.path.join(OUT, name)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    print(f"  {name:28s} {len(rows):>6,} rows")


def main():
    print("Generating dataset...")

    people_rows = [
        {"person_id": p[0], "person_name": p[1], "email": p[2], "joined_date": p[3].isoformat()}
        for p in PEOPLE
    ]
    write_csv("dim_person.csv", people_rows,
              ["person_id", "person_name", "email", "joined_date"])

    cat_rows = [
        {"category_id": c[0], "category_name": c[1], "category_group": c[2]}
        for c in CATEGORIES
    ]
    write_csv("dim_category.csv", cat_rows,
              ["category_id", "category_name", "category_group"])

    dates = build_dim_date()
    write_csv("dim_date.csv", dates,
              ["date_key", "year", "quarter", "month_number", "month_name",
               "year_month", "day_of_month", "day_name", "is_weekend"])

    expenses, shares = build_expenses()
    write_csv("fact_expense.csv", expenses,
              ["expense_id", "expense_date", "category_id", "paid_by_person_id",
               "merchant", "description", "amount_dkk", "split_type", "participant_count"])
    write_csv("fact_expense_share.csv", shares,
              ["share_id", "expense_id", "person_id", "expense_date", "category_id",
               "share_amount_dkk", "is_payer"])

    settlements = build_settlements(shares)
    write_csv("fact_settlement.csv", settlements,
              ["settlement_id", "settlement_date", "from_person_id",
               "to_person_id", "amount_dkk", "method"])

    # ---- integrity check: shares must reconcile to expense totals ----
    total_exp = sum(Decimal(e["amount_dkk"]) for e in expenses)
    total_shr = sum(Decimal(s["share_amount_dkk"]) for s in shares)
    print(f"\n  Total expenses : {total_exp:>12,.2f} DKK")
    print(f"  Total shares   : {total_shr:>12,.2f} DKK")
    assert total_exp == total_shr, f"MISMATCH: {total_exp - total_shr}"
    print("  Reconciliation : OK (shares sum exactly to expenses)")


if __name__ == "__main__":
    main()
