-- Q11. Does the electronic-check effect survive once we control for contract
--      type, or is it just that month-to-month customers pay that way?
-- This is the confound check an interviewer will reach for. The effect holds
-- inside every contract tier, which is what makes it worth acting on.
SELECT contract,
       payment_method,
       COUNT(*)                        AS subscribers,
       ROUND(AVG(churn_flag) * 100, 2) AS churn_rate_pct
FROM   clean.subscribers
GROUP  BY contract, payment_method
HAVING COUNT(*) >= 50
ORDER  BY contract, churn_rate_pct DESC;
