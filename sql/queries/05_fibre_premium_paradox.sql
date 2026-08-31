-- Q5. Our premium product should retain best. Does it?
-- Verifies: "Fibre churns 41.9% vs DSL 19.0%, while charging 57% more."
SELECT internet_service,
       COUNT(*)                        AS subscribers,
       ROUND(AVG(monthly_charges), 2)  AS arpu,
       ROUND(AVG(churn_flag) * 100, 2) AS churn_rate_pct,
       ROUND(SUM(monthly_charges * churn_flag), 2) AS monthly_revenue_lost
FROM   clean.subscribers
GROUP  BY internet_service
ORDER  BY churn_rate_pct DESC;

-- The premium, computed rather than asserted:
SELECT ROUND((f.arpu - d.arpu) / d.arpu * 100, 1) AS fibre_premium_pct
FROM  (SELECT AVG(monthly_charges) arpu FROM clean.subscribers WHERE internet_service = 'Fiber optic') f,
      (SELECT AVG(monthly_charges) arpu FROM clean.subscribers WHERE internet_service = 'DSL')         d;
