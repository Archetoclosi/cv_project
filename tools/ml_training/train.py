#!/usr/bin/env python3
"""
Risk Engine — Training Pipeline
================================
Input:  risk_engine_training_data.csv  (raccolto dall'app)
Output: RiskEngine.mlmodel             (da copiare in ios/Runner/)

Uso:
    python train.py --data path/to/risk_engine_training_data.csv
    python train.py --data path/to/data.csv --output path/to/RiskEngine.mlmodel
"""

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.metrics import (
    classification_report,
    confusion_matrix,
    roc_auc_score,
)
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline
import coremltools as ct
import joblib

# ─── Feature columns (devono corrispondere a FeatureVector) ──────────────────

FEATURE_COLS = [
    # Vision
    "phone_detected",
    "phone_confidence",
    "phone_persistence",
    "phone_area_ratio",
    "phone_center_x",
    "phone_center_y",
    "face_detected",
    "face_count",
    # IMU
    "accel_magnitude_mean",
    "accel_magnitude_std",
    "gyro_magnitude_mean",
    "gyro_magnitude_std",
    "tilt_angle",
    "mag_magnitude_std",
    # Derived (calcolate in FeatureVector, già presenti nel CSV)
    "is_stationary",
    "tilt_in_photo_range",
    "phone_strength",
]

LABEL_COL = "is_threat"

# ─── Helpers ─────────────────────────────────────────────────────────────────


def load_data(csv_path: str) -> tuple[np.ndarray, np.ndarray]:
    df = pd.read_csv(csv_path)

    # Sanity check
    missing = [c for c in FEATURE_COLS + [LABEL_COL] if c not in df.columns]
    if missing:
        raise ValueError(f"Colonne mancanti nel CSV: {missing}")

    print(f"\n📊 Dataset caricato: {len(df)} sample")
    print(f"   Threats : {df[LABEL_COL].sum()} ({df[LABEL_COL].mean()*100:.1f}%)")
    print(f"   Safe    : {(~df[LABEL_COL].astype(bool)).sum()}")

    balance = min(df[LABEL_COL].mean(), 1 - df[LABEL_COL].mean())
    if balance < 0.30:
        print(f"\n⚠️  Dataset sbilanciato ({balance*100:.0f}% classe minoritaria).")
        print("   Considera di raccogliere più sample della classe minoritaria.")
        print("   Il training continua con class_weight='balanced'.\n")

    X = df[FEATURE_COLS].values.astype(np.float32)
    y = df[LABEL_COL].values.astype(np.int32)
    return X, y


def train(X: np.ndarray, y: np.ndarray) -> Pipeline:
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.20, random_state=42, stratify=y
    )

    pipeline = Pipeline([
        # StandardScaler non è strettamente necessario per RF,
        # ma lo includiamo per forward-compatibility con MLP.
        ("scaler", StandardScaler()),
        ("clf", RandomForestClassifier(
            n_estimators=100,
            max_depth=8,           # limita complessità → modello più piccolo
            min_samples_leaf=4,    # evita overfitting su dataset piccoli
            class_weight="balanced",
            random_state=42,
            n_jobs=-1,
        )),
    ])

    # ── Cross-validation ──────────────────────────────────────────────────
    print("🔄 Cross-validation (5-fold)...")
    cv_scores = cross_val_score(pipeline, X_train, y_train, cv=5, scoring="roc_auc")
    print(f"   AUC-ROC: {cv_scores.mean():.3f} ± {cv_scores.std():.3f}")

    # ── Final fit ─────────────────────────────────────────────────────────
    pipeline.fit(X_train, y_train)

    # ── Test set evaluation ───────────────────────────────────────────────
    y_pred = pipeline.predict(X_test)
    y_proba = pipeline.predict_proba(X_test)[:, 1]

    print("\n📈 Test set results:")
    print(classification_report(y_test, y_pred, target_names=["safe", "threat"]))
    print("Confusion matrix:")
    print(confusion_matrix(y_test, y_pred))
    print(f"AUC-ROC: {roc_auc_score(y_test, y_proba):.3f}")

    # ── Feature importance ────────────────────────────────────────────────
    rf = pipeline.named_steps["clf"]
    importances = sorted(
        zip(FEATURE_COLS, rf.feature_importances_),
        key=lambda x: x[1],
        reverse=True,
    )
    print("\n🌲 Feature importance (top 10):")
    for name, imp in importances[:10]:
        bar = "█" * int(imp * 40)
        print(f"   {name:<30} {bar} {imp:.3f}")

    return pipeline


def export_coreml(pipeline: Pipeline, output_path: str) -> None:
    """
    Converte il pipeline scikit-learn in un .mlmodel Core ML.
    Il modello espone:
      - Input:  17 float (le FEATURE_COLS)
      - Output: classLabel (int, 0=safe 1=threat)
                classProbability (dict, {"0": p_safe, "1": p_threat})
    """
    print(f"\n📦 Esportazione Core ML → {output_path}")

    # coremltools richiede un esempio di input per l'inferenza di shape
    sample_input = pd.DataFrame(
        [np.zeros(len(FEATURE_COLS), dtype=np.float32)],
        columns=FEATURE_COLS,
    )

    cml_model = ct.converters.sklearn.convert(
        pipeline,
        input_features=FEATURE_COLS,
        output_feature_names="risk_label",
    )

    # Metadata utile per il debug nell'app
    cml_model.short_description = "Risk Engine — phone capture detection"
    cml_model.author = "RiskEngine Training Pipeline"
    cml_model.version = "1.0"
    cml_model.input_description["phone_detected"] = "1 if phone detected in frame"
    cml_model.output_description["risk_label"] = "0=safe, 1=threat"

    # Aggiungi i nomi delle feature come metadata custom
    cml_model.user_defined_metadata["feature_cols"] = json.dumps(FEATURE_COLS)
    cml_model.user_defined_metadata["model_type"] = "random_forest"

    cml_model.save(output_path)
    print(f"✅ Salvato: {output_path}")

    # Stima dimensione
    size_kb = Path(output_path).stat().st_size / 1024
    print(f"   Dimensione: {size_kb:.1f} KB")

    # Quick sanity check: inferenza su un sample zero
    spec = ct.models.MLModel(output_path)
    test_input = {col: float(0) for col in FEATURE_COLS}
    result = spec.predict(test_input)
    print(f"   Sanity check output: {result}")


def save_sklearn_backup(pipeline: Pipeline, output_dir: str) -> None:
    """Salva anche il modello scikit-learn nativo per eventuale re-export."""
    path = str(Path(output_dir) / "risk_engine_sklearn.joblib")
    joblib.dump(pipeline, path)
    print(f"💾 Backup scikit-learn: {path}")


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Train Risk Engine model")
    parser.add_argument(
        "--data",
        required=True,
        help="Path al CSV di training (risk_engine_training_data.csv)",
    )
    parser.add_argument(
        "--output",
        default="RiskEngine.mlmodel",
        help="Path di output per il .mlmodel (default: RiskEngine.mlmodel)",
    )
    args = parser.parse_args()

    print("🚀 Risk Engine — Training Pipeline")
    print("=" * 45)

    X, y = load_data(args.data)
    pipeline = train(X, y)

    output_path = args.output
    export_coreml(pipeline, output_path)
    save_sklearn_backup(pipeline, str(Path(output_path).parent))

    print("\n🎯 Prossimo passo:")
    print(f"   Copia {output_path} in ios/Runner/")
    print("   e aggiorna MLRiskEngine.swift per usarlo.")


if __name__ == "__main__":
    main()
