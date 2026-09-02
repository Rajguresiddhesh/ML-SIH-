# Integrating the pipeline into `httpsaryxn/SIH_2026` (FreshLabel Pro)

Repo-specific algorithm. Read [`INTEGRATION.md`](INTEGRATION.md) first for the
generic package mechanics; this file gives the exact files, edits and mappings
for **that** app.

---

## 0. What the target app looks like today

```
SIH_2026/
  apps/mobile/          Flutter app "FreshLabel Pro"  (namespace com.sih2026.mobile)
    lib/
      core/services/camera_capture_service.dart   image_picker -> PendingCapture
      core/services/consumer_data_service.dart    createNewProductAndScan(), _evaluateCompliance()  <-- FAKE
      core/models/product_model.dart              ProductModel (compliance_status, compliance_issues)
      core/models/consumer_scan_model.dart        ConsumerScanModel (detected_declarations map)
      screens/consumer/consumer_scan_analysis_screen.dart   _startAnalysisPipeline()  <-- has a TODO
      screens/consumer/widgets/scanner_modal_sheet.dart     manual details + photo capture
      screens/regulator/regulator_scan_analysis_screen.dart  regulator equivalent
    pubspec.yaml        image_picker, supabase_flutter, google_fonts, path_provider, intl
    android/app/build.gradle.kts   minSdk = flutter.minSdkVersion (inherited)
  services/backend/     FastAPI STUB — only / and /health. No analysis endpoint.
  supabase/migrations/  products, consumer_scans, ... tables
```

**Current behaviour:** user types product name/brand/category/net-qty/MRP into
`ScannerModalSheet`, takes a photo → `ConsumerScanAnalysisScreen` plays a fake
progress bar → `ConsumerDataService.createNewProductAndScan()` runs a 2-rule
hardcoded `_evaluateCompliance()` and *invents* ingredients/nutrition → writes
`products` + `consumer_scans` rows in Supabase.

**Integration = replace the fake `_evaluateCompliance()` (and the invented
declarations) with the real pipeline**, keeping every model, table and screen
unchanged.

You have two places to run the pipeline. Pick one.

| | **A. On-device (Dart)** | **B. Backend (Python)** |
|---|---|---|
| Where | `apps/mobile` embeds this repo's `mobile/lib/src` as a package | `services/backend` embeds `legal_metrology_ml`, app calls it over HTTP |
| Offline | ✅ full audit offline | ❌ needs the server |
| OCR | Google ML Kit on device | EasyOCR on server |
| Ships in the APK | ✅ | ❌ (thin client) |
| Effort | medium | low (backend is already scaffolded, there is a `TODO` for it) |

`.apk` = the app, so the literal answer to "into the apk" is **A**. B is the
faster hackathon path and is documented at the end.

---

## Algorithm A — on-device

### A1. Vendor the compliance package

```bash
# from SIH_2026/
mkdir -p apps/mobile/packages/legal_metrology/lib/src
cp -r <ML-SIH->/mobile/lib/src/compliance  apps/mobile/packages/legal_metrology/lib/src/
cp -r <ML-SIH->/mobile/lib/src/data        apps/mobile/packages/legal_metrology/lib/src/
cp -r <ML-SIH->/mobile/lib/src/extraction  apps/mobile/packages/legal_metrology/lib/src/
cp -r <ML-SIH->/mobile/assets              apps/mobile/packages/legal_metrology/assets
```

Create `apps/mobile/packages/legal_metrology/pubspec.yaml`:

```yaml
name: legal_metrology
description: On-device LM(PC) Rules 2011 compliance audit.
version: 1.0.0
publish_to: "none"
environment:
  sdk: ^3.12.2                 # match apps/mobile/pubspec.yaml exactly
  flutter: ">=3.19.0"
dependencies:
  flutter: { sdk: flutter }
  http: ^1.2.2
  connectivity_plus: ^6.0.5
  google_mlkit_barcode_scanning: ^0.13.1
  google_mlkit_text_recognition: ^0.15.0
flutter:
  assets:
    - assets/fixtures/
```

Create `apps/mobile/packages/legal_metrology/lib/legal_metrology.dart` — the
barrel from `INTEGRATION.md` §1.3.

### A2. Add the dependency

`apps/mobile/pubspec.yaml` → `dependencies:` add:

```yaml
  legal_metrology:
    path: packages/legal_metrology
```

```bash
cd apps/mobile && flutter pub get
```

`image_picker` and `path_provider` are already there — no conflict. If
`pub get` complains about `http`/`connectivity_plus`, widen the ranges in the
package pubspec, not the app.

### A3. Android

`apps/mobile/android/app/build.gradle.kts` — force minSdk 21 (ML Kit floor):

```kotlin
    defaultConfig {
        applicationId = "com.sih2026.mobile"
        minSdk = maxOf(flutter.minSdkVersion, 21)   // was: flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
```

`apps/mobile/android/app/src/main/AndroidManifest.xml`:

* add next to the existing `INTERNET` permission:
  ```xml
  <uses-permission android:name="android.permission.CAMERA" />
  ```
* inside `<application>`, after the `flutterEmbedding` meta-data:
  ```xml
  <meta-data
      android:name="com.google.mlkit.vision.DEPENDENCIES"
      android:value="barcode,ocr,ocr_devanagari" />
  ```

If a release build ever sets `isMinifyEnabled = true`, add to
`proguard-rules.pro`: `-keep class com.google.mlkit.** { *; }`.

### A4. iOS

`apps/mobile/ios/Runner/Info.plist` — add:

```xml
<key>NSCameraUsageDescription</key><string>Scan packaging bar codes and labels.</string>
<key>NSPhotoLibraryUsageDescription</key><string>Pick a packaging photo to check.</string>
```

Podfile: `platform :ios, '12.0'` minimum.

### A5. New adapter service — `apps/mobile/lib/core/services/legal_metrology_service.dart`

This is the only new app file. It runs the pipeline on a `PendingCapture` and
returns objects in the app's existing shapes.

```dart
import 'package:legal_metrology/legal_metrology.dart';
import '../models/pending_capture.dart';

class LmAuditResult {
  final String complianceStatus;                 // compliant|warning|potential_violation|unverified
  final List<Map<String, dynamic>> complianceIssues;
  final Map<String, dynamic> detectedDeclarations;
  final ComplianceReport report;                  // full detail for a rich results screen
  LmAuditResult(this.complianceStatus, this.complianceIssues,
      this.detectedDeclarations, this.report);
}

class LegalMetrologyService {
  static final _ocr = LabelOcrService();
  static final _bc = BarcodeScannerService();

  /// Audit a captured label photo. Uses on-device OCR + bar code + the
  /// manually-entered fields from ScannerModalSheet as seeds.
  static Future<LmAuditResult> auditCapture({
    required PendingCapture capture,
    String? productName,
    String? brand,
    String? netQuantity,
    double? mrp,
    String? gs1IndiaKey,
  }) async {
    final path = capture.localPath;

    // 1. On-device OCR -> declarations
    final ocr = await _ocr.recognise(path);
    final parsed = parseOcr(ocr);
    final pkg = toPackageData(parsed);

    // 2. seed with the user's typed fields when OCR missed them
    pkg.commodityName ??= productName;
    if (pkg.mrpValue == null && mrp != null) pkg.mrpValue = mrp;
    if (pkg.netQuantityValue == null && netQuantity != null) {
      final q = parseQuantity(netQuantity);
      pkg..netQuantityValue = q.value..netQuantityUnit = q.unit;
    }

    // 3. bar code on the same photo (optional)
    final codes = await _bc.scanFile(path);
    final barcode = codes.isNotEmpty ? codes.first.value : null;

    // 4. run the rulebook (adds B01–B06 + registry enrichment when online)
    final report = await runLabelAudit(
      pkg,
      barcode: barcode,
      lookupConfig: LookupConfig(gs1IndiaKey: gs1IndiaKey),
    );

    return LmAuditResult(
      _status(report),
      _issues(report),
      _declarations(report),
      report,
    );
  }

  /// Bar-code-only path (if you add a scanner button later).
  static Future<LmAuditResult> auditBarcode(String code, {String? gs1IndiaKey}) async {
    final report = await runBarcodeAudit(code,
        lookupConfig: LookupConfig(gs1IndiaKey: gs1IndiaKey));
    return LmAuditResult(_status(report), _issues(report), _declarations(report), report);
  }

  // ---- mapping to the app's vocabulary ----
  static String _status(ComplianceReport r) {
    if (r.score.criticalFailures > 0) return 'potential_violation';
    if (r.diff.failed.isNotEmpty) return 'warning';
    if (r.diff.inconclusive.any((x) => x.severity == 'CRITICAL' || x.severity == 'MAJOR')) {
      return 'unverified';
    }
    if (r.diff.warnings.isNotEmpty) return 'warning';
    return 'compliant';
  }

  static String _sev(String s) => switch (s) {
        'CRITICAL' => 'potential_violation',
        'MAJOR' => 'warning',
        _ => 'warning',
      };

  static List<Map<String, dynamic>> _issues(ComplianceReport r) => [
        for (final x in r.diff.failed)
          {'type': x.ruleName, 'severity': _sev(x.severity), 'message': x.detail,
           'rule_id': x.ruleId, 'legal_reference': x.legalReference},
        for (final x in r.diff.warnings)
          {'type': x.ruleName, 'severity': 'warning', 'message': x.detail,
           'rule_id': x.ruleId, 'legal_reference': x.legalReference},
        for (final x in r.diff.inconclusive.where(
            (x) => x.severity == 'CRITICAL' || x.severity == 'MAJOR'))
          {'type': x.ruleName, 'severity': 'unverified', 'message': x.detail,
           'rule_id': x.ruleId, 'legal_reference': x.legalReference},
      ];

  static Map<String, dynamic> _declarations(ComplianceReport r) {
    final p = r.packageData;
    return {
      'commodity_name': p.commodityName,
      'manufacturer': p.manufacturerName,
      'manufacturer_address': p.manufacturerAddress,
      'net_quantity': p.netQuantityValue == null
          ? null
          : '${p.netQuantityValue} ${p.netQuantityUnit ?? ''}'.trim(),
      'mrp': p.mrpValue,
      'mrp_inclusive_of_taxes': p.mrpIncludesTax,
      'mfg_date': p.manufactureDate,
      'best_before': p.bestBefore,
      'country_of_origin': p.countryOfOrigin,
      'fssai_license_no': p.fssaiLicenseNumber,
      'consumer_care_info': [p.consumerCarePhone, p.consumerCareEmail]
          .where((e) => e != null).join(' | '),
      'barcode': {
        'value': p.barcodeValue,
        'gtin_format': p.barcodeGtinFormat,
        'checksum_valid': p.barcodeChecksumValid,
        'gs1_india': p.barcodeIsGs1India,
        'restricted': p.barcodeIsRestricted,
        'issuing_country': p.barcodeIssuingCountry,
      },
      'identified_in': p.productDataSources,
      'score_pct': (r.score.finalScore * 100).round(),
      'star_rating': r.score.starRating,
      'star_label': r.score.starLabel,
      'recommendations': r.recommendations,
    };
  }
}
```

### A6. Wire it into the consumer flow — 2 edits

**Edit 1 — `lib/core/services/consumer_data_service.dart`**

`createNewProductAndScan(...)` currently calls the private
`_evaluateCompliance(...)` and `_generateIngredientsFor/_generateNutritionFor`.
Give it an optional pre-computed result and use that when present:

```dart
static Future<ConsumerScanModel?> createNewProductAndScan({
  required String productName,
  ...
  LmAuditResult? audit,          // <-- NEW
}) async {
  ...
  final compliance = audit != null
      ? _ComplianceResult(status: audit.complianceStatus, issues: audit.complianceIssues)
      : _evaluateCompliance(netQuantity: resolvedNetQty, mrp: resolvedMrp, productName: trimmedName);

  // real declarations instead of the invented ones
  final detected = audit?.detectedDeclarations ?? { /* existing map */ };
  // use `detected` where the method builds 'detected_declarations'
  ...
  // pull real values back onto the product row when the audit found them
  final realMfr  = audit?.report.packageData.manufacturerName ?? manufacturerName;
  final realFssai = audit?.report.packageData.fssaiLicenseNumber;
  ...
}
```

Keep the Supabase insert exactly as-is — `compliance_status`,
`compliance_issues`, `detected_declarations` already accept these shapes.

**Edit 2 — `lib/screens/consumer/consumer_scan_analysis_screen.dart`**

In `_startAnalysisPipeline()`, replace the `// TODO: send PendingCapture to
FastAPI backend` block with the real call and drive the existing progress bar
off its real phases:

```dart
Future<void> _startAnalysisPipeline() async {
  try {
    _progressController.forward();                 // keep the animation

    setState(() { _currentStageIndex = 1;
      _statusMessage = 'Reading label with on-device OCR...'; });
    final audit = await LegalMetrologyService.auditCapture(
      capture: widget.pendingCapture,
      productName: widget.prefilledProductName,
      brand: widget.prefilledBrand,
      netQuantity: widget.prefilledNetQty,
      mrp: widget.prefilledMrp,
      gs1IndiaKey: /* from settings/env, or null */ null,
    );

    setState(() { _currentStageIndex = 2;
      _statusMessage = 'Verifying LM(PC) Rules 2011 declarations...'; });

    final createdScan = await ConsumerDataService.createNewProductAndScan(
      productName: audit.report.packageData.commodityName
          ?? widget.prefilledProductName ?? 'Packaged Food Product',
      brand: widget.prefilledBrand,
      category: widget.prefilledCategory,
      netQuantity: widget.prefilledNetQty,
      mrp: widget.prefilledMrp,
      pendingCapture: widget.pendingCapture,
      imageUrl: widget.pendingCapture.localPath,
      audit: audit,                                // <-- pass it through
    );

    await _progressController.forward(from: _progressController.value);
    if (!mounted) return;
    setState(() {
      _completedScan = createdScan;
      _isAnalysisFinished = true;
      _statusMessage = 'Analysis complete — ${audit.detectedDeclarations['score_pct']}% '
          '(${audit.detectedDeclarations['star_label']}).';
    });
    if (createdScan != null) widget.onScanCompleted?.call(createdScan);
  } catch (e) {
    if (mounted) setState(() { _hasError = true; _errorMessage = 'Analysis failed: $e'; });
  }
}
```

No other screen changes are required — `ProductSummaryModal`,
`recent_scans_section`, `product_summary_modal` all read from
`ConsumerScanModel` / `detected_declarations` which now carry real data.

### A7. Regulator flow (same shape)

`lib/screens/regulator/regulator_scan_analysis_screen.dart` +
`lib/core/services/regulator_data_service.dart` mirror the consumer pair. Apply
the identical two edits there; `regulator_declaration_card.dart` and
`regulator_violation_review_screen.dart` render `compliance_issues` unchanged.
For the regulator, prefer `runBarcodeAudit` when a GTIN is present (stricter,
cites GS1) and surface `report.diff.failed` as violations.

### A8. Optional — richer results screen

The full `ComplianceReport` is on `audit.report`. Copy
`<ML-SIH->/mobile/lib/src/ui/result_page.dart` into the app and push it from the
"View details" action to show per-rule PASS/FAIL/INCONCLUSIVE with legal
references and the bar-code/GS1 card.

### A9. Build & verify

```bash
cd apps/mobile
flutter clean && flutter pub get
flutter analyze
flutter test packages/legal_metrology          # Python<->Dart rulebook parity
flutter build apk --release                     # build/app/outputs/flutter-apk/app-release.apk
```

Device smoke test: capture a real Indian FMCG label with Wi-Fi on → declarations
resolve, score > 60%. Capture a label with `MRP` but no "inclusive of all
taxes" → `R06_MRP_TAX` shows as a warning issue. Type GTIN `9781234567897`
through a bar-code path → `B03_GTIN_SCOPE` failure.

---

## Algorithm B — backend (fills the existing `TODO`)

The app already expects this (`consumer_scan_analysis_screen.dart` has the
commented `BackendApiService.analyzeConsumerLabel(...)` call).

### B1. Vendor the Python pipeline

```bash
# from SIH_2026/
cp -r <SIH2026-backend>/legal_metrology_ml services/backend/legal_metrology_ml
```

Add to `services/backend/pyproject.toml` deps: `easyocr`, `opencv-python`,
`pydantic`, `pandas`, `interpret`, `fpdf2`, `pyzbar`, `requests`
(mirror `requirements.txt` from the backend repo).

### B2. Add the endpoint — `services/backend/app/main.py`

```python
import tempfile, uuid
from pathlib import Path
from fastapi import UploadFile, File, Form, Header

from legal_metrology_ml.main import run_pipeline

@app.post("/consumer/analyze", tags=["Compliance"])
async def analyze_label(
    image: UploadFile | None = File(default=None),
    barcode_number: str | None = Form(default=None),
    net_quantity: str | None = Form(default=None),
    mrp: float | None = Form(default=None),
    x_gemini_api_key: str | None = Header(default=None),
):
    front = None
    if image is not None:
        front = Path(tempfile.gettempdir()) / f"{uuid.uuid4().hex}.jpg"
        front.write_bytes(await image.read())
    report = run_pipeline(
        front_image=str(front) if front else None,
        barcode_number=barcode_number,
        output_path=None,
        api_key=x_gemini_api_key,
    )
    s = report.compliance_score
    return {
        "compliance_status": (
            "potential_violation" if s.critical_failures
            else "warning" if s.failed_rules else "compliant"
        ),
        "score_pct": round(s.final_score * 100, 1),
        "star_label": s.star_label,
        "compliance_issues": [
            {"type": r.rule_name, "severity": r.severity, "message": r.detail}
            for r in report.rulebook_diff.failed + report.rulebook_diff.warnings
        ],
        "detected_declarations": report.package_data.model_dump(),
        "recommendations": report.recommendations,
    }
```

(This is essentially the Flask `app.py` `/analyze` logic in FastAPI form.)

### B3. Wire the app

Add `http` to `apps/mobile/pubspec.yaml`, create
`lib/core/services/backend_api_service.dart` with
`analyzeConsumerLabel({fileBytes, fileName, fields})` doing a
`MultipartRequest` to `<backend>/consumer/analyze`, then in
`_startAnalysisPipeline()` uncomment the TODO block and pass the JSON into
`ConsumerDataService.createNewProductAndScan(audit: ...)` exactly as in A6.

### B4. Trade-off

Backend keeps the APK tiny and OCR quality high (EasyOCR), but every scan needs
the server reachable. A common hybrid: **A** as the offline default, **B**
as an opportunistic "re-verify on server" when online.

---

## Data-flow (Algorithm A)

```
ScannerModalSheet (name/brand/qty/MRP + photo)
        │  PendingCapture(localPath)
        ▼
ConsumerScanAnalysisScreen._startAnalysisPipeline
        │
        ▼
LegalMetrologyService.auditCapture
   ├─ LabelOcrService (ML Kit, offline)      ─┐
   ├─ BarcodeScannerService (ML Kit, offline) ├─► PackageData
   ├─ parseOcr / toPackageData                ─┘
   ├─ lookupProduct  (OFF / GS1 India — only if online)
   └─ evaluate + evaluateBarcodeRules + scoreDiff   ► ComplianceReport
        │  map -> {compliance_status, compliance_issues, detected_declarations}
        ▼
ConsumerDataService.createNewProductAndScan(audit: …)
        │
        ▼
Supabase  products + consumer_scans   (unchanged schema)
        ▼
ProductSummaryModal / recent scans / regulator dashboards
```
