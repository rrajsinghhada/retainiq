-- 09_trai_analytics.sql
-- The market layer. Every view here uses a genuine monthly time axis, which
-- the subscriber snapshot cannot provide.

-- Q1. Where is Vi actually losing subscribers, month by month?
--     Window function: LAG() over a real calendar, not a tenure proxy.
--
--     GAPS MATTER. Not every TRAI report parses, so consecutive rows are not
--     always consecutive months. Raw LAG() would report an Oct-to-Mar change
--     as one month's net adds and overstate it fivefold. months_elapsed makes
--     the interval explicit and per_month_change normalises for it; is_adjacent
--     flags the rows safe to read as a true monthly figure.
DROP VIEW IF EXISTS analytics.v_vi_loss_vs_porting;
DROP VIEW IF EXISTS analytics.v_vi_net_adds_by_circle;
CREATE VIEW analytics.v_vi_net_adds_by_circle AS
WITH seq AS (
    SELECT f.circle_id,
           c.circle_name,
           c.category,
           f.report_month,
           f.subscribers,
           LAG(f.subscribers)   OVER w AS prev_subscribers,
           LAG(f.report_month)  OVER w AS prev_month
    FROM   clean.fact_circle_operator_month f
    JOIN   clean.dim_circle c ON c.circle_id = f.circle_id
    WHERE  f.operator_code = 'VI'
    WINDOW w AS (PARTITION BY f.circle_id ORDER BY f.report_month)
)
SELECT circle_name,
       category,
       report_month,
       subscribers,
       subscribers - prev_subscribers                          AS change_since_prev,
       (EXTRACT(YEAR  FROM age(report_month, prev_month)) * 12
      + EXTRACT(MONTH FROM age(report_month, prev_month)))::INT AS months_elapsed,
       ROUND((subscribers - prev_subscribers)::NUMERIC
             / NULLIF(EXTRACT(YEAR  FROM age(report_month, prev_month)) * 12
                    + EXTRACT(MONTH FROM age(report_month, prev_month)), 0))
                                                               AS per_month_change,
       (EXTRACT(YEAR  FROM age(report_month, prev_month)) * 12
      + EXTRACT(MONTH FROM age(report_month, prev_month))) = 1  AS is_adjacent,
       ROUND((subscribers::NUMERIC / NULLIF(prev_subscribers, 0) - 1) * 100, 3)
                                                               AS change_pct
FROM   seq
ORDER  BY circle_name, report_month;

-- Q2. Vi's market share by circle, and whether it is eroding.
CREATE OR REPLACE VIEW analytics.v_vi_share_by_circle AS
WITH totals AS (
    SELECT circle_id, report_month, SUM(subscribers) AS all_operators
    FROM   clean.fact_circle_operator_month
    GROUP  BY circle_id, report_month
)
SELECT c.circle_name,
       c.category,
       f.report_month,
       f.subscribers                                        AS vi_subscribers,
       t.all_operators,
       ROUND(f.subscribers::NUMERIC / t.all_operators * 100, 2) AS vi_share_pct,
       ROUND((f.subscribers::NUMERIC / t.all_operators * 100)
             - LAG(f.subscribers::NUMERIC / t.all_operators * 100)
               OVER (PARTITION BY f.circle_id ORDER BY f.report_month), 3)
                                                            AS share_change_pp
FROM   clean.fact_circle_operator_month f
JOIN   totals t ON t.circle_id = f.circle_id AND t.report_month = f.report_month
JOIN   clean.dim_circle c ON c.circle_id = f.circle_id
WHERE  f.operator_code = 'VI';

-- Q3. Port-out intensity: how much MNP activity per 1,000 subscribers, by
--     circle. Normalising matters -- big circles always show big raw numbers.
CREATE OR REPLACE VIEW analytics.v_port_intensity_by_circle AS
WITH circle_total AS (
    SELECT circle_id, report_month, SUM(subscribers) AS all_operators
    FROM   clean.fact_circle_operator_month
    GROUP  BY circle_id, report_month
)
SELECT c.circle_name,
       c.category,
       c.zone,
       m.report_month,
       m.monthly_ports_mn,
       t.all_operators,
       ROUND(m.monthly_ports_mn * 1000000
             / NULLIF(t.all_operators, 0) * 1000, 2)         AS ports_per_1000_subs
FROM   clean.fact_mnp_month m
JOIN   clean.dim_circle c    ON c.circle_id = m.circle_id
LEFT   JOIN circle_total t   ON t.circle_id = m.circle_id
                            AND t.report_month = m.report_month
WHERE  m.monthly_ports_mn IS NOT NULL;

-- Q4. The cross-reference that makes this layer worth building: circles where
--     Vi is bleeding subscribers AND port activity is high. If the two line
--     up, competitive switching is the story. If they don't, Vi's losses are
--     something else -- disconnection, SIM consolidation, rural drop-off.
CREATE OR REPLACE VIEW analytics.v_vi_loss_vs_porting AS
SELECT n.circle_name,
       n.category,
       n.report_month,
       n.per_month_change               AS vi_net_adds_per_month,
       p.ports_per_1000_subs,
       RANK() OVER (PARTITION BY n.report_month ORDER BY n.per_month_change ASC)
                                        AS rank_worst_vi_loss,
       RANK() OVER (PARTITION BY n.report_month ORDER BY p.ports_per_1000_subs DESC)
                                        AS rank_highest_porting
FROM   analytics.v_vi_net_adds_by_circle n
JOIN   analytics.v_port_intensity_by_circle p
       ON p.circle_name = n.circle_name AND p.report_month = n.report_month
WHERE  n.per_month_change IS NOT NULL;

-- Q5. Operator scoreboard: who is winning each circle over the window.
CREATE OR REPLACE VIEW analytics.v_circle_operator_trend AS
SELECT c.circle_name,
       o.operator_name,
       MIN(f.report_month)                                   AS first_month,
       MAX(f.report_month)                                   AS last_month,
       MAX(f.subscribers) FILTER (WHERE f.report_month =
            (SELECT MAX(report_month) FROM clean.fact_circle_operator_month))
                                                             AS latest_subscribers,
       MAX(f.subscribers) FILTER (WHERE f.report_month =
            (SELECT MIN(report_month) FROM clean.fact_circle_operator_month))
                                                             AS earliest_subscribers
FROM   clean.fact_circle_operator_month f
JOIN   clean.dim_circle   c ON c.circle_id     = f.circle_id
JOIN   clean.dim_operator o ON o.operator_code = f.operator_code
GROUP  BY c.circle_name, o.operator_name;
