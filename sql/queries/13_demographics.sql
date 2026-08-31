-- Q13. Do household characteristics tell us anything we can act on?
-- Mostly a negative result, and worth having: senior citizens churn more but
-- are a small slice, and partner/dependents matter less than commitment does.
-- Knowing which variables DON'T drive your model is an interview answer too.
SELECT is_senior, has_partner, has_dependents,
       COUNT(*)                        AS subscribers,
       ROUND(AVG(churn_flag) * 100, 2) AS churn_rate_pct,
       ROUND(AVG(monthly_charges), 2)  AS arpu
FROM   clean.subscribers
GROUP  BY is_senior, has_partner, has_dependents
ORDER  BY churn_rate_pct DESC;
