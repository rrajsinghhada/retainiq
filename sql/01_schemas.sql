-- 01_schemas.sql
-- RetainIQ | Five schemas, one database.
-- raw      : untouched load of source files, all TEXT, never queried for analysis
-- clean    : typed, constrained, one row per subscriber
-- analytics: diagnostic views (the "why" layer)
-- ml       : model output written back from Python
-- decision : CLV, value-at-risk, offer thresholds, simulator

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS clean;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS ml;
CREATE SCHEMA IF NOT EXISTS decision;

COMMENT ON SCHEMA raw       IS 'Verbatim source loads. All columns TEXT. Never analysed directly.';
COMMENT ON SCHEMA clean     IS 'Typed and constrained subscriber layer.';
COMMENT ON SCHEMA analytics IS 'Diagnostic views: who is churning and from where.';
COMMENT ON SCHEMA ml        IS 'Model scores written back from Python.';
COMMENT ON SCHEMA decision  IS 'Retention economics: CLV, value at risk, offer thresholds.';
