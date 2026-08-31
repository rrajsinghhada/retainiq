#!/usr/bin/env bash
# 08_export_for_powerbi.sh
# Produces two CSVs in exports/ to carry to a Windows machine.
#
# Deliberately only two files. The first is one row per subscriber with every
# attribute AND the model/economics output already joined, so Power BI can
# aggregate it any way you like without going back to the database. The second
# is the offer ladder, which cannot be derived from the first.
#
# Run:  source .env && export DATABASE_URL && ./08_export_for_powerbi.sh

set -euo pipefail
: "${DATABASE_URL:?set DATABASE_URL first (source .env && export DATABASE_URL)}"
mkdir -p exports

echo "--> exports/subscribers_scored.csv"
psql "$DATABASE_URL" -c "\copy (
  SELECT s.customer_id,
         s.gender, s.is_senior, s.has_partner, s.has_dependents,
         s.tenure_months, s.tenure_band,
         s.contract, s.payment_method, s.paperless_billing,
         s.internet_service, s.phone_service, s.multiple_lines,
         s.online_security, s.online_backup, s.device_protection,
         s.tech_support, s.streaming_tv, s.streaming_movies,
         s.add_on_count,
         s.monthly_charges, s.total_charges,
         s.churn_flag,
         e.p_churn,
         e.expected_tenure_months,
         e.clv,
         e.value_at_risk,
         e.var_threshold,
         e.is_targeted
  FROM   clean.subscribers s
  JOIN   decision.v_customer_economics e ON e.customer_id = s.customer_id
  WHERE  e.scenario = 'baseline'
  ORDER  BY e.value_at_risk DESC
) TO 'exports/subscribers_scored.csv' CSV HEADER"

echo "--> exports/simulator.csv"
psql "$DATABASE_URL" -c "\copy (
  SELECT scenario, offer_cost, assumed_save_rate, targeted, var_threshold,
         offer_spend, expected_saves, saved_contribution, net_contribution
  FROM   decision.v_simulator
  WHERE  scenario LIKE 'offer_%'
  ORDER  BY offer_cost
) TO 'exports/simulator.csv' CSV HEADER"

echo
wc -l exports/*.csv
echo "done. Copy exports/ to a USB stick. Do NOT copy .env."
