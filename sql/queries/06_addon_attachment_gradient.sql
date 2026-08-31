-- Q6. Does bundling more services protect against churn?
-- Verifies: "45.8% at one add-on falling to 5.3% at six."
-- Trap: the zero-add-on group looks safe (21.4%) but is mostly phone-only
--       customers paying 32.79 who have little to leave. Compositional
--       artefact, not a protective effect. Read the gradient from 1 upward.
SELECT add_on_count,
       COUNT(*)                        AS subscribers,
       ROUND(AVG(churn_flag) * 100, 2) AS churn_rate_pct,
       ROUND(AVG(monthly_charges), 2)  AS arpu,
       ROUND(AVG((internet_service = 'No')::INT) * 100, 1) AS pct_no_internet
FROM   clean.subscribers
GROUP  BY add_on_count
ORDER  BY add_on_count;
