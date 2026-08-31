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
 ('baseline',      0.650, 12, 72, 160.00, 0.432, 'Central case: simulator peak on logit_v1 scores'),
 ('save_rate_low', 0.650, 12, 72, 140.00, 0.250, 'Sensitivity: pessimistic uplift'),
 ('save_rate_high',0.650, 12, 72, 140.00, 0.550, 'Sensitivity: optimistic uplift'),
 ('window_6',      0.650,  6, 72, 140.00, 0.413, 'Sensitivity: shorter observation window'),
 ('window_24',     0.650, 24, 72, 140.00, 0.413, 'Sensitivity: longer observation window');

-- ---------------------------------------------------------------------------
-- Monthly churn hazard by contract type, per scenario.
-- ---------------------------------------------------------------------------
-- Kept for diagnostics and for the before/after comparison. No longer feeds
-- the economics: expected tenure is now individual, not segment-level.
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
--
--   THE KEY MODELLING DECISION, stated explicitly because it looks wrong
--   until you see why it isn't:
--
--   Expected tenure here is a COUNTERFACTUAL. It is how long the subscriber
--   is worth if the retention offer succeeds -- not how long they will last
--   on their current trajectory. A saved subscriber is by definition no
--   longer churning at their pre-intervention rate, so expected tenure must
--   NOT be derived from their own p_churn.
--
--   It therefore comes from the segment (contract) hazard, which stands in
--   for "a comparable retained customer". This is why a subscriber can
--   legitimately carry a 79.9% churn probability and a 72-month expected
--   life at the same time: the first is their risk today, the second is
--   their worth if we keep them.
--
--   An earlier revision derived expected tenure from each subscriber's own
--   p_churn instead. It was tested and rejected: it counts risk twice (once
--   in the probability, once in the shortened tenure), the two effects
--   cancel, and the target list inverts to favour LOW-risk customers -- the
--   exact "discounting people who were never going to leave" failure the
--   whole project is built to avoid. The comparison view below preserves
--   both so the difference can be shown rather than asserted.
--
--   CLV           = ARPU x gross margin x expected tenure if saved
--   value at risk = P(churn) x CLV
--   offer worth making when  value_at_risk x save_rate > offer_cost
--   => threshold   = offer_cost / save_rate
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW decision.v_customer_economics AS
SELECT a.scenario,
       s.customer_id,
       s.contract,
       s.tenure_band,
       s.monthly_charges,
       sc.p_churn,
       LEAST(1.0 / NULLIF(h.monthly_hazard, 0),
             a.max_expected_tenure_months)::NUMERIC(8,2)  AS expected_tenure_if_saved,
       -- Diagnostic only. Never feeds CLV. Kept so the rejected alternative
       -- can be demonstrated: what this subscriber is worth if NOT saved.
       LEAST(1.0 / NULLIF(1 - POWER(1 - sc.p_churn,
                          1.0 / a.observation_window_months), 0),
             a.max_expected_tenure_months)::NUMERIC(8,2)  AS expected_tenure_if_not_saved,
       ROUND(s.monthly_charges
             * a.gross_margin_pct
             * LEAST(1.0 / NULLIF(h.monthly_hazard, 0),
                     a.max_expected_tenure_months), 2)     AS clv,
       ROUND(sc.p_churn * s.monthly_charges
             * a.gross_margin_pct
             * LEAST(1.0 / NULLIF(h.monthly_hazard, 0),
                     a.max_expected_tenure_months), 2)     AS value_at_risk,
       ROUND(a.offer_cost / a.assumed_save_rate, 2)        AS var_threshold,
       a.offer_cost,
       a.assumed_save_rate,
       (sc.p_churn * s.monthly_charges * a.gross_margin_pct
        * LEAST(1.0 / NULLIF(h.monthly_hazard, 0), a.max_expected_tenure_months)
        >= a.offer_cost / a.assumed_save_rate)             AS is_targeted
FROM   clean.subscribers s
JOIN   ml.churn_scores sc  ON sc.customer_id = s.customer_id
JOIN   ml.active_model am  ON am.model_version = sc.model_version
CROSS  JOIN decision.assumptions a
JOIN   decision.v_segment_hazard h
       ON h.scenario = a.scenario AND h.contract = s.contract;

-- ---------------------------------------------------------------------------
-- The rejected alternative, kept so the choice can be demonstrated.
-- Ranks subscribers by value at risk under BOTH tenure definitions.
-- Under the individual-hazard version the top of the list fills with
-- two-year, low-probability subscribers: safe customers being offered
-- retention discounts.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW decision.v_tenure_method_comparison AS
SELECT customer_id,
       contract,
       monthly_charges,
       p_churn,
       expected_tenure_if_saved,
       expected_tenure_if_not_saved,
       value_at_risk                                        AS var_counterfactual,
       ROUND(p_churn * monthly_charges * 0.65
             * expected_tenure_if_not_saved, 2)             AS var_individual_hazard,
       RANK() OVER (ORDER BY value_at_risk DESC)            AS rank_counterfactual,
       RANK() OVER (ORDER BY p_churn * monthly_charges * 0.65
                             * expected_tenure_if_not_saved DESC) AS rank_individual
FROM   decision.v_customer_economics
WHERE  scenario = 'baseline';

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
