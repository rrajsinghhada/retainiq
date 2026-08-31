-- Q8. Is churn hitting our cheap customers or our valuable ones?
--     (This is the question that justifies the whole value layer.)
-- Window function: NTILE(10) over spend.
WITH d AS (
    SELECT monthly_charges, churn_flag,
           NTILE(10) OVER (ORDER BY monthly_charges) AS value_decile
    FROM   clean.subscribers
)
SELECT value_decile,
       COUNT(*)                                   AS subscribers,
       ROUND(MIN(monthly_charges), 2)             AS min_monthly,
       ROUND(MAX(monthly_charges), 2)             AS max_monthly,
       ROUND(AVG(churn_flag) * 100, 2)            AS churn_rate_pct,
       ROUND(SUM(monthly_charges * churn_flag),2) AS monthly_revenue_lost
FROM   d
GROUP  BY value_decile
ORDER  BY value_decile;
