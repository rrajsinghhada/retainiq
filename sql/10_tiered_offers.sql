-- 10_tiered_offers.sql
-- From "who to call" to "who to call and what to offer them".
--
-- 06_decision.sql finds ONE offer size that maximises net contribution across
-- the whole list. That is the right answer to "what should this campaign
-- cost", but it hands the same rupee amount to a subscriber with 1,600 at risk
-- and to one with 380. This file sizes the offer per subscriber.
--
-- THE DERIVATION -- know this cold, it is the best whiteboard moment in the
-- project:
--
--   For a single subscriber, expected net contribution from an offer of c is
--       net(c) = VaR x s(c) - c
--   with the same response curve the simulator uses
--       s(c) = S x (1 - e^(-c/k))        S = ceiling save rate, k = scale
--
--   Differentiate and set to zero. Spend until the marginal rupee of offer
--   buys exactly one rupee of expected saved contribution:
--       VaR x s'(c) = 1
--       VaR x (S/k) x e^(-c/k) = 1
--       c* = k x ln(VaR x S / k)
--
--   With S = 0.50 and k = 80 that is c* = 80 x ln(VaR / 160): no offer is
--   justified below VaR = 160, and the amount grows with the LOG of value --
--   fast at first, then slowly. Diminishing returns fall out of the algebra
--   rather than being imposed on it.
--
--   CAVEAT to say before you are asked: tiering is only as good as the curve,
--   and the curve is assumed. A wrong shape distorts a tiered campaign more
--   than a uniform one, because the tiers ARE the curve. Two alternative
--   curves are seeded below so the sensitivity can be shown.

DROP TABLE IF EXISTS decision.response_curve CASCADE;

CREATE TABLE decision.response_curve (
    curve_name  TEXT PRIMARY KEY,
    s_max       NUMERIC(4,3) NOT NULL CHECK (s_max BETWEEN 0 AND 1),
    k           NUMERIC(8,2) NOT NULL CHECK (k > 0),
    min_offer   NUMERIC(8,2) NOT NULL,   -- below this a campaign is not worth running
    max_offer   NUMERIC(8,2) NOT NULL,   -- policy ceiling, not an economic one
    round_to    NUMERIC(8,2) NOT NULL,   -- real campaigns use round numbers
    note        TEXT
);

INSERT INTO decision.response_curve VALUES
 ('central', 0.500,  80.00, 100.00, 600.00, 50.00,
  'Matches the simulator: s = 0.50 x (1 - exp(-c/80))'),
 ('flat',    0.350, 200.00, 100.00, 600.00, 50.00,
  'Sensitivity: persuasion responds slowly to offer size'),
 ('steep',   0.600,  40.00, 100.00, 600.00, 50.00,
  'Sensitivity: most of the effect arrives with a small offer');

-- ---------------------------------------------------------------------------
-- Per-subscriber offer sizing.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW decision.v_tiered_offers AS
WITH raw_opt AS (
    SELECT e.customer_id,
           e.contract,
           e.tenure_band,
           e.monthly_charges,
           e.p_churn,
           e.clv,
           e.value_at_risk,
           r.curve_name, r.s_max, r.k, r.min_offer, r.max_offer, r.round_to,
           CASE WHEN e.value_at_risk * r.s_max > r.k
                THEN r.k * LN(e.value_at_risk * r.s_max / r.k)
                ELSE 0 END AS c_star
    FROM   decision.v_customer_economics e
    CROSS  JOIN decision.response_curve r
    WHERE  e.scenario = 'baseline'
),
practical AS (
    SELECT *,
           -- clamp to policy bounds, then round to a number a campaign can use
           LEAST(GREATEST(ROUND(c_star / round_to) * round_to, min_offer),
                 max_offer)::NUMERIC(8,2) AS offer
    FROM   raw_opt
)
SELECT curve_name,
       customer_id,
       contract,
       tenure_band,
       monthly_charges,
       p_churn,
       clv,
       value_at_risk,
       ROUND(c_star, 2)                                         AS optimal_offer_exact,
       offer,
       ROUND(s_max * (1 - EXP(-offer / k)), 4)                   AS implied_save_rate,
       ROUND(value_at_risk * s_max * (1 - EXP(-offer / k)) - offer, 2)
                                                                 AS expected_net,
       'Tier ' || NTILE(4) OVER (PARTITION BY curve_name
                                 ORDER BY value_at_risk DESC)     AS tier
FROM   practical
-- Participation constraint: only make the offer if it pays for itself.
WHERE  value_at_risk * s_max * (1 - EXP(-offer / k)) - offer > 0;

-- ---------------------------------------------------------------------------
-- The campaign sheet. This is the artefact a retention manager runs.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW decision.v_campaign_sheet AS
SELECT curve_name,
       tier,
       offer,
       COUNT(*)                     AS customers,
       ROUND(MIN(value_at_risk), 2) AS min_value_at_risk,
       ROUND(MAX(value_at_risk), 2) AS max_value_at_risk,
       ROUND(SUM(offer), 2)         AS tier_spend,
       ROUND(SUM(expected_net), 2)  AS tier_net_contribution
FROM   decision.v_tiered_offers
GROUP  BY curve_name, tier, offer
ORDER  BY curve_name, tier, offer;

-- ---------------------------------------------------------------------------
-- Does tiering actually beat the best single uniform offer? Answer it rather
-- than assume it. If the gain is small, say so -- a uniform campaign is
-- simpler to run, simpler to explain, and simpler to audit.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW decision.v_tiered_vs_uniform AS
WITH tiered AS (
    SELECT curve_name,
           COUNT(*)          AS customers,
           SUM(offer)        AS spend,
           SUM(expected_net) AS net_contribution
    FROM   decision.v_tiered_offers
    GROUP  BY curve_name
),
uniform AS (
    SELECT targeted    AS customers,
           offer_spend AS spend,
           net_contribution
    FROM   decision.v_simulator
    WHERE  scenario = 'baseline'
)
SELECT t.curve_name,
       u.customers        AS uniform_customers,
       u.net_contribution AS uniform_net,
       t.customers        AS tiered_customers,
       t.spend            AS tiered_spend,
       t.net_contribution AS tiered_net,
       ROUND(t.net_contribution - u.net_contribution, 2) AS gain,
       ROUND((t.net_contribution / NULLIF(u.net_contribution, 0) - 1) * 100, 2)
                                                          AS gain_pct
FROM   tiered t CROSS JOIN uniform u
ORDER  BY t.curve_name;
