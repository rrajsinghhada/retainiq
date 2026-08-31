"""
07_train_and_score.py
RetainIQ | Read clean.subscribers from Neon, train, score, write back.

The point of this script is the last step. Predictions that stay in a notebook
cannot be joined to the economics layer, so everything ends up in Postgres:
probabilities in ml.churn_scores, evaluation numbers in ml.model_metrics.

Run:  DATABASE_URL="postgresql://..." python 07_train_and_score.py
"""

import os
import numpy as np
import pandas as pd
from sqlalchemy import create_engine, text
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.metrics import roc_auc_score, brier_score_loss
from xgboost import XGBClassifier

DB = os.environ["DATABASE_URL"]
engine = create_engine(DB)

# ---------------------------------------------------------------------------
# 1. Read the clean layer. No feature engineering in pandas that could equally
#    live in SQL -- tenure_band and add_on_count already came from the database.
# ---------------------------------------------------------------------------
df = pd.read_sql("SELECT * FROM clean.subscribers", engine)
print(f"loaded {len(df):,} subscribers, churn rate {df.churn_flag.mean():.1%}")

y = df["churn_flag"]
drop = ["customer_id", "churn_flag", "plan_id", "total_charges_imputed"]
X = df.drop(columns=drop)

cat = X.select_dtypes(include=["object"]).columns.tolist()
num = X.select_dtypes(include=["number", "bool"]).columns.tolist()

X_tr, X_te, y_tr, y_te = train_test_split(
    X, y, test_size=0.25, stratify=y, random_state=42
)

pre = ColumnTransformer([
    ("cat", OneHotEncoder(handle_unknown="ignore", drop="first"), cat),
    ("num", StandardScaler(), num),
])


def top_decile(y_true, p):
    """Recall, precision and lift in the top 10% by predicted probability.
    This is the metric retention teams actually live with: they work a list."""
    k = int(len(p) * 0.10)
    idx = np.argsort(p)[::-1][:k]
    hits = y_true.iloc[idx].sum()
    recall = hits / y_true.sum()
    precision = hits / k
    lift = precision / y_true.mean()
    return recall, precision, lift


def evaluate(name, model, is_pipeline=True):
    p = model.predict_proba(X_te)[:, 1] if is_pipeline else model.predict_proba(X_te)[:, 1]
    auc = roc_auc_score(y_te, p)
    rec, prec, lift = top_decile(y_te, p)
    brier = brier_score_loss(y_te, p)
    print(f"{name:10s} AUC {auc:.4f} | top-decile recall {rec:.3f} "
          f"precision {prec:.3f} lift {lift:.2f} | Brier {brier:.4f}")
    return dict(auc=auc, recall_top_decile=rec, precision_top_decile=prec,
                lift_top_decile=lift, brier_score=brier)


# ---------------------------------------------------------------------------
# 2. Logistic regression FIRST, and keep it.
#    class_weight="balanced", not SMOTE: SMOTE synthesises minority points in
#    feature space and distorts the probability calibration you are about to
#    multiply by CLV downstream.
# ---------------------------------------------------------------------------
logit = Pipeline([
    ("pre", pre),
    ("clf", LogisticRegression(max_iter=2000, class_weight="balanced")),
])
logit.fit(X_tr, y_tr)
m_logit = evaluate("logit_v1", logit)

# Odds ratios -- the reason you keep this model. These are the sentences you
# say out loud: "a month-to-month contract multiplies churn odds by 2.4x."
names = logit.named_steps["pre"].get_feature_names_out()
coefs = logit.named_steps["clf"].coef_[0]
odds = (pd.DataFrame({"feature": names, "odds_ratio": np.exp(coefs)})
          .sort_values("odds_ratio", ascending=False))
print("\ntop churn drivers (odds ratios):")
print(odds.head(8).to_string(index=False))
print("\ntop retention drivers:")
print(odds.tail(5).to_string(index=False))

# ---------------------------------------------------------------------------
# 3. XGBoost, to show you can do the accurate version too.
# ---------------------------------------------------------------------------
spw = (y_tr == 0).sum() / (y_tr == 1).sum()
xgb = Pipeline([
    ("pre", pre),
    ("clf", XGBClassifier(
        n_estimators=400, max_depth=4, learning_rate=0.05,
        subsample=0.8, colsample_bytree=0.8,
        scale_pos_weight=spw, eval_metric="logloss", random_state=42)),
])
xgb.fit(X_tr, y_tr)
m_xgb = evaluate("xgb_v1", xgb)

# ---------------------------------------------------------------------------
# 4. Write scores for the FULL population back to Postgres.
# ---------------------------------------------------------------------------
def write_scores(version, model, metrics):
    out = pd.DataFrame({
        "customer_id": df["customer_id"],
        "model_version": version,
        "p_churn": model.predict_proba(X)[:, 1].round(5),
    })
    with engine.begin() as con:
        con.execute(text("DELETE FROM ml.churn_scores WHERE model_version = :v"),
                    {"v": version})
        out.to_sql("churn_scores", con, schema="ml",
                   if_exists="append", index=False)
        con.execute(text("DELETE FROM ml.model_metrics WHERE model_version = :v"),
                    {"v": version})
        con.execute(text("""
            INSERT INTO ml.model_metrics
              (model_version, auc, recall_top_decile, precision_top_decile,
               lift_top_decile, brier_score, notes)
            VALUES (:v, :auc, :rec, :prec, :lift, :brier, :notes)
        """), dict(v=version, auc=float(metrics["auc"]),
                   rec=float(metrics["recall_top_decile"]),
                   prec=float(metrics["precision_top_decile"]),
                   lift=float(metrics["lift_top_decile"]),
                   brier=float(metrics["brier_score"]),
                   notes="25% holdout, class-weighted, no SMOTE"))
    print(f"wrote {len(out):,} scores for {version}")


write_scores("logit_v1", logit, m_logit)
write_scores("xgb_v1", xgb, m_xgb)

with engine.begin() as con:
    con.execute(text("UPDATE ml.active_model SET model_version = 'logit_v1'"))

print("\ndone. now run: SELECT * FROM decision.v_simulator;")
