# Legal Metrology Checker — Flutter (offline-first)

On-device port of the [`legal_metrology_ml`](../legal_metrology_ml) pipeline for
**Legal Metrology (Packaged Commodities) Rules, 2011** compliance.

## What runs where

| Concern | Backend (Python) | Mobile (this app) |
|---|---|---|
| **Rulebook** (Rule 6 declarations, B01–B06) | `layer4_rulebook_engine` | `lib/src/compliance/` — pure Dart port, **fully offline** |
| **GTIN / GS1 validation** | `layer1_feature_extraction/gs1.py` | `lib/src/compliance/gs1.dart` — pure Dart, offline |
| **Scoring** | `run_barcode_pipeline` | `lib/src/compliance/rulebook_engine.dart` |
| **Bar code decode** | pyzbar / OpenCV | Google **ML Kit Barcode Scanning** (on-device) |
| **Label OCR** | EasyOCR (PyTorch) | Google **ML Kit Text Recognition** — Latin + Devanagari (on-device) |
| **Symbol detection** | Ultralytics YOLO | *optional* `assets/models/symbol_detector.tflite` (see `tools/export_yolo_tflite.py`) |
| **EBM second opinion** | `interpret` EBM | *optional* `assets/models/compliance_ebm.json` (see `tools/export_ebm_to_json.py`) — **not** a TFLite model; it is an additive model exported as JSON |
| **Product registry lookup** | `data_sources/product_lookup.py` | `lib/src/data/product_lookup.dart` — Open Food Facts / UPCItemDB / Wikidata / GS1 India, **only when online** |
| **Gemini LLM** | `llm/` | not ported (remote API) |

The deterministic rulebook is always the verdict. Online sources and the
optional models only *enrich* it.

## Setup

```bash
cd mobile
flutter create .            # generates android/ ios/ etc. around this lib/
flutter pub get
flutter run
```

`flutter create .` will not overwrite `lib/`, `pubspec.yaml`, `test/` or
`assets/`. After it runs, apply the platform tweaks below.

### Android

`android/app/build.gradle` — ML Kit needs API 21+:

```gradle
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

`android/app/src/main/AndroidManifest.xml` — inside `<application>`, so ML Kit
models download on install:

```xml
<meta-data
    android:name="com.google.mlkit.vision.DEPENDENCIES"
    android:value="barcode,ocr,ocr_devanagari" />
```

Camera + internet permissions (internet is only used for optional enrichment):

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
```

### iOS

`ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key><string>Scan bar codes and label photos</string>
<key>NSPhotoLibraryUsageDescription</key><string>Pick a label or bar code photo</string>
```

Podfile platform `>= 12.0`.

## Generating the optional model assets

From the repository root, in the Python environment:

```bash
python tools/export_ebm_to_json.py       # -> mobile/assets/models/compliance_ebm.json
python tools/export_yolo_tflite.py --weights best.pt   # -> mobile/assets/models/symbol_detector.tflite
python tools/gen_dart_fixtures.py         # -> mobile/assets/fixtures/rulebook_cases.json (parity test data)
```

## Tests

```bash
flutter test              # includes the Python↔Dart rulebook parity test
```

`test/rulebook_parity_test.dart` replays `assets/fixtures/rulebook_cases.json`
(produced by the backend) through the Dart rulebook and asserts every ported
rule agrees with the Python verdict.

## Settings

The gear icon stores an optional **GS1 India / DataKart** API key
(`SharedPreferences`). Without it the free registries are used; the audit still
works entirely offline from the GTIN structure.
