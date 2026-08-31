-- Q4. Does how a customer pays tell us anything about whether they stay?
-- Verifies: "Electronic check 45.3%, every other method 15-19%."
-- Reading: the rail itself causes nothing. It marks the absence of a stored
--          payment instrument, so each cycle is a fresh decision.
SELECT payment_method,
       COUNT(*)                        AS subscribers,
       ROUND(AVG(churn_flag) * 100, 2) AS churn_rate_pct,
       ROUND(AVG(monthly_charges), 2)  AS arpu
FROM   clean.subscribers
GROUP  BY payment_method
ORDER  BY churn_rate_pct DESC;
