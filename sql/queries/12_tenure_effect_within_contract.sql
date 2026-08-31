-- Q12. Is the tenure-ARPU relationship real, or an artefact of long-tenure
--      customers sitting on longer contracts?
-- Second confound check. If ARPU still rises with tenure inside each contract
-- tier, the relationship is not explained by contract mix.
SELECT contract,
       tenure_band,
       COUNT(*)                        AS subscribers,
       ROUND(AVG(monthly_charges), 2)  AS arpu,
       ROUND(AVG(churn_flag) * 100, 2) AS churn_rate_pct
FROM   clean.subscribers
GROUP  BY contract, tenure_band
ORDER  BY contract, tenure_band;
