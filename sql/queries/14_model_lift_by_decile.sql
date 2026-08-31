-- Q14. Does the model actually concentrate churners at the top of the list?
--      This is the number to lead with, not AUC: retention teams work a list.
-- Verifies: "2.87x lift in the top decile."
-- Window function: NTILE(10) over predicted probability.
WITH scored AS (
    SELECT s.churn_flag,
           NTILE(10) OVER (ORDER BY sc.p_churn DESC) AS score_decile
    FROM   clean.subscribers s
    JOIN   ml.churn_scores  sc ON sc.customer_id = s.customer_id
    JOIN   ml.active_model  am ON am.model_version = sc.model_version
)
SELECT score_decile,
       COUNT(*)                        AS subscribers,
       SUM(churn_flag)                 AS churners,
       ROUND(AVG(churn_flag) * 100, 2) AS churn_rate_pct,
       ROUND(AVG(churn_flag) / (SELECT AVG(churn_flag) FROM clean.subscribers), 2) AS lift
FROM   scored
GROUP  BY score_decile
ORDER  BY score_decile;
