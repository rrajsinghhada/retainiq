-- Q9. If we could only protect one slice of the base, which slice holds the
--     most lost revenue?
-- Verifies: "61.6% of lost revenue comes from subscribers paying 80+."
SELECT CASE WHEN monthly_charges >= 80 THEN '80 and above' ELSE 'below 80' END AS arpu_band,
       COUNT(*)                                    AS subscribers,
       SUM(churn_flag)                             AS churned,
       ROUND(AVG(churn_flag) * 100, 2)             AS churn_rate_pct,
       ROUND(SUM(monthly_charges * churn_flag), 2) AS monthly_revenue_lost,
       ROUND(SUM(monthly_charges * churn_flag)
             / SUM(SUM(monthly_charges * churn_flag)) OVER () * 100, 1) AS pct_of_all_loss
FROM   clean.subscribers
GROUP  BY 1;
