-- =====================================================================
-- Reporting views
--
-- Power BI could import the raw tables directly, but pushing the joins
-- and the balance logic down into SQL keeps the semantic model thin and
-- means the same numbers are reproducible outside the report.
-- =====================================================================

SET search_path TO analytics;

-- ---------------------------------------------------------------------
-- v_expense_detail — one flat row per person-share, ready to slice.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_expense_detail AS
SELECT
    s.share_id,
    s.expense_id,
    e.expense_date,
    d.year,
    d.quarter,
    d.year_month,
    d.month_name,
    d.day_name,
    d.is_weekend,
    c.category_name,
    c.category_group,
    p.person_name,
    payer.person_name          AS paid_by,
    e.merchant,
    e.amount_dkk               AS expense_total_dkk,
    s.share_amount_dkk,
    s.is_payer,
    e.split_type
FROM fact_expense_share s
JOIN fact_expense  e     ON e.expense_id  = s.expense_id
JOIN dim_date      d     ON d.date_key    = s.expense_date
JOIN dim_category  c     ON c.category_id = s.category_id
JOIN dim_person    p     ON p.person_id   = s.person_id
JOIN dim_person    payer ON payer.person_id = e.paid_by_person_id;

-- ---------------------------------------------------------------------
-- v_monthly_spend — the headline trend, split fixed vs variable.
--
-- Rent alone is ~43% of the total, which flattens the overall trend
-- line. Separating the groups is what makes seasonality visible.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_monthly_spend AS
SELECT
    d.year_month,
    c.category_group,
    SUM(e.amount_dkk)                        AS total_dkk,
    COUNT(*)                                 AS expense_count,
    ROUND(AVG(e.amount_dkk), 2)              AS avg_expense_dkk
FROM fact_expense e
JOIN dim_date     d ON d.date_key    = e.expense_date
JOIN dim_category c ON c.category_id = e.category_id
GROUP BY d.year_month, c.category_group;

-- ---------------------------------------------------------------------
-- v_person_balance — the operational question: who owes whom?
--
-- balance = (what they paid out) - (what they consumed) + (settlements
-- received) ... inverted: a positive balance means the household owes
-- this person money.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_person_balance AS
WITH paid AS (
    SELECT paid_by_person_id AS person_id, SUM(amount_dkk) AS total_paid
    FROM fact_expense
    GROUP BY paid_by_person_id
),
owed AS (
    SELECT person_id, SUM(share_amount_dkk) AS total_share
    FROM fact_expense_share
    GROUP BY person_id
),
settled_out AS (
    SELECT from_person_id AS person_id, SUM(amount_dkk) AS total_sent
    FROM fact_settlement
    GROUP BY from_person_id
),
settled_in AS (
    SELECT to_person_id AS person_id, SUM(amount_dkk) AS total_received
    FROM fact_settlement
    GROUP BY to_person_id
)
SELECT
    p.person_id,
    p.person_name,
    COALESCE(paid.total_paid,          0) AS total_paid_dkk,
    COALESCE(owed.total_share,         0) AS total_share_dkk,
    COALESCE(settled_out.total_sent,   0) AS settlements_sent_dkk,
    COALESCE(settled_in.total_received,0) AS settlements_received_dkk,
    COALESCE(paid.total_paid, 0)
      - COALESCE(owed.total_share, 0)
      + COALESCE(settled_out.total_sent, 0)
      - COALESCE(settled_in.total_received, 0) AS net_balance_dkk
FROM dim_person p
LEFT JOIN paid        ON paid.person_id        = p.person_id
LEFT JOIN owed        ON owed.person_id        = p.person_id
LEFT JOIN settled_out ON settled_out.person_id = p.person_id
LEFT JOIN settled_in  ON settled_in.person_id  = p.person_id;

-- ---------------------------------------------------------------------
-- v_category_ranking — contribution analysis with a running share,
-- so the report can answer "which categories make up 80% of spend?".
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_category_ranking AS
SELECT
    c.category_name,
    c.category_group,
    SUM(e.amount_dkk) AS total_dkk,
    COUNT(*)          AS expense_count,
    ROUND(100.0 * SUM(e.amount_dkk) / SUM(SUM(e.amount_dkk)) OVER (), 1) AS pct_of_total,
    ROUND(100.0 * SUM(SUM(e.amount_dkk)) OVER (ORDER BY SUM(e.amount_dkk) DESC)
                / SUM(SUM(e.amount_dkk)) OVER (), 1) AS running_pct
FROM fact_expense e
JOIN dim_category c ON c.category_id = e.category_id
GROUP BY c.category_name, c.category_group
ORDER BY total_dkk DESC;

-- ---------------------------------------------------------------------
-- Data-quality check — shares must reconcile to expense totals exactly.
-- Should return zero rows. Run it after every load.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_dq_share_reconciliation AS
SELECT
    e.expense_id,
    e.amount_dkk,
    SUM(s.share_amount_dkk) AS sum_of_shares,
    e.amount_dkk - SUM(s.share_amount_dkk) AS difference
FROM fact_expense e
JOIN fact_expense_share s ON s.expense_id = e.expense_id
GROUP BY e.expense_id, e.amount_dkk
HAVING e.amount_dkk <> SUM(s.share_amount_dkk);
