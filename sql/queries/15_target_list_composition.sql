-- Q15. Who actually ends up on the call list, and does it match the diagnosis?
--      If the model and the diagnostic story disagree, one of them is wrong.
SELECT s.contract,
       COUNT(*) FILTER (WHERE e.is_targeted)                 AS targeted,
       COUNT(*)                                              AS total,
       ROUND(COUNT(*) FILTER (WHERE e.is_targeted)::NUMERIC
             / COUNT(*) * 100, 1)                            AS pct_of_segment_targeted,
       ROUND(AVG(e.value_at_risk) FILTER (WHERE e.is_targeted), 2) AS avg_value_at_risk
FROM   decision.v_customer_economics e
JOIN   clean.subscribers s ON s.customer_id = e.customer_id
WHERE  e.scenario = 'baseline'
GROUP  BY s.contract
ORDER  BY pct_of_segment_targeted DESC;
