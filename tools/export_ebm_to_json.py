"""Export the trained Explainable Boosting Machine to plain JSON.

The EBM in `legal_metrology_ml/layer3_ml_model` is **not** a neural network, so
it cannot be converted to TFLite. It is an additive model:

    logit = intercept
          + sum_f  term_score_f(bin(x_f))          # per-feature shape functions
          + sum_ij interaction_score_ij(bin_i, bin_j)  # pairwise interactions

This script dumps the bin edges and per-bin scores so the model can be
re-evaluated in ~40 lines of Dart/Kotlin with no ML runtime. Optional — the
mobile app's default verdict comes from the deterministic rulebook.

Usage:
    python tools/export_ebm_to_json.py \
        --model legal_metrology_ml/data/ebm_model/compliance_ebm.pkl \
        --out   mobile/assets/models/compliance_ebm.json
"""
from __future__ import annotations

import argparse
import json
import pickle
from pathlib import Path

import numpy as np


def _to_list(x):
    if isinstance(x, np.ndarray):
        return x.tolist()
    if isinstance(x, (list, tuple)):
        return [_to_list(v) for v in x]
    if isinstance(x, (np.floating, np.integer)):
        return x.item()
    return x


def export(model_path: str, out_path: str) -> None:
    with open(model_path, "rb") as f:
        ebm = pickle.load(f)

    payload = {
        "format": "ebm-additive-v1",
        "feature_names": _to_list(getattr(ebm, "feature_names_in_", [])),
        "feature_types": _to_list(getattr(ebm, "feature_types_in_", [])),
        "intercept": _to_list(np.ravel(ebm.intercept_)),
        "term_features": _to_list(getattr(ebm, "term_features_", [])),
        "bins": _to_list(getattr(ebm, "bins_", [])),
        "term_scores": _to_list(getattr(ebm, "term_scores_", [])),
        "link": getattr(ebm, "link_", "logit"),
    }

    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    Path(out_path).write_text(json.dumps(payload, indent=2))
    print(f"Wrote {out_path} "
          f"({len(payload['feature_names'])} features, "
          f"{len(payload['term_features'])} terms)")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="legal_metrology_ml/data/ebm_model/compliance_ebm.pkl")
    ap.add_argument("--out", default="mobile/assets/models/compliance_ebm.json")
    a = ap.parse_args()
    export(a.model, a.out)
