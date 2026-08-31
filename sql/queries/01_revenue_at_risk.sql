-- Q1. How much of the business is actually leaving, in money rather than headcount?
-- Verifies: "26.5% of subscribers, carrying 30.5% of monthly revenue."
SELECT COUNT(*)                                          AS subscribers,
       SUM(churn_flag)                                   AS churned,
       ROUND(AVG(churn_flag) * 100, 2)                   AS churn_rate_pct,
       ROUND(SUM(monthly_charges), 2)                    AS monthly_revenue,
       ROUND(SUM(monthly_charges * churn_flag), 2)       AS monthly_revenue_lost,
       ROUND(SUM(monthly_charges * churn_flag)
             / SUM(monthly_charges) * 100, 2)            AS revenue_at_risk_pct
FROM   clean.subscribers;
