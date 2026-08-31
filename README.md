# RetainIQ — Neon build, step by step

Everything below has been run end to end against PostgreSQL 16 with your actual
CSV. The numbers in the "expected output" blocks are the real ones you should
see, so if yours differ, something went wrong at that step.

---

## Step 0 — Local setup (Mac, one time)

```bash
brew install libpq
brew link --force libpq
psql --version          # should print 16.x or 17.x
```

## Step 1 — Neon project

In the Neon console: **New Project** → name `retainiq`, database `retainiq_db`.
Pick the region nearest you from whatever the console currently offers (check
the list — don't assume). Copy the connection string; it looks like:

```
postgresql://user:pass@ep-xxx.region.aws.neon.tech/retainiq_db?sslmode=require
```

Put it in a gitignored file, never in your shell history or a notebook cell:

```bash
cd ~/projects/retainiq
echo 'DATABASE_URL="postgresql://user:pass@ep-xxx...?sslmode=require"' > .env
echo -e '.env\n*.csv\n__pycache__/' > .gitignore
source .env
```

Use the **direct** endpoint (no `-pooler` in the hostname) for loading and
migrations. The pooler endpoint is for applications.

## Step 2 — Build the schemas

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/01_schemas.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/02_raw.sql
```

Five schemas, not one `public` dump: `raw`, `clean`, `analytics`, `ml`,
`decision`. This is also what makes the optional LLM layer safe later — you
point text-to-SQL at `analytics` and `decision` only, so it physically cannot
reach the raw table.

## Step 3 — Load the CSV

```bash
psql "$DATABASE_URL" -c "\copy raw.telco_customers FROM \
  '/Users/YOU/Downloads/WA_Fn-UseC_-Telco-Customer-Churn.csv' \
  WITH (FORMAT csv, HEADER true)"
```

`\copy` (client-side), not `COPY` (server-side — Neon can't see your Mac).

Expected: `COPY 7043`

Verify before going further:

```sql
SELECT COUNT(*) AS rows, COUNT(DISTINCT customer_id) AS ids
FROM raw.telco_customers;                       -- 7043 | 7043

SELECT COUNT(*) FROM raw.telco_customers
WHERE TRIM(total_charges) = '';                 -- 11
```

**That last query is the one people get wrong.** The 11 blank `TotalCharges`
values in this file are a *single space*, not an empty string. `WHERE
total_charges = ''` returns zero rows and you conclude the data is clean. It
isn't. `TRIM` is what catches them.

## Step 4 — Clean layer

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/03_clean.sql
```

Creates `clean.dim_plan` (the commercial configuration lookup) and
`clean.subscribers` (7,043 rows, typed, with a primary key and CHECK
constraints so a bad reload fails loudly instead of silently).

Those 11 rows all have `tenure = 0` and none of them churned — new joiners who
hadn't been billed yet. They get `total_charges = 0` and a
`total_charges_imputed` flag, so the decision is visible in the data rather
than buried in a notebook.

Note what this file *doesn't* do: no `fact_usage`, no `fact_billing`, no
`circle_id`, no `churn_month`. This CSV is one snapshot row per customer with
no month column. Those tables arrive with the TRAI layer. Building them now
would mean inventing data.

## Step 5 — Diagnostic views

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/04_analytics.sql
psql "$DATABASE_URL" -c "SELECT * FROM analytics.v_churn_by_tenure_band;"
```

Expected:

```
 tenure_band  | subscribers | churned | churn_rate_pct | avg_monthly_charges
--------------+-------------+---------+----------------+---------------------
 00-06 months |        1481 |     784 |          52.94 |               54.74
 07-12 months |         705 |     253 |          35.89 |               58.95
 13-24 months |        1024 |     294 |          28.71 |               61.36
 25-48 months |        1594 |     325 |          20.39 |               65.93
 49+ months   |        2239 |     213 |           9.51 |               73.95
```

Overall: 26.54% churn, but **30.50% of monthly revenue** — churn is skewed
toward higher-ARPU subscribers. That one line is your opening slide.

Six views ship here (overview, tenure band, plan, add-ons, value decile,
survival hazard). Your spec asks for 12–15 analytical queries — write the rest
yourself, one per business question, and keep them in `sql/queries/`.

## Step 6 — Train, score, write back

```bash
pip install pandas scikit-learn xgboost sqlalchemy psycopg2-binary
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/05_ml.sql
python 07_train_and_score.py
```

Real output from this dataset:

```
logit_v1   AUC 0.8516 | top-decile recall 0.287 precision 0.761 lift 2.87
xgb_v1     AUC 0.8376 | top-decile recall 0.283 precision 0.750 lift 2.83
```

Two things worth having ready:

- **XGBoost did not beat logistic regression here.** That is a real result on a
  small, mostly-categorical dataset, and it is a much better answer to "why did
  you keep logistic regression?" than a preference for interpretability.
- The odds ratios print to console. Fibre-optic internet ≈ 3.3× churn odds; a
  two-year contract ≈ 0.21×. Those are the sentences you say out loud.

Both models' scores land in `ml.churn_scores` with a `model_version`, and the
evaluation numbers land in `ml.model_metrics` — so the figures on your resume
are reproducible from the database, not from memory.

## Step 7 — The decision layer

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/06_decision.sql
psql "$DATABASE_URL" -c "SELECT * FROM decision.v_simulator WHERE scenario LIKE 'offer_%' ORDER BY offer_cost;"
```

Every assumption lives in `decision.assumptions`, one row per scenario. When
you're asked where the save rate came from, you open a table.

The curve, on real scores:

```
 offer_cost | save_rate | targeted | net_contribution
------------+-----------+----------+------------------
     100.00 |     0.357 |     4661 |       1,192,200
     120.00 |     0.388 |     4551 |       1,243,595
     140.00 |     0.413 |     4424 |       1,268,706   ← peak
     160.00 |     0.432 |     4276 |       1,268,111
     180.00 |     0.447 |     4154 |       1,251,269
```

**The single most important design point in the whole project:** the assumed
save rate must *rise with offer size and flatten out*. If you hold it constant
across the ladder, net contribution falls monotonically and the simulator's
answer is always "offer the smallest amount possible" — no peak, no
recommendation, no conversation. The peak exists because bigger offers persuade
more people with diminishing returns. The curve used here is
`save_rate = 0.50 × (1 − e^(−offer/80))`, and it is asserted, not measured.
Say that before the interviewer asks.

Also note the peak is flat between 140 and 160. That is worth volunteering:
the recommendation is robust to a ±15% error in the response curve, which is
a stronger claim than a sharp optimum would be.

## Step 8 — Power BI

Get Data → PostgreSQL. Server `ep-xxx.region.aws.neon.tech`, database
`retainiq_db`, **Import** mode, encrypted connection on.

Use Import, not DirectQuery. Neon autosuspends when idle, so a DirectQuery
dashboard will hang on a cold start in the middle of your demo.

Pull in `analytics.v_churn_by_tenure_band`, `analytics.v_churn_by_value_decile`,
`decision.v_target_list`, `decision.v_simulator`. One executive page (churn
rate, revenue at risk, the simulator curve, the recommendation), one diagnostic
page.

---

## Rebuild from scratch

```bash
./run_all.sh          # drops and rebuilds everything except the raw load
```

Everything is idempotent — re-running any file is safe. That matters more than
it sounds: a warehouse you can rebuild with one command is one you designed; a
warehouse you clicked together in the SQL editor is one you can't defend.

## Sequencing against your four-week plan

| Week | Files | Deliverable |
|---|---|---|
| 1 | `01`–`04` + your own queries | SQL warehouse + one-page diagnosis |
| 2 | `05`, `07`, `06` | Ranked target list with economic justification |
| 3 | Power BI + simulator polish | The demoable version |
| 4 | text-to-SQL over `analytics` + `decision` only | The "ask it anything" moment |

Stop after any week and you still have a coherent project.

## Known limits — say these before you're asked

1. **No incrementality.** `p_churn` is propensity, not treatment response.
   Resolving it needs an uplift model on a randomised holdout.
2. **The save-rate response curve is invented**, not measured. Sensitivity
   range is in `decision.assumptions`.
3. **The monthly hazard is derived from an assumed observation window.** The
   Kaggle churn flag carries no time window; `window_6` and `window_24`
   scenarios show what that does to CLV.
4. **The subscriber data is US-flavoured.** TRAI stays a separate layer. Don't
   force the join.
