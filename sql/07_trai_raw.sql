-- 07_trai_raw.sql
-- Staging for the TRAI monthly Telecom Subscription Data press releases.
--
-- Source: https://www.trai.gov.in/release-publication/reports/telecom-subscriptions-reports
-- One PDF per month. Two tables are extracted from each:
--   Annexure-II    operator x circle wireless subscriber counts
--   MNP Status     cumulative porting requests per circle
--
-- All TEXT again, for the same reason as the Telco load: the parse must never
-- fail on a stray footnote or a merged cell. Typing happens in 08_trai_clean.

DROP TABLE IF EXISTS raw.trai_operator_circle CASCADE;
DROP TABLE IF EXISTS raw.trai_mnp CASCADE;

CREATE TABLE raw.trai_operator_circle (
    source_file   TEXT,   -- e.g. trai_2025_07.pdf, for tracing a bad row back
    report_month  TEXT,   -- YYYY-MM, the month the report is "as on"
    circle_raw    TEXT,   -- circle name exactly as printed, before normalisation
    operator_raw  TEXT,   -- operator name exactly as printed
    subscribers   TEXT
);

CREATE TABLE raw.trai_mnp (
    source_file       TEXT,
    report_month      TEXT,
    zone_raw          TEXT,   -- 'Zone-I' or 'Zone-II'
    circle_raw        TEXT,
    cumulative_ports  TEXT    -- millions, cumulative since 2010/2011
);

COMMENT ON TABLE raw.trai_operator_circle IS
  'Annexure-II of the TRAI monthly subscription press release. Long format: '
  'one row per file x month x circle x operator.';

COMMENT ON COLUMN raw.trai_mnp.cumulative_ports IS
  'CUMULATIVE porting requests in millions since MNP launch, not monthly. '
  'Monthly activity is the month-over-month difference. Do not read directly.';
