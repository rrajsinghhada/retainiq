-- Q2. Where in the customer lifecycle do we lose people, and are the ones we
--     lose worth less or more than the ones we keep?
-- Verifies: "52.9% in the first six months, 9.5% past four years; ARPU rises
--            from 54.74 to 73.95 with tenure."
-- Caveat: tenure bands on a snapshot are a synthetic cohort read, not a
--         calendar retention triangle. Say so if asked.
SELECT tenure_band,
       COUNT(*)                        AS subscribers,
       SUM(churn_flag)                 AS churned,
       ROUND(AVG(churn_flag) * 100, 2) AS churn_rate_pct,
       ROUND(AVG(monthly_charges), 2)  AS arpu
FROM   clean.subscribers
GROUP  BY tenure_band
ORDER  BY tenure_band;
