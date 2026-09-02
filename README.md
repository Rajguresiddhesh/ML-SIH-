# ML-SIH — On-device Legal Metrology compliance (Flutter)

Offline-first mobile port of the [`legal_metrology_ml`](https://github.com/Rajguresiddhesh/SIH2026)
pipeline — **Legal Metrology (Packaged Commodities) Rules, 2011** compliance
from a bar code or a label photo, on device.

| Folder | Contents |
|---|---|
| [`mobile/`](mobile/) | The Flutter app. Pure-Dart rulebook (Rule 6 + `B01`–`B06`), GTIN/GS1 validation, deterministic scoring — all offline. Bar-code decode and Latin+Devanagari OCR via Google ML Kit. Product-registry / GS1 India enrichment only when online. |
| [`tools/`](tools/) | Python export helpers, run against the backend repo: YOLO→TFLite, EBM→JSON, and `gen_dart_fixtures.py` which produces the parity-test data in `mobile/assets/fixtures/`. |

## Why there is no single `.tflite`

The pipeline is heterogeneous:

- **Rulebook + GTIN/GS1 validation** — deterministic code, ported to Dart. No model.
- **EBM** (`interpret`) — an *additive* model, not a neural net. Exported to JSON
  (`tools/export_ebm_to_json.py`); optional second opinion only.
- **YOLOv8 symbol detector** — the one genuine TFLite conversion
  (`tools/export_yolo_tflite.py`), needs trained weights.
- **OCR / barcode** — Google ML Kit on-device models.
- **LLM / registry lookups** — remote, online-optional.

## Integrating into an existing Flutter app

- **[INTEGRATION.md](INTEGRATION.md)** — generic procedure: add this pipeline to
  any existing Flutter project (as a local package) and rebuild the APK, with
  the Android/iOS platform config and call sites.
- **[INTEGRATION_SIH2026.md](INTEGRATION_SIH2026.md)** — the same, specialised
  for `httpsaryxn/SIH_2026` (FreshLabel Pro): exact file edits, the
  `ComplianceReport → ProductModel / ConsumerScanModel` mapping, and a
  backend-side alternative that fills that repo's existing `TODO`.

## Quick start (standalone)

```bash
cd mobile
flutter create .        # generates android/ ios/ around the existing lib/
flutter pub get
flutter test            # runs the Python↔Dart rulebook parity test
flutter run
```

See [`mobile/README.md`](mobile/README.md) for the Android/iOS platform tweaks
(minSdk 21, ML Kit `DEPENDENCIES` meta-data, camera permissions).

## Regenerating the parity fixtures / model assets

`tools/` needs the backend repo checked out next to this one:

```
some-dir/
  SIH2026/          # the Python backend
  ML-SIH-/          # this repo
```

```bash
cd ML-SIH-
python tools/gen_dart_fixtures.py     # PYTHONPATH picks up ../SIH2026 automatically? no:
PYTHONPATH=../SIH2026 python tools/gen_dart_fixtures.py
```
