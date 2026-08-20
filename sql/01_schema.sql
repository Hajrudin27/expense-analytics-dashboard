-- =====================================================================
-- Expense Analytics — reporting schema (PostgreSQL)
--
-- A small star schema sitting alongside the Roommate Expense Splitter API.
-- The operational API owns the write model; this schema is shaped purely
-- for reporting: conformed dimensions, additive facts, one grain per table.
-- =====================================================================

DROP SCHEMA IF EXISTS analytics CASCADE;
CREATE SCHEMA analytics;

SET search_path TO analytics;

-- ---------------------------------------------------------------------
-- Dimensions
-- ---------------------------------------------------------------------

CREATE TABLE dim_person (
    person_id    INTEGER PRIMARY KEY,
    person_name  TEXT NOT NULL,
    email        TEXT NOT NULL,
    joined_date  DATE NOT NULL
);

CREATE TABLE dim_category (
    category_id     INTEGER PRIMARY KEY,
    category_name   TEXT NOT NULL,
    -- Fixed / Variable / Discretionary / Irregular.
    -- Lets the report separate "costs we control" from "costs we don't".
    category_group  TEXT NOT NULL
);

CREATE TABLE dim_date (
    date_key      DATE PRIMARY KEY,
    year          SMALLINT NOT NULL,
    quarter       TEXT     NOT NULL,
    month_number  SMALLINT NOT NULL,
    month_name    TEXT     NOT NULL,
    year_month    TEXT     NOT NULL,
    day_of_month  SMALLINT NOT NULL,
    day_name      TEXT     NOT NULL,
    is_weekend    BOOLEAN  NOT NULL
);

-- ---------------------------------------------------------------------
-- Facts
-- ---------------------------------------------------------------------

-- Grain: one row per expense (what was spent, and who fronted the money).
CREATE TABLE fact_expense (
    expense_id         INTEGER PRIMARY KEY,
    expense_date       DATE    NOT NULL REFERENCES dim_date(date_key),
    category_id        INTEGER NOT NULL REFERENCES dim_category(category_id),
    paid_by_person_id  INTEGER NOT NULL REFERENCES dim_person(person_id),
    merchant           TEXT    NOT NULL,
    description        TEXT    NOT NULL,
    amount_dkk         NUMERIC(12,2) NOT NULL CHECK (amount_dkk > 0),
    split_type         TEXT    NOT NULL CHECK (split_type IN ('EQUAL','CUSTOM')),
    participant_count  SMALLINT NOT NULL CHECK (participant_count > 0)
);

-- Grain: one row per person per expense — their slice of that expense.
-- This is the table most report visuals point at, because "who consumed
-- what" is the question, not "who happened to hold the card".
CREATE TABLE fact_expense_share (
    share_id          INTEGER PRIMARY KEY,
    expense_id        INTEGER NOT NULL REFERENCES fact_expense(expense_id),
    person_id         INTEGER NOT NULL REFERENCES dim_person(person_id),
    expense_date      DATE    NOT NULL REFERENCES dim_date(date_key),
    category_id       INTEGER NOT NULL REFERENCES dim_category(category_id),
    share_amount_dkk  NUMERIC(12,2) NOT NULL,
    is_payer          BOOLEAN NOT NULL
);

-- Grain: one row per settle-up transfer between two housemates.
CREATE TABLE fact_settlement (
    settlement_id    INTEGER PRIMARY KEY,
    settlement_date  DATE    NOT NULL REFERENCES dim_date(date_key),
    from_person_id   INTEGER NOT NULL REFERENCES dim_person(person_id),
    to_person_id     INTEGER NOT NULL REFERENCES dim_person(person_id),
    amount_dkk       NUMERIC(12,2) NOT NULL CHECK (amount_dkk > 0),
    method           TEXT    NOT NULL,
    CHECK (from_person_id <> to_person_id)
);

-- Indexes on the foreign keys the report filters and slices by.
CREATE INDEX idx_expense_date      ON fact_expense (expense_date);
CREATE INDEX idx_expense_category  ON fact_expense (category_id);
CREATE INDEX idx_share_person      ON fact_expense_share (person_id);
CREATE INDEX idx_share_date        ON fact_expense_share (expense_date);
CREATE INDEX idx_share_category    ON fact_expense_share (category_id);
