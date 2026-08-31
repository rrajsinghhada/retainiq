-- 03_clean.sql
-- Typed subscriber layer + a genuine plan lookup.
--
-- Deliberately NOT a full star schema. This CSV is a single snapshot with one
-- row per customer and no month column, so fact_usage / fact_billing / churn_month
-- cannot be built honestly from it. Those arrive with the TRAI layer (07).

DROP TABLE IF EXISTS clean.subscribers CASCADE;
DROP TABLE IF EXISTS clean.dim_plan CASCADE;

-- ---------------------------------------------------------------------------
-- Plan dimension: the commercial configuration a subscriber sits on.
-- ---------------------------------------------------------------------------
CREATE TABLE clean.dim_plan (
    plan_id           SMALLSERIAL PRIMARY KEY,
    contract          TEXT    NOT NULL,
    internet_service  TEXT    NOT NULL,
    payment_method    TEXT    NOT NULL,
    paperless_billing BOOLEAN NOT NULL,
    UNIQUE (contract, internet_service, payment_method, paperless_billing)
);

INSERT INTO clean.dim_plan (contract, internet_service, payment_method, paperless_billing)
SELECT DISTINCT
       contract,
       internet_service,
       payment_method,
       paperless_billing = 'Yes'
FROM   raw.telco_customers
ORDER  BY 1, 2, 3, 4;

-- ---------------------------------------------------------------------------
-- Subscriber snapshot.
-- ---------------------------------------------------------------------------
CREATE TABLE clean.subscribers (
    customer_id            TEXT      PRIMARY KEY,
    plan_id                SMALLINT  NOT NULL REFERENCES clean.dim_plan(plan_id),

    gender                 TEXT      NOT NULL CHECK (gender IN ('Male','Female')),
    is_senior              BOOLEAN   NOT NULL,
    has_partner            BOOLEAN   NOT NULL,
    has_dependents         BOOLEAN   NOT NULL,

    tenure_months          SMALLINT  NOT NULL CHECK (tenure_months >= 0),
    tenure_band            TEXT      NOT NULL,

    phone_service          BOOLEAN   NOT NULL,
    multiple_lines         TEXT      NOT NULL,
    internet_service       TEXT      NOT NULL,
    online_security        TEXT      NOT NULL,
    online_backup          TEXT      NOT NULL,
    device_protection      TEXT      NOT NULL,
    tech_support           TEXT      NOT NULL,
    streaming_tv           TEXT      NOT NULL,
    streaming_movies       TEXT      NOT NULL,
    add_on_count           SMALLINT  NOT NULL CHECK (add_on_count BETWEEN 0 AND 6),

    contract               TEXT      NOT NULL,
    paperless_billing      BOOLEAN   NOT NULL,
    payment_method         TEXT      NOT NULL,

    monthly_charges        NUMERIC(8,2)  NOT NULL CHECK (monthly_charges >= 0),
    total_charges          NUMERIC(10,2) NOT NULL CHECK (total_charges  >= 0),
    total_charges_imputed  BOOLEAN   NOT NULL,

    churn_flag             SMALLINT  NOT NULL CHECK (churn_flag IN (0,1))
);

INSERT INTO clean.subscribers
SELECT
    r.customer_id,
    p.plan_id,

    r.gender,
    r.senior_citizen = '1',
    r.partner        = 'Yes',
    r.dependents     = 'Yes',

    r.tenure::SMALLINT,
    CASE
        WHEN r.tenure::INT <= 6  THEN '00-06 months'
        WHEN r.tenure::INT <= 12 THEN '07-12 months'
        WHEN r.tenure::INT <= 24 THEN '13-24 months'
        WHEN r.tenure::INT <= 48 THEN '25-48 months'
        ELSE                          '49+ months'
    END,

    r.phone_service = 'Yes',
    r.multiple_lines,
    r.internet_service,
    r.online_security,
    r.online_backup,
    r.device_protection,
    r.tech_support,
    r.streaming_tv,
    r.streaming_movies,
    (r.online_security   = 'Yes')::INT
  + (r.online_backup     = 'Yes')::INT
  + (r.device_protection = 'Yes')::INT
  + (r.tech_support      = 'Yes')::INT
  + (r.streaming_tv      = 'Yes')::INT
  + (r.streaming_movies  = 'Yes')::INT,

    r.contract,
    r.paperless_billing = 'Yes',
    r.payment_method,

    r.monthly_charges::NUMERIC,

    -- The 11 blank TotalCharges values are a SINGLE SPACE, not an empty string.
    -- TRIM is what catches them. All 11 are tenure = 0 (billed nothing yet) and
    -- none of them churned, so 0 is the correct value, not NULL and not a drop.
    COALESCE(NULLIF(TRIM(r.total_charges), '')::NUMERIC, 0),
    NULLIF(TRIM(r.total_charges), '') IS NULL,

    (r.churn = 'Yes')::INT
FROM raw.telco_customers r
JOIN clean.dim_plan p
  ON  p.contract          = r.contract
  AND p.internet_service  = r.internet_service
  AND p.payment_method    = r.payment_method
  AND p.paperless_billing = (r.paperless_billing = 'Yes');

CREATE INDEX ON clean.subscribers (plan_id);

COMMENT ON COLUMN clean.subscribers.total_charges_imputed IS
  'TRUE for the 11 zero-tenure rows whose source TotalCharges was blank.';
