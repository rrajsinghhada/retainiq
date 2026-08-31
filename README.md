# RetainIQ — Retention Decision Engine

A telco loses a quarter of its subscribers. The retention budget is finite. Who
do you spend it on, how much do you spend, and where does that spend stop paying
for itself?

Most churn projects stop at the first question. This one answers all three.

---

## The problem

Predicting churn is the easy half. A model that tells you 1,869 subscribers are
likely to leave has told you nothing about what to do, because it has not told
you which of them are worth paying to keep. A customer paying ₹21 a month with
an 80% churn probability and a customer paying ₹105 a month with a 40%
probability are not the same retention decision, and no ranking by probability
will distinguish them.

RetainIQ closes that gap: it multiplies each subscriber's predicted churn
probability by their lifetime value to produce a **value at risk**, then derives
the break-even offer size below which no intervention is worth making.

## What it found

Across 7,043 subscribers:

- **26.5% churn, but they carry 30.5% of monthly revenue.** Churn is not evenly
  distributed. 61.6% of the lost revenue comes from subscribers billing ₹80+.
- **Commitment predicts retention; tenure mostly does not.** Month-to-month
  churns at 42.7%, one-year at 11.3%, two-year at 2.8%. The apparent "first six
  months" effect largely dissolves once you control for contract type — within
  one-year and two-year contracts, churn actually *rises* slightly with tenure.
- **The premium product retains worst.** Fibre optic subscribers pay 57% more
  than DSL and churn at 41.9% against 19.0%.
- **Risk factors compound.** Month-to-month + fibre + electronic check churns at
  60.4% — 1,307 subscribers, 18.6% of the base, and the highest-ARPU group in
  the dataset.

## The recommendation

**A ₹160 retention offer, extended to the 4,256 subscribers whose value at risk
exceeds ₹370.** Net contribution: ₹1,275,282.

Scenario testing across offer sizes from ₹20 to ₹400 shows the return peaking in
the ₹140–160 range and falling away on either side. At ₹400 the programme
returns 44% less, because the qualifying threshold rises faster than the
persuasion improves. The peak is flat between ₹140 and ₹160 — net contribution
varies by 0.01% — so the recommendation survives a material error in the
response assumptions.

Full write-up: [DIAGNOSIS.md](DIAGNOSIS.md)

## Market context: does this apply to Indian telecom?

The subscriber data is a US sample, so a second layer was built from TRAI's
monthly Telecom Subscription Data reports — circle-level, genuinely Indian, and
with a real monthly time axis the snapshot cannot provide.

**Vi is losing roughly 988,000 subscribers a month, and the losses are
concentrated by circle category:**

| Category | Circles | Net change per month |
|---|---|---|
| B | 8 | −711,156 |
| A | 5 | −237,621 |
| Metro | 3 | −32,148 |
| C | 6 | −6,932 |

Eight Category B circles account for **72% of the total monthly loss** across
just over a third of the circles. Category C is close to flat. The bleeding is
not in the metros where competition is fiercest, nor in the thin rural circles —
it is concentrated in the mid-tier band.

Madhya Pradesh is worst at −166,297 a month, Rajasthan second at −123,717.
Rajasthan's Vi base fell from 10.65m in April 2024 to 8.98m by June 2025, a
15.6% decline with a loss in every observed month. Karnataka is the only circle
growing, at +44,365 a month — a question worth asking rather than an answer.

**This layer is deliberately not joined to the subscriber model.** The Kaggle
set is subscriber-level and US-flavoured; TRAI is circle-level aggregate and
Indian. They share no key and forcing a join would invent a relationship that
does not exist. They run alongside each other: one supplies the decision
mechanics, the other the market backdrop.

Two honest notes on the data. TRAI publishes PDFs whose internal rendering
varies month to month — 8 of 15 reports parsed with every row validated against
the report's own totals, and the remaining 7 were left out rather than
hand-transcribed into numbers nobody could reproduce. That leaves gaps in the
series, so the analytics carry `months_elapsed` and an `is_adjacent` flag and
normalise per month; a raw month-over-month difference across a five-month gap
would overstate a single month's loss fivefold. Separately, net subscriber
change is not a churn rate — it nets gross additions, disconnections and
porting in both directions.


## Model performance

| Model | AUC | Top-decile precision | Lift | Brier |
|---|---|---|---|---|
| Logistic regression | 0.8411 | 76.1% | 2.87× | 0.1633 |
| XGBoost | 0.8269 | 75.6% | 2.85× | 0.1647 |

Logistic regression wins on this dataset — 7,000 rows of largely categorical
features with roughly linear relationships is not where gradient boosting earns
its keep. It also calibrates better, which matters because these probabilities
get multiplied by CLV downstream. Class imbalance is handled with class weights
rather than SMOTE, for the same reason: SMOTE synthesises minority points in
feature space and distorts the calibration the economics layer depends on.

Lift is the headline metric rather than AUC, because retention teams work a
target list, not a probability distribution.

## How it works

```
CSV → raw (all TEXT, load never fails)
        ↓
      clean (typed, constrained, one row per subscriber)
        ↓
      analytics (15 diagnostic queries: who is leaving and why)
        ↓
   [ Python: logistic regression + XGBoost ]
        ↓
      ml.churn_scores (probabilities written BACK to Postgres)
        ↓
      decision (CLV → value at risk → offer threshold → simulator)
        ↓
      Power BI
```

Five PostgreSQL schemas in one database. The write-back is the design decision
that matters: predictions return to the warehouse rather than living in a
notebook, so the economics layer, the target list and the dashboard all read
from SQL. It also means a natural-language query layer can later be pointed at
`analytics` and `decision` only, with no grant on `raw` — so it physically
cannot reach unvalidated data.

Every assumption lives in `decision.assumptions`, one row per scenario. The
simulator is not code; it is the same views evaluated against different
assumption rows.

## Repository

```
sql/01_schemas.sql          five schemas
sql/02_raw.sql              landing table
sql/03_clean.sql            typed layer + plan dimension
sql/04_analytics.sql        six diagnostic views
sql/05_ml.sql               score write-back tables
sql/06_decision.sql         assumptions, CLV, value at risk, simulator
sql/queries/                15 analytical queries, one business question each
sql/07_trai_raw.sql         TRAI staging tables
sql/08_trai_clean.sql       circle and operator dimensions, monthly facts
sql/09_trai_analytics.sql   gap-aware market views
07_train_and_score.py       train, evaluate, write scores back
08_export_for_powerbi.sh    two CSVs for the dashboard
09_parse_trai.py            TRAI PDF parser, with self-tests
run_all.sh                  full rebuild from one command
DIAGNOSIS.md                one-page written diagnosis
```

## Running it

Requires PostgreSQL client tools and a Postgres database (built on Neon).

```bash
conda env create -f environment.yml && conda activate retainiq

echo 'export DATABASE_URL="postgresql://..."' > .env
source .env

psql "$DATABASE_URL" -f sql/01_schemas.sql
psql "$DATABASE_URL" -f sql/02_raw.sql
psql "$DATABASE_URL" -c "\copy raw.telco_customers FROM 'data/WA_Fn-UseC_-Telco-Customer-Churn.csv' WITH (FORMAT csv, HEADER true)"
./run_all.sh
```

Dataset: [IBM Telco Customer Churn](https://www.kaggle.com/datasets/blastchar/telco-customer-churn),
7,043 subscribers. Download it to `data/` — it is not committed.

Every script is idempotent. `run_all.sh` rebuilds the entire warehouse and
reproduces every figure above.

## What this project cannot tell you

Stated plainly, because these are the questions worth asking of it.

**It measures propensity, not persuadability.** The model identifies who is
likely to leave, not who can be talked out of it. A subscriber at 90% churn
probability may be unreachable while one at 50% is highly persuadable. Resolving
this requires an uplift model trained on a randomised holdout — the offer
withheld from a random control group and the difference measured. No amount of
observational data substitutes for that experiment.

**The offer response curve is assumed, not measured.** The relationship between
offer size and save rate is asserted from judgment
(`save_rate = 0.50 × (1 − e^(−offer/80))`). Sensitivity scenarios spanning a 25%
to 55% save rate are included and the recommendation holds across them, but the
curve is an input, not a finding. Note that a *constant* save rate across the
ladder would be worse than an assumed curve: it degenerates the optimisation, so
that net contribution falls monotonically and the "optimal" offer is always the
smallest one possible.

**Expected tenure is a counterfactual, and that is deliberate.** CLV uses how
long a subscriber is worth *if the offer succeeds*, taken from the segment
hazard — not how long they would last on their current trajectory. So a
subscriber can carry a 79.9% churn probability and a 72-month expected life at
once: the first is their risk today, the second is their worth if retained.

This looks like an inconsistency, so the alternative was built and tested:
deriving each subscriber's expected tenure from their own predicted hazard,
`h = 1 − (1 − p)^(1/W)`. It was rejected. Counting risk twice — once in the
probability, once in the shortened tenure — makes the two effects cancel and
inverts the target list toward low-risk subscribers. The top of the list filled
with two-year contracts at 16% churn probability, which is precisely the
"discounting people who were never going to leave" failure the project exists to
avoid.

`decision.v_tenure_method_comparison` keeps both methods side by side. One
subscriber ranks 1st under the counterfactual definition and 1,799th under the
individual-hazard one.

The open question the counterfactual leaves is whose hazard a saved subscriber
should inherit — their existing segment's, or the segment they move into if the
intervention changes their contract. Answering that properly needs post-campaign
data.

**Contract effects are correlational.** Whether two-year contracts cause
retention, or already-committed customers are the ones who sign them, cannot be
separated from this data.

**The subscriber data is US-flavoured.** Indian subscriber-level telecom data
is not public. Monetary figures are the dataset's own units, written as ₹ for
the Indian telecom framing. The TRAI layer above supplies genuine Indian market
context, deliberately as a separate layer rather than a forced join.

## Next

Uplift modelling on a randomised holdout, answering the incrementality question
properly. Then budget optimisation across retention channels, with measured
response curves instead of assumed ones.

---

Built by [Rishiraj Singh Hada](https://github.com/rrajsinghhada) · MBA Business
Analytics, BITS Pilani
