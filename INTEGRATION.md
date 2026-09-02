# Integrating the Legal Metrology compliance pipeline into an existing Flutter app

You cannot modify a built `.apk`. You add this code to the **source** of the
existing Flutter project and produce a new APK. Below is the exact procedure.

---

## Phase 0 — Prerequisites

1. You have the existing app's **Flutter project source** (a folder with
   `pubspec.yaml`, `lib/`, `android/`, `ios/`). If you only have the `.apk`,
   stop — get the source from whoever built it.
2. Flutter SDK `>= 3.19` and the same Dart 3 SDK installed
   (`flutter --version`).
3. The existing app builds today: `flutter pub get && flutter build apk`
   succeeds **before** you change anything. Fix that first.
4. Decide the integration mode:
   - **Mode A (package by path)** — recommended, isolated. Used below.
   - **Mode B (copy folders)** — faster, but mixes into the app's `lib/`.

Notation: `APP/` = the existing project root, `PKG/` = this repo's `mobile/`.

---

## Phase 1 — Bring the compliance code in as a local package

### 1.1  Create the package folder

```
APP/
  packages/
    legal_metrology/
      pubspec.yaml
      lib/
        legal_metrology.dart          # public API barrel (new, see 1.3)
        src/
          compliance/                 # copied from PKG/lib/src/compliance/
          data/                       # copied from PKG/lib/src/data/
          extraction/                 # copied from PKG/lib/src/extraction/  (skip if APP already scans/OCRs)
```

```bash
cd APP
mkdir -p packages/legal_metrology/lib/src
cp -r <this-repo>/mobile/lib/src/compliance packages/legal_metrology/lib/src/
cp -r <this-repo>/mobile/lib/src/data       packages/legal_metrology/lib/src/
cp -r <this-repo>/mobile/lib/src/extraction packages/legal_metrology/lib/src/   # optional
cp -r <this-repo>/mobile/assets             packages/legal_metrology/assets     # fixtures + model READMEs
```

### 1.2  `packages/legal_metrology/pubspec.yaml`

```yaml
name: legal_metrology
description: On-device Legal Metrology (Packaged Commodities) Rules 2011 audit.
version: 1.0.0
publish_to: "none"

environment:
  sdk: ">=3.3.0 <4.0.0"
  flutter: ">=3.19.0"

dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.2
  connectivity_plus: ^6.0.5
  # Only if you copied src/extraction/ (i.e. you want this package to scan/OCR):
  google_mlkit_barcode_scanning: ^0.13.1
  google_mlkit_text_recognition: ^0.15.0

flutter:
  assets:
    - assets/fixtures/
```

If you did **not** copy `src/extraction/`, also delete
`packages/legal_metrology/lib/src/extraction/` and drop the two `google_mlkit_*`
lines.

### 1.3  `packages/legal_metrology/lib/legal_metrology.dart` (public API barrel)

Create this file so the app imports one thing:

```dart
/// Public API for the on-device Legal Metrology compliance audit.
library legal_metrology;

export 'src/compliance/models.dart'
    show PackageData, RuleResult, ComplianceDiff, ComplianceScore,
         ComplianceReport, AnalysisSource, QuantityCategory, PackageType;
export 'src/compliance/gs1.dart' show classifyGtin, GtinInfo, validateGtin;
export 'src/compliance/audit.dart'
    show runBarcodeAudit, runLabelAudit, packageFromRecord;
export 'src/compliance/rulebook_engine.dart'
    show evaluate, scoreDiff, generateRecommendations, starRating;
export 'src/data/product_lookup.dart' show lookupProduct, LookupConfig;
export 'src/data/product_record.dart' show ProductRecord;

// Only if src/extraction/ was copied:
export 'src/extraction/barcode_scanner.dart' show BarcodeScannerService, ScannedBarcode;
export 'src/extraction/label_ocr.dart' show LabelOcrService, OcrResult;
export 'src/extraction/text_parser.dart' show parseOcr, toPackageData, ParsedDeclarations;
```

### 1.4  Fix the fixture path (only if you run the parity test)

`test/rulebook_parity_test.dart` reads `assets/fixtures/rulebook_cases.json`
relative to the package root. Copy that test file into
`packages/legal_metrology/test/` and it works as-is.

---

## Phase 2 — Wire the package into the app

### 2.1  `APP/pubspec.yaml` — add the dependency

```yaml
dependencies:
  legal_metrology:
    path: packages/legal_metrology
```

(Or, without a local copy: `git: { url: <this-repo-url>, path: packages/legal_metrology }`.)

### 2.2  Resolve

```bash
cd APP
flutter pub get
```

If `pub get` reports a version conflict on `http`, `connectivity_plus`, or the
`google_mlkit_*` packages, align the version ranges in **both** pubspecs to a
range that satisfies the app's existing constraints (widen the package's
ranges rather than pinning the app's).

---

## Phase 3 — Platform configuration

Do this **only for capabilities you actually use**.

### 3.1  Android — `APP/android/app/build.gradle`

ML Kit and `connectivity_plus` need API 21+:

```gradle
android {
    defaultConfig {
        minSdkVersion 21          // raise if lower; leave if already >= 21
    }
}
```

### 3.2  Android — `APP/android/app/src/main/AndroidManifest.xml`

Permissions (inside `<manifest>`, outside `<application>`):

```xml
<uses-permission android:name="android.permission.INTERNET" />        <!-- optional online enrichment -->
<uses-permission android:name="android.permission.CAMERA" />          <!-- only if this package scans/OCRs -->
```

ML Kit model bundling (inside `<application>`, only if `src/extraction/` copied):

```xml
<meta-data
    android:name="com.google.mlkit.vision.DEPENDENCIES"
    android:value="barcode,ocr,ocr_devanagari" />
```

### 3.3  iOS — `APP/ios/Runner/Info.plist`

Only if this package scans/OCRs and the app didn't already declare these:

```xml
<key>NSCameraUsageDescription</key>
<string>Scan product bar codes and label photos for compliance checks.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Pick a label or bar code photo for compliance checks.</string>
```

`APP/ios/Podfile`: `platform :ios, '12.0'` or higher.

### 3.4  Android release build — ProGuard/R8

If the app uses `minifyEnabled true`, add to `APP/android/app/proguard-rules.pro`:

```
-keep class com.google.mlkit.** { *; }
-keep class com.google_mlkit_commons.** { *; }
```

---

## Phase 4 — Call the pipeline from the app's UI

### 4.1  If the existing app ALREADY has a bar-code scanner

You only need the pure-Dart core. After the app decodes a bar code to a string:

```dart
import 'package:legal_metrology/legal_metrology.dart';

Future<void> onBarcodeDecoded(String code) async {
  final report = await runBarcodeAudit(
    code,
    // optional: licensed GS1 India key from your settings store
    lookupConfig: LookupConfig(gs1IndiaKey: myGs1Key),
  );

  // Everything you need is on `report`:
  final pct   = (report.score.finalScore * 100).round();   // 0..100
  final stars = report.score.starRating;                    // 1..5
  final label = report.score.starLabel;
  final failed        = report.diff.failed;         // List<RuleResult>
  final warnings      = report.diff.warnings;
  final inconclusive  = report.diff.inconclusive;   // "verify on the pack"
  final passed        = report.diff.passed;
  final recs          = report.recommendations;     // List<String>
  final gtinValid     = report.packageData.barcodeValid;
  final gs1India      = report.packageData.barcodeIsGs1India;
  final identifiedIn  = report.packageData.productDataSources; // registries that matched
}
```

`runBarcodeAudit` never throws for network reasons — offline it returns the
GTIN-structure verdict with mandatory declarations marked `INCONCLUSIVE`.

### 4.2  If you also want on-device label OCR

```dart
import 'package:legal_metrology/legal_metrology.dart';

Future<ComplianceReport> auditLabelPhoto(String imagePath) async {
  final ocr    = await LabelOcrService().recognise(imagePath);   // ML Kit, offline
  final parsed = parseOcr(ocr);
  final pkg    = toPackageData(parsed);

  // opportunistically read a bar code from the same photo
  final codes  = await BarcodeScannerService().scanFile(imagePath);
  final barcode = codes.isNotEmpty ? codes.first.value : null;

  return runLabelAudit(pkg, barcode: barcode);
}
```

### 4.3  Rendering

Group `report.diff` into sections (`failed` / `warnings` / `inconclusive` /
`passed` / `notApplicable`). Each `RuleResult` has `ruleId`, `ruleName`,
`severity`, `detail`, `legalReference`. See
`mobile/lib/src/ui/result_page.dart` in this repo for a ready-made widget you
can copy.

---

## Phase 5 — (Optional) add the TFLite / EBM assets

The audit works without these. Add them only for the symbol detector or an EBM
second opinion.

1. Produce the files against the SIH2026 backend:
   ```bash
   python tools/export_yolo_tflite.py --weights best.pt   # -> symbol_detector.tflite
   python tools/export_ebm_to_json.py                      # -> compliance_ebm.json
   ```
2. Put them in `APP/packages/legal_metrology/assets/models/` and declare them in
   the package's `pubspec.yaml` under `flutter: assets:`.
3. Add `tflite_flutter: ^0.11.0` to the package deps and write a loader
   (`Interpreter.fromAsset('packages/legal_metrology/assets/models/symbol_detector.tflite')`).
   *(Not included in this repo — the deterministic rulebook is the verdict.)*

---

## Phase 6 — Build and verify the new APK

```bash
cd APP
flutter clean
flutter pub get
flutter test packages/legal_metrology            # rulebook parity (Python <-> Dart)
flutter analyze
flutter build apk --release                      # -> build/app/outputs/flutter-apk/app-release.apk
```

Smoke test on a device:

1. `8901030928239` → GS1 India (890), valid GTIN, INCONCLUSIVE declarations if
   offline / not in a registry.
2. `9781234567897` → `B03_GTIN_SCOPE` FAIL (Bookland prefix — not a product).
3. `8901234567895` → `B02_GTIN_CHECKSUM` FAIL (bad check digit).
4. A real Indian FMCG bar code with network on → declarations resolve from
   Open Food Facts / GS1 India, score rises.

---

## Phase 7 — Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `pub get` version solving failed | Widen the version ranges in `packages/legal_metrology/pubspec.yaml` to match the app's existing `http` / `connectivity_plus` / ML Kit constraints. |
| `MissingPluginException` at runtime | You added a plugin dep to the **package** but never ran `flutter pub get` at the **app** root, or the app needs a full rebuild (`flutter clean`). |
| Build fails: `minSdkVersion 19 cannot be smaller than 21` | Raise `minSdkVersion` to 21 in `APP/android/app/build.gradle` (Phase 3.1). |
| ML Kit OCR returns empty on device | Devanagari model still downloading; the code already falls back to Latin-only. Add the `DEPENDENCIES` meta-data (Phase 3.2) so it bundles at install. |
| Release APK crashes on ML Kit, debug is fine | Add the ProGuard keep rules (Phase 3.4). |
| Every declaration is INCONCLUSIVE | Expected for a bar-code-only audit with no network / unknown GTIN — that's the honest verdict. Provide a GS1 India key or capture a label photo (`runLabelAudit`). |
| `runBarcodeAudit` hangs ~12 s | The registry lookups' overall deadline. Happens on a flaky network; it returns partial results. Call it off the UI thread (it already is a `Future`). |

---

## Minimal-footprint variant

If the app already scans bar codes and you want the **smallest** change:

1. Copy only `packages/legal_metrology/lib/src/compliance/` and
   `.../src/data/` (no `extraction/`).
2. Package deps: just `http` and `connectivity_plus`.
3. No Android/iOS changes except `INTERNET` permission (and only if you want the
   online enrichment; drop `connectivity_plus` + the `lookupProduct` call for a
   100% offline, zero-permission integration — the GTIN structural audit and the
   full Rule 6 checklist still run).
4. One call site: `runBarcodeAudit(decodedString)`.
