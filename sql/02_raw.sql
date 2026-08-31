-- 02_raw.sql
-- Landing table for WA_Fn-UseC_-Telco-Customer-Churn.csv
-- Every column is TEXT on purpose: the load must never fail on a bad value.
-- Column ORDER must match the CSV exactly (\copy matches by position, not name).

DROP TABLE IF EXISTS raw.telco_customers CASCADE;

CREATE TABLE raw.telco_customers (
    customer_id       TEXT,
    gender            TEXT,
    senior_citizen    TEXT,
    partner           TEXT,
    dependents        TEXT,
    tenure            TEXT,
    phone_service     TEXT,
    multiple_lines    TEXT,
    internet_service  TEXT,
    online_security   TEXT,
    online_backup     TEXT,
    device_protection TEXT,
    tech_support      TEXT,
    streaming_tv      TEXT,
    streaming_movies  TEXT,
    contract          TEXT,
    paperless_billing TEXT,
    payment_method    TEXT,
    monthly_charges   TEXT,
    total_charges     TEXT,
    churn             TEXT
);

COMMENT ON TABLE raw.telco_customers IS
  'IBM Telco Customer Churn sample, 7043 rows. Loaded verbatim via \copy.';
