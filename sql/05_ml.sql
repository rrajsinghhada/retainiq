-- 05_ml.sql
-- The write-back table. Python trains and scores; the probabilities come home
-- to Postgres so that CLV, value-at-risk and Power BI all read from SQL.
--
-- model_version lets logistic regression and XGBoost coexist so you can show
-- the same decision layer under both models.

DROP TABLE IF EXISTS ml.churn_scores CASCADE;

CREATE TABLE ml.churn_scores (
    customer_id   TEXT         NOT NULL REFERENCES clean.subscribers(customer_id),
    model_version TEXT         NOT NULL,
    p_churn       NUMERIC(6,5) NOT NULL CHECK (p_churn BETWEEN 0 AND 1),
    scored_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    PRIMARY KEY (customer_id, model_version)
);

CREATE INDEX ON ml.churn_scores (model_version, p_churn DESC);

-- Which model the decision layer uses by default. One row.
DROP TABLE IF EXISTS ml.active_model CASCADE;

CREATE TABLE ml.active_model (
    only_one_row  BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (only_one_row),
    model_version TEXT NOT NULL
);

INSERT INTO ml.active_model (model_version) VALUES ('logit_v1');

-- Model quality, recorded by hand after each training run so the numbers on
-- your resume are reproducible from the database rather than from memory.
DROP TABLE IF EXISTS ml.model_metrics CASCADE;

CREATE TABLE ml.model_metrics (
    model_version      TEXT PRIMARY KEY,
    trained_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    auc                NUMERIC(5,4),
    recall_top_decile  NUMERIC(5,4),
    precision_top_decile NUMERIC(5,4),
    lift_top_decile    NUMERIC(6,3),
    brier_score        NUMERIC(6,5),
    notes              TEXT
);
