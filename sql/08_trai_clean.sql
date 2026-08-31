-- 08_trai_clean.sql
-- Typed TRAI layer. This is where the project finally gets a real month axis.
--
-- The Telco snapshot has no time dimension, so LAG(), cohort triangles and
-- month-over-month analysis are not possible on it. They ARE possible here.
-- That split is deliberate and should be stated out loud: subscriber-level
-- mechanics come from the Kaggle set, market movement comes from TRAI, and
-- the two are kept as separate layers rather than forced into a join that
-- the data cannot support.

DROP TABLE IF EXISTS clean.fact_circle_operator_month CASCADE;
DROP TABLE IF EXISTS clean.fact_mnp_month CASCADE;
DROP TABLE IF EXISTS clean.dim_operator CASCADE;
DROP TABLE IF EXISTS clean.dim_circle CASCADE;

-- ---------------------------------------------------------------------------
-- Circle dimension. 22 licensed service areas, seeded explicitly rather than
-- derived, because the category and zone assignments are regulatory facts that
-- do not appear in the PDF tables.
-- ---------------------------------------------------------------------------
CREATE TABLE clean.dim_circle (
    circle_id    SMALLSERIAL PRIMARY KEY,
    circle_name  TEXT NOT NULL UNIQUE,
    zone         TEXT NOT NULL CHECK (zone IN ('Zone-I','Zone-II')),
    category     TEXT NOT NULL CHECK (category IN ('Metro','A','B','C'))
);

INSERT INTO clean.dim_circle (circle_name, zone, category) VALUES
  ('Delhi',            'Zone-I',  'Metro'),
  ('Mumbai',           'Zone-I',  'Metro'),
  ('Kolkata',          'Zone-II', 'Metro'),
  ('Andhra Pradesh',   'Zone-II', 'A'),
  ('Gujarat',          'Zone-I',  'A'),
  ('Karnataka',        'Zone-II', 'A'),
  ('Maharashtra',      'Zone-I',  'A'),
  ('Tamil Nadu',       'Zone-II', 'A'),
  ('Haryana',          'Zone-I',  'B'),
  ('Kerala',           'Zone-II', 'B'),
  ('Madhya Pradesh',   'Zone-II', 'B'),
  ('Punjab',           'Zone-I',  'B'),
  ('Rajasthan',        'Zone-I',  'B'),
  ('U.P.(E)',          'Zone-I',  'B'),
  ('U.P.(W)',          'Zone-I',  'B'),
  ('West Bengal',      'Zone-II', 'B'),
  ('Assam',            'Zone-II', 'C'),
  ('Bihar',            'Zone-II', 'C'),
  ('Himachal Pradesh', 'Zone-I',  'C'),
  ('J & K',            'Zone-I',  'C'),
  ('North East',       'Zone-II', 'C'),
  ('Odisha',           'Zone-II', 'C');

-- ---------------------------------------------------------------------------
-- Operator dimension. Names drift across reports ("Bharti", "Bharti Airtel",
-- "Bharti Airtel Ltd."), so the parser normalises to these codes and this
-- table is the authority on what a code means.
-- ---------------------------------------------------------------------------
CREATE TABLE clean.dim_operator (
    operator_code TEXT PRIMARY KEY,
    operator_name TEXT NOT NULL,
    ownership     TEXT NOT NULL CHECK (ownership IN ('Private','PSU'))
);

INSERT INTO clean.dim_operator VALUES
  ('VI',      'Vodafone Idea',   'Private'),
  ('AIRTEL',  'Bharti Airtel',   'Private'),
  ('JIO',     'Reliance Jio',    'Private'),
  ('BSNL',    'BSNL',            'PSU'),
  ('MTNL',    'MTNL',            'PSU'),
  ('RCOM',    'Reliance Com.',   'Private');

-- ---------------------------------------------------------------------------
-- Wireless subscribers by circle, operator and month.
-- ---------------------------------------------------------------------------
CREATE TABLE clean.fact_circle_operator_month (
    circle_id     SMALLINT NOT NULL REFERENCES clean.dim_circle(circle_id),
    operator_code TEXT     NOT NULL REFERENCES clean.dim_operator(operator_code),
    report_month  DATE     NOT NULL,
    subscribers   BIGINT   NOT NULL CHECK (subscribers >= 0),
    PRIMARY KEY (circle_id, operator_code, report_month)
);

INSERT INTO clean.fact_circle_operator_month
SELECT c.circle_id,
       r.operator_raw,
       to_date(r.report_month || '-01', 'YYYY-MM-DD'),
       replace(r.subscribers, ',', '')::BIGINT
FROM   raw.trai_operator_circle r
JOIN   clean.dim_circle c ON c.circle_name = r.circle_raw
WHERE  r.subscribers IS NOT NULL
  AND  replace(r.subscribers, ',', '') ~ '^[0-9]+$'
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- MNP. Source is cumulative; the monthly figure is derived here with LAG()
-- so nothing downstream has to remember that.
-- ---------------------------------------------------------------------------
CREATE TABLE clean.fact_mnp_month (
    circle_id            SMALLINT NOT NULL REFERENCES clean.dim_circle(circle_id),
    report_month         DATE     NOT NULL,
    cumulative_ports_mn  NUMERIC(10,2) NOT NULL,
    monthly_ports_mn     NUMERIC(10,2),   -- NULL for the first observed month
    PRIMARY KEY (circle_id, report_month)
);

INSERT INTO clean.fact_mnp_month
WITH parsed AS (
    SELECT c.circle_id,
           to_date(r.report_month || '-01', 'YYYY-MM-DD') AS report_month,
           replace(r.cumulative_ports, ',', '')::NUMERIC  AS cumulative_ports_mn
    FROM   raw.trai_mnp r
    JOIN   clean.dim_circle c ON c.circle_name = r.circle_raw
    WHERE  replace(r.cumulative_ports, ',', '') ~ '^[0-9.]+$'
)
SELECT circle_id,
       report_month,
       cumulative_ports_mn,
       ROUND(cumulative_ports_mn
             - LAG(cumulative_ports_mn) OVER (PARTITION BY circle_id
                                              ORDER BY report_month), 2)
FROM   parsed
ON CONFLICT DO NOTHING;
