-- 04_analytics.sql
-- The diagnostic layer. Every view answers one stated business question.
-- These are the queries you narrate in the first 90 seconds of the demo.

-- Q1. What is the overall churn rate and how much monthly revenue walks out?
CREATE OR REPLACE VIEW analytics.v_churn_overview AS
SELECT COUNT(*)                                          AS subscribers,
       SUM(churn_flag)                                   AS churned,
       ROUND(AVG(churn_flag) * 100, 2)                   AS churn_rate_pct,
       ROUND(SUM(monthly_charges), 2)                    AS monthly_revenue,
       ROUND(SUM(monthly_charges * churn_flag), 2)       AS monthly_revenue_lost,
       ROUND(SUM(monthly_charges * churn_flag)
             / NULLIF(SUM(monthly_charges), 0) * 100, 2) AS revenue_at_risk_pct
FROM   clean.subscribers;

-- Q2. Where in the lifecycle do we lose people?
--     (Tenure bands on a snapshot = a synthetic cohort read, not a true
--      calendar retention triangle. Say that out loud in the interview.)
CREATE OR REPLACE VIEW analytics.v_churn_by_tenure_band AS
SELECT tenure_band,
       COUNT(*)                        AS subscribers,
       SUM(churn_flag)                 AS churned,
       ROUND(AVG(churn_flag) * 100, 2) AS churn_rate_pct,
       ROUND(AVG(monthly_charges), 2)  AS avg_monthly_charges
FROM   clean.subscribers
GROUP  BY tenure_band
ORDER  BY tenure_band;

-- Q3. Which commercial configuration leaks hardest?
CREATE OR REPLACE VIEW analytics.v_churn_by_plan AS
SELECT p.contract,
       p.internet_service,
       p.payment_method,
       COUNT(*)                          AS subscribers,
       ROUND(AVG(s.churn_flag) * 100, 2) AS churn_rate_pct,
       ROUND(SUM(s.monthly_charges * s.churn_flag), 2) AS monthly_revenue_lost
FROM   clean.subscribers s
JOIN   clean.dim_plan    p USING (plan_id)
GROUP  BY p.contract, p.internet_service, p.payment_method
HAVING COUNT(*) >= 30
ORDER  BY churn_rate_pct DESC;

-- Q4. Does bundling protect us? (product-attachment hypothesis)
CREATE OR REPLACE VIEW analytics.v_churn_by_addons AS
SELECT add_on_count,
       COUNT(*)                        AS subscribers,
       ROUND(AVG(churn_flag) * 100, 2) AS churn_rate_pct,
       ROUND(AVG(monthly_charges), 2)  AS avg_monthly_charges
FROM   clean.subscribers
GROUP  BY add_on_count
ORDER  BY add_on_count;

-- Q5. Is the churn concentrated in our valuable customers or our cheap ones?
--     NTILE(10) — the value decile split you reuse in the decision layer.
CREATE OR REPLACE VIEW analytics.v_churn_by_value_decile AS
WITH d AS (
    SELECT customer_id,
           monthly_charges,
           churn_flag,
           NTILE(10) OVER (ORDER BY monthly_charges) AS value_decile
    FROM   clean.subscribers
)
SELECT value_decile,
       COUNT(*)                                  AS subscribers,
       ROUND(MIN(monthly_charges), 2)            AS min_monthly,
       ROUND(MAX(monthly_charges), 2)            AS max_monthly,
       ROUND(AVG(churn_flag) * 100, 2)           AS churn_rate_pct,
       ROUND(SUM(monthly_charges * churn_flag),2) AS monthly_revenue_lost
FROM   d
GROUP  BY value_decile
ORDER  BY value_decile;

-- Q6. Survival curve: share still active at each tenure month, plus the
--     month-over-month change. LAG() over the tenure axis.
CREATE OR REPLACE VIEW analytics.v_survival_by_tenure AS
WITH by_month AS (
    SELECT tenure_months,
           COUNT(*)        AS subscribers,
           SUM(churn_flag) AS churned
    FROM   clean.subscribers
    GROUP  BY tenure_months
),
cum AS (
    SELECT tenure_months,
           subscribers,
           churned,
           SUM(subscribers) OVER (ORDER BY tenure_months DESC
                                  ROWS BETWEEN UNBOUNDED PRECEDING
                                           AND CURRENT ROW) AS at_risk
    FROM   by_month
)
SELECT tenure_months,
       subscribers,
       churned,
       at_risk,
       ROUND(churned::NUMERIC / NULLIF(at_risk, 0) * 100, 2) AS hazard_pct,
       ROUND(churned::NUMERIC / NULLIF(at_risk, 0) * 100
             - LAG(churned::NUMERIC / NULLIF(at_risk, 0) * 100)
               OVER (ORDER BY tenure_months), 2)             AS hazard_change_pp
FROM   cum
ORDER  BY tenure_months;
