-- Q3. Does contractual commitment predict retention, and does it cost us
--     anything in revenue to sell the longer contract?
-- Verifies: "42.7% / 11.3% / 2.8% on near-identical ARPU."
SELECT contract,
       COUNT(*)                        AS subscribers,
       ROUND(AVG(churn_flag) * 100, 2) AS churn_rate_pct,
       ROUND(AVG(monthly_charges), 2)  AS arpu,
       ROUND(AVG(tenure_months), 1)    AS avg_tenure_months
FROM   clean.subscribers
GROUP  BY contract
ORDER  BY churn_rate_pct DESC;
