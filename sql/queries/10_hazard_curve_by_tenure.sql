-- Q10. Month by month, what share of the still-active base leaves, and when
--      does the bleeding slow down?
-- Window functions: running SUM() OVER for the at-risk population, LAG() for
--                   the month-over-month change in hazard.
WITH by_month AS (
    SELECT tenure_months, COUNT(*) AS subscribers, SUM(churn_flag) AS churned
    FROM   clean.subscribers GROUP BY tenure_months
),
cum AS (
    SELECT tenure_months, subscribers, churned,
           SUM(subscribers) OVER (ORDER BY tenure_months DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS at_risk
    FROM by_month
)
SELECT tenure_months, subscribers, churned, at_risk,
       ROUND(churned::NUMERIC / at_risk * 100, 2) AS hazard_pct,
       ROUND(churned::NUMERIC / at_risk * 100
             - LAG(churned::NUMERIC / at_risk * 100) OVER (ORDER BY tenure_months), 2)
                                                  AS hazard_change_pp
FROM   cum
ORDER  BY tenure_months
LIMIT  24;
