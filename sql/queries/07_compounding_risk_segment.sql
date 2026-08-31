-- Q7. Do our risk factors stack, or are they three views of the same customers?
-- Verifies: "Month-to-month + fibre + electronic check churns at 60.4%,
--            1,307 subscribers, 18.6% of the base."
WITH flagged AS (
    SELECT churn_flag,
           monthly_charges,
           (contract        = 'Month-to-month')::INT AS f_m2m,
           (internet_service= 'Fiber optic')::INT    AS f_fibre,
           (payment_method  = 'Electronic check')::INT AS f_echeck
    FROM clean.subscribers
)
SELECT f_m2m + f_fibre + f_echeck        AS risk_factors_present,
       COUNT(*)                          AS subscribers,
       ROUND(COUNT(*)::NUMERIC / SUM(COUNT(*)) OVER () * 100, 1) AS pct_of_base,
       ROUND(AVG(churn_flag) * 100, 2)   AS churn_rate_pct,
       ROUND(AVG(monthly_charges), 2)    AS arpu
FROM   flagged
GROUP  BY 1
ORDER  BY 1;
