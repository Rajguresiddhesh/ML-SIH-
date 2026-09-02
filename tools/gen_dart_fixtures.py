"""Generate rulebook parity fixtures.

Runs the Python rulebook on a set of synthetic packages and dumps the verdicts
to JSON. The Flutter app loads the same JSON in `test/rulebook_parity_test.dart`
to prove the Dart port matches the backend.

Usage:
    python tools/gen_dart_fixtures.py
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

# The Python backend (`legal_metrology_ml`) lives in the SIH2026 repo. Locate it
# via LM_BACKEND, a sibling checkout, or this repo root.
_here = Path(__file__).resolve().parents[1]
for _cand in [os.environ.get("LM_BACKEND"), _here / ".." / "SIH2026",
              _here / ".." / "Sheet", _here]:
    if _cand and (Path(_cand) / "legal_metrology_ml").is_dir():
        sys.path.insert(0, str(Path(_cand).resolve()))
        break

from legal_metrology_ml.layer1_feature_extraction.gs1 import classify_gtin
from legal_metrology_ml.layer2_data_normalization.normalizer import DataNormalizer
from legal_metrology_ml.layer4_rulebook_engine.barcode_rules import evaluate_barcode_rules
from legal_metrology_ml.layer4_rulebook_engine.engine import RulebookEngine
from legal_metrology_ml.data_sources.product_lookup import ProductRecord

OUT = Path("mobile/assets/fixtures/rulebook_cases.json")

CASES = [
    {
        "name": "well-identified Indian FMCG",
        "gtin": "8901030928239",
        "record": dict(
            product_name="Lux Soap", brand="Lux",
            manufacturer_name="Hindustan Unilever Ltd",
            manufacturer_address="Mumbai 400099, Maharashtra, India",
            net_quantity_raw="100 g", net_quantity_value=100.0, net_quantity_unit="g",
            country_of_origin="India", mrp_value=45.0, manufacture_date="08/2025",
            consumer_care_email="care@hul.com", consumer_care_phone="18001022221",
            fssai_license="10012345678901", sources=["gs1_india_datakart"],
        ),
    },
    {
        "name": "partial registry data",
        "gtin": "8901030928239",
        "record": dict(
            product_name="Lux Soap", brand="Lux", manufacturer_name="HUL Ltd",
            manufacturer_address="Mumbai 400099, MH, India",
            net_quantity_raw="100 g", net_quantity_value=100.0, net_quantity_unit="g",
            country_of_origin="India", sources=["open_food_facts"],
        ),
    },
    {
        "name": "unknown bookland prefix",
        "gtin": "9781234567897",
        "record": dict(sources=[]),
    },
    {
        "name": "bad check digit",
        "gtin": "8901234567895",
        "record": dict(sources=[]),
    },
]


def verdicts(gtin: str, rec_kwargs: dict) -> dict:
    gi = classify_gtin(gtin)
    rec = ProductRecord(gtin=gtin, **{k: v for k, v in rec_kwargs.items()})
    pkg = DataNormalizer().from_product_record(rec, gi)
    diff = RulebookEngine().evaluate(pkg, extra_results=evaluate_barcode_rules(pkg, gi))
    return {
        r.rule_id: r.status
        for bucket in (diff.passed, diff.failed, diff.warnings, diff.not_applicable, diff.inconclusive)
        for r in bucket
    }


def main() -> None:
    out = []
    for case in CASES:
        out.append({
            "name": case["name"],
            "gtin": case["gtin"],
            "record": case["record"],
            "expected": verdicts(case["gtin"], case["record"]),
        })
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, indent=2))
    print(f"Wrote {OUT} ({len(out)} cases)")


if __name__ == "__main__":
    main()
