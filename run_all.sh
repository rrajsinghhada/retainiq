#!/usr/bin/env bash
# RetainIQ | full rebuild. Assumes raw.telco_customers is already loaded.
set -euo pipefail
: "${DATABASE_URL:?set DATABASE_URL first (source .env)}"
for f in sql/01_schemas.sql sql/03_clean.sql sql/04_analytics.sql \
         sql/05_ml.sql; do
  echo "--> $f"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f "$f"
done
echo "--> 07_train_and_score.py"
python 07_train_and_score.py
echo "--> sql/06_decision.sql"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f sql/06_decision.sql
echo "rebuild complete"
