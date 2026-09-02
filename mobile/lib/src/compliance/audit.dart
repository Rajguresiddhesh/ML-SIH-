/// Orchestration — mirrors `legal_metrology_ml/main.py::run_barcode_pipeline`
/// and the local-OCR path, on-device.
library;

import '../data/product_lookup.dart';
import '../data/product_record.dart';
import 'barcode_rules.dart';
import 'gs1.dart';
import 'models.dart';
import 'rulebook_engine.dart';

/// Build [PackageData] from a registry [ProductRecord] + GTIN facts
/// (Dart port of `DataNormalizer.from_product_record`).
PackageData packageFromRecord(ProductRecord rec, GtinInfo gtin) {
  final p = PackageData()
    ..analysisSource = AnalysisSource.barcodeRegistry
    ..commodityName = rec.productName
    ..manufacturerName = rec.manufacturerName
    ..manufacturerAddress = rec.manufacturerAddress
    ..packerName = rec.packerName
    ..importerName = rec.importerName
    ..importerAddress = rec.importerAddress
    ..countryOfOrigin = rec.countryOfOrigin
    ..mrpValue = rec.mrpValue
    ..mrpCurrency = rec.mrpCurrency
    ..mrpIncludesTax = null
    ..manufactureDate = rec.manufactureDate
    ..bestBefore = rec.bestBefore
    ..consumerCarePhone = rec.consumerCarePhone
    ..consumerCareEmail = rec.consumerCareEmail
    ..consumerCareAddress = rec.consumerCare
    ..fssaiLicenseNumber = rec.fssaiLicense
    ..hasVegNonVegSymbol = rec.vegNonVeg == 'VEG' || rec.vegNonVeg == 'NON_VEG'
    ..hasBarcode = true
    ..barcodeValue = rec.gtin
    ..barcodeType = gtin.format
    ..barcodeGtinFormat = gtin.format
    ..barcodeChecksumValid = gtin.checksumValid
    ..barcodeValid = gtin.isValid
    ..barcodeIssuingCountry = gtin.issuingCountry
    ..barcodeIsGs1India = gtin.isGs1India
    ..barcodeIsRestricted = gtin.isRestricted
    ..barcodeRegisteredOwner = rec.brand ?? rec.manufacturerName
    ..productDataSources = List.of(rec.sources)
    ..dataProvenance = Map.of(rec.fieldSources)
    ..productIdentified = rec.found;

  if (rec.netQuantityValue != null) {
    p.netQuantityValue = rec.netQuantityValue;
    p.netQuantityUnit = rec.netQuantityUnit;
    p.netQuantityCategory = switch (rec.netQuantityUnit) {
      'g' || 'kg' || 'mg' => QuantityCategory.weight,
      'ml' || 'l' || 'cl' => QuantityCategory.volume,
      'm' || 'cm' || 'mm' => QuantityCategory.length,
      'U' || 'N' => QuantityCategory.number,
      _ => null,
    };
  }

  p.isImported = (p.importerName ?? p.importerAddress) != null ||
      (p.countryOfOrigin != null &&
          !['india', ''].contains(p.countryOfOrigin!.trim().toLowerCase()));
  return p;
}

int _seq = 0;
String _scanId() => '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_seq++}';

/// Deterministic bar-code-only audit.
Future<ComplianceReport> runBarcodeAudit(
  String barcode, {
  LookupConfig lookupConfig = const LookupConfig(),
}) async {
  final code = barcode.trim();
  final gtin = classifyGtin(code);
  final record = await lookupProduct(code, config: lookupConfig);

  final pkg = packageFromRecord(record, gtin);
  final diff = evaluate(pkg, extra: evaluateBarcodeRules(pkg, gtin));
  final score = scoreDiff(diff);
  final recs = generateRecommendations(diff);
  if (!record.found) {
    recs.insert(0,
        '[INFO] This GTIN was not found in any product registry. Findings reflect only what the '
        'bar code itself proves — confirm every mandatory declaration on the physical package.');
  }

  return ComplianceReport(
    scanId: _scanId(),
    timestamp: DateTime.now(),
    source: 'Barcode: $code',
    packageData: pkg,
    diff: diff,
    score: score,
    recommendations: recs,
  );
}

/// Label audit from OCR-derived [PackageData]. Attaches GTIN + registry data
/// when a bar code was also read.
Future<ComplianceReport> runLabelAudit(
  PackageData pkg, {
  String? barcode,
  LookupConfig lookupConfig = const LookupConfig(),
}) async {
  GtinInfo? gtin;
  if (barcode != null && barcode.trim().isNotEmpty) {
    gtin = classifyGtin(barcode.trim());
    pkg
      ..hasBarcode = true
      ..barcodeValue = gtin.digits
      ..barcodeType = gtin.format
      ..barcodeGtinFormat = gtin.format
      ..barcodeChecksumValid = gtin.checksumValid
      ..barcodeValid = gtin.isValid
      ..barcodeIssuingCountry = gtin.issuingCountry
      ..barcodeIsGs1India = gtin.isGs1India
      ..barcodeIsRestricted = gtin.isRestricted;

    final rec = await lookupProduct(gtin.digits, config: lookupConfig);
    pkg
      ..productDataSources = List.of(rec.sources)
      ..productIdentified = rec.found
      ..barcodeRegisteredOwner = rec.brand ?? rec.manufacturerName;
    // fill gaps OCR could not read
    pkg.commodityName ??= rec.productName;
    pkg.manufacturerName ??= rec.manufacturerName;
    pkg.manufacturerAddress ??= rec.manufacturerAddress;
    pkg.countryOfOrigin ??= rec.countryOfOrigin;
    pkg.netQuantityValue ??= rec.netQuantityValue;
    pkg.netQuantityUnit ??= rec.netQuantityUnit;
  }

  final diff = evaluate(
    pkg,
    extra: pkg.hasBarcode ? evaluateBarcodeRules(pkg, gtin) : const [],
  );
  // Image audits do not add unverified-mandatory weight (missing == FAIL).
  final score = scoreDiff(diff, countUnverified: false);
  final recs = generateRecommendations(diff);

  return ComplianceReport(
    scanId: _scanId(),
    timestamp: DateTime.now(),
    source: barcode != null ? 'Label + barcode $barcode' : 'Label photo',
    packageData: pkg,
    diff: diff,
    score: score,
    recommendations: recs,
  );
}
