-- 06_decision.sql
-- The half of RetainIQ that most projects never build.
--
-- Every assumption lives in a table, not in Python. When an interviewer asks
-- "where did your save rate come from?", you point at a row and change it.

-- ---------------------------------------------------------------------------
-- Assumptions. One row per scenario. This IS the simulator.
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS decision.assumptions CASCADE;

CREATE TABLE decision.assumptions (
    scenario                  TEXT PRIMARY KEY,
    gross_margin_pct          NUMERIC(4,3) NOT NULL CHECK (gross_margin_pct BETWEEN 0 AND 1),
    observation_window_months SMALLINT     NOT NULL CHECK (observation_window_months > 0),
    max_expected_tenure_months SMALLINT    NOT NULL CHECK (max_expected_tenure_months > 0),
    offer_cost                NUMERIC(8,2) NOT NULL CHECK (offer_cost >= 0),
    assumed_save_rate         NUMERIC(4,3) NOT NULL CHECK (assumed_save_rate BETWEEN 0 AND 1),
    note                      TEXT
);

COMMENT ON COLUMN decision.assumptions.observation_window_months IS
  'ASSUMPTION. The Kaggle churn flag carries no time window, so the monthly '
  'hazard cannot be derived from the data. It is asserted here and tested '
  'across a range. In production this comes from the billing system.';

COMMENT ON COLUMN decision.assumptions.assumed_save_rate IS
  'ASSUMPTION. Share of targeted at-risk subscribers the offer actually saves. '
  'Not measurable from observational data — needs a randomised holdout. '
  'Sensitivity scenarios below exist so you can show the range, not hide it.';

-- The offer ladder. IMPORTANT: the save rate must RISE WITH OFFER SIZE and
-- flatten out. If you hold save rate constant across the ladder, the simulator
-- degenerates -- net contribution just falls monotonically and the "optimal"
-- answer is always the smallest possible offer. The peak in the curve exists
-- only because a bigger offer persuades more people with diminishing returns.
-- Response curve used: save_rate = 0.50 x (1 - exp(-offer / 80)).
-- This is an ASSUMED curve. In production it comes from a randomised holdout.
INSERT INTO decision.assumptions
SELECT 'offer_' || LPAD(c::TEXT, 3, '0'),
       0.650, 12, 72,
       c,
       ROUND((0.50 * (1 - EXP(-c / 80.0)))::NUMERIC, 3),
       'Offer ladder, diminishing-returns response curve'
FROM   generate_series(20, 400, 20) AS c;

INSERT INTO decision.assumptions VALUES
 ('baseline',      0.650, 12, 72, 140.00, 0.413, 'Central case: the ladder peak'),
 ('save_rate_low', 0.650, 12, 72, 140.00, 0.250, 'Sensitivity: pessimistic uplift'),
 ('save_rate_high',0.650, 12, 72, 140.00, 0.550, 'Sensitivity: optimistic uplift'),
 ('window_6',      0.650,  6, 72, 140.00, 0.413, 'Sensitivity: shorter observation window'),
 ('window_24',     0.650, 24, 72, 140.00, 0.413, 'Sensitivity: longer observation window');

-- ---------------------------------------------------------------------------
-- Monthly churn hazard by contract type, per scenario.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW decision.v_segment_hazard AS
SELECT a.scenario,
       s.contract,
       COUNT(*)                            AS subscribers,
       ROUND(AVG(s.churn_flag), 4)         AS observed_churn_share,
       ROUND(AVG(s.churn_flag) / a.observation_window_months, 5) AS monthly_hazard
FROM   clean.subscribers s
CROSS  JOIN decision.assumptions a
GROUP  BY a.scenario, s.contract, a.observation_window_months;

-- ---------------------------------------------------------------------------
-- Per-subscriber economics.
--   expected tenure = 1 / monthly hazard, capped
--   CLV             = ARPU x gross margin x expected tenure
--   value at risk   = P(churn) x CLV
--   offer is worth making when  value_at_risk x save_rate > offer_cost
--   => threshold     = offer_cost / save_rate
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW decision.v_customer_economics AS
SELECT a.scenario,
       s.customer_id,
       s.contract,
       s.tenure_band,
       s.monthly_charges,
       sc.p_churn,
       LEAST(1.0 / NULLIF(h.monthly_hazard, 0),
             a.max_expected_tenure_months)::NUMERIC(8,2)      AS expected_tenure_months,
       ROUND(s.monthly_charges
             * a.gross_margin_pct
             * LEAST(1.0 / NULLIF(h.monthly_hazard, 0),
                     a.max_expected_tenure_months), 2)         AS clv,
       ROUND(sc.p_churn * s.monthly_charges
             * a.gross_margin_pct
             * LEAST(1.0 / NULLIF(h.monthly_hazard, 0),
                     a.max_expected_tenure_months), 2)         AS value_at_risk,
       ROUND(a.offer_cost / a.assumed_save_rate, 2)            AS var_threshold,
       a.offer_cost,
       a.assumed_save_rate,
       (sc.p_churn * s.monthly_charges * a.gross_margin_pct
        * LEAST(1.0 / NULLIF(h.monthly_hazard, 0), a.max_expected_tenure_months)
        >= a.offer_cost / a.assumed_save_rate)                 AS is_targeted
FROM   clean.subscribers s
JOIN   ml.churn_scores sc  ON sc.customer_id = s.customer_id
JOIN   ml.active_model am  ON am.model_version = sc.model_version
CROSS  JOIN decision.assumptions a
JOIN   decision.v_segment_hazard h
       ON h.scenario = a.scenario AND h.contract = s.contract;

-- ---------------------------------------------------------------------------
-- The deliverable: who to call, in what order, under the central case.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW decision.v_target_list AS
SELECT ROW_NUMBER() OVER (ORDER BY value_at_risk DESC) AS priority,
       customer_id,
       contract,
       tenure_band,
       monthly_charges,
       p_churn,
       clv,
       value_at_risk,
       var_threshold
FROM   decision.v_customer_economics
WHERE  scenario = 'baseline'
  AND  is_targeted
ORDER  BY value_at_risk DESC;

-- ---------------------------------------------------------------------------
-- The simulator. One row per scenario. net_contribution is the only line
-- that matters; it peaks and then falls, and the peak is your recommendation.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW decision.v_simulator AS
SELECT e.scenario,
       e.offer_cost,
       e.assumed_save_rate,
       COUNT(*) FILTER (WHERE e.is_targeted)                      AS targeted,
       ROUND(MIN(e.var_threshold), 2)                             AS var_threshold,
       ROUND(COUNT(*) FILTER (WHERE e.is_targeted) * e.offer_cost, 2) AS offer_spend,
       ROUND(SUM(e.p_churn * e.assumed_save_rate)
             FILTER (WHERE e.is_targeted), 1)                     AS expected_saves,
       ROUND(SUM(e.value_at_risk * e.assumed_save_rate)
             FILTER (WHERE e.is_targeted), 2)                     AS saved_contribution,
       ROUND(SUM(e.value_at_risk * e.assumed_save_rate)
             FILTER (WHERE e.is_targeted)
             - COUNT(*) FILTER (WHERE e.is_targeted) * e.offer_cost, 2) AS net_contribution
FROM   decision.v_customer_economics e
GROUP  BY e.scenario, e.offer_cost, e.assumed_save_rate
ORDER  BY e.offer_cost, e.assumed_save_rate;
