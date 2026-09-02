/// Dart port of `legal_metrology_ml/layer4_rulebook_engine/barcode_rules.py`.
///
/// Bar-code / GS1 integrity checks (B01–B06) that complement the declaration
/// rules when auditing from a bar code.
library;

import 'gs1.dart';
import 'models.dart';

RuleResult _r(
  String id,
  String name,
  String status,
  String severity,
  String detail,
  double weight, {
  String? evidence,
  String? legalReference,
}) =>
    RuleResult(
      ruleId: id,
      ruleName: name,
      status: status,
      severity: severity,
      detail: detail,
      weight: weight,
      evidence: evidence,
      legalReference: legalReference,
    );

RuleResult _b01(PackageData p, GtinInfo? g) {
  if (!p.hasBarcode || (p.barcodeValue ?? '').isEmpty) {
    return _r('B01_GTIN_STRUCT', 'Bar Code Structure (Rule 6(10))',
        'NOT_APPLICABLE', 'MINOR', 'No bar code was scanned or supplied.', 0.0,
        legalReference: 'Rule 6(10)');
  }
  final fmt = p.barcodeGtinFormat ?? g?.format;
  if (fmt != null) {
    return _r('B01_GTIN_STRUCT', 'Bar Code Structure (Rule 6(10))', 'PASS',
        'MINOR', 'Bar code is a valid $fmt number.', 0.25,
        evidence: p.barcodeValue, legalReference: 'Rule 6(10)');
  }
  return _r('B01_GTIN_STRUCT', 'Bar Code Structure (Rule 6(10))', 'FAIL', 'MAJOR',
      "'${p.barcodeValue}' is not a valid GTIN length (expected 8, 12, 13 or 14 digits).",
      0.5,
      evidence: p.barcodeValue, legalReference: 'Rule 6(10)');
}

RuleResult _b02(PackageData p, GtinInfo? g) {
  final valid = p.barcodeChecksumValid ?? g?.checksumValid;
  if (valid == null) {
    return _r('B02_GTIN_CHECKSUM', 'Bar Code Check Digit (Rule 6(10))',
        'INCONCLUSIVE', 'MINOR', 'Check digit could not be evaluated.', 0.25,
        legalReference: 'Rule 6(10)');
  }
  if (valid) {
    return _r('B02_GTIN_CHECKSUM', 'Bar Code Check Digit (Rule 6(10))', 'PASS',
        'MINOR',
        'GS1 mod-10 check digit matches — the number is internally consistent.',
        0.25,
        evidence: p.barcodeValue, legalReference: 'Rule 6(10)');
  }
  return _r('B02_GTIN_CHECKSUM', 'Bar Code Check Digit (Rule 6(10))', 'FAIL',
      'MAJOR',
      'GS1 check digit is wrong — the bar code number is mistyped or misprinted.',
      0.5,
      evidence: p.barcodeValue, legalReference: 'Rule 6(10)');
}

RuleResult _b03(PackageData p, GtinInfo? g) {
  if ((p.barcodeValue ?? '').isEmpty) {
    return _r('B03_GTIN_SCOPE', 'Bar Code Is a Trade Item (Rule 6(10))',
        'NOT_APPLICABLE', 'MINOR', 'No bar code supplied.', 0.0,
        legalReference: 'Rule 6(10)');
  }
  final restricted = p.barcodeIsRestricted ?? g?.isRestricted ?? false;
  if (restricted) {
    return _r('B03_GTIN_SCOPE', 'Bar Code Is a Trade Item (Rule 6(10))', 'FAIL',
        'MAJOR',
        'Bar code uses a reserved prefix (${g?.restrictedReason ?? 'restricted range'}); '
        'it does not identify a consumer package and must not be printed as the product GTIN.',
        0.5,
        evidence: p.barcodeValue, legalReference: 'Rule 6(10)');
  }
  return _r('B03_GTIN_SCOPE', 'Bar Code Is a Trade Item (Rule 6(10))', 'PASS',
      'MINOR', 'Bar code prefix is in the normal GTIN range for trade items.',
      0.25,
      legalReference: 'Rule 6(10)');
}

RuleResult _b04(PackageData p, GtinInfo? g) {
  final country = p.barcodeIssuingCountry ?? g?.issuingCountry;
  final india = p.barcodeIsGs1India ?? g?.isGs1India ?? false;
  if (country == null) {
    return _r('B04_GS1_AUTHORITY', 'GS1 Issuing Authority', 'WARNING', 'MINOR',
        'GS1 prefix does not map to any known member organisation.', 0.25);
  }
  if (india) {
    return _r('B04_GS1_AUTHORITY', 'GS1 Issuing Authority', 'PASS', 'MINOR',
        'Prefix 890 — the bar code number is licensed through GS1 India, '
        'consistent with a package manufactured or packed in India.',
        0.25,
        evidence: 'GS1 India (890)');
  }
  return _r('B04_GS1_AUTHORITY', 'GS1 Issuing Authority', 'PASS', 'MINOR',
      'Bar code number is licensed through the GS1 organisation for: $country.',
      0.25,
      evidence: country);
}

RuleResult _b05(PackageData p, GtinInfo? g) {
  final sources = p.productDataSources;
  if (p.productIdentified) {
    return _r('B05_REGISTRY_ID', 'Registry Identification (Rule 6(1)(a))', 'PASS',
        'MAJOR',
        'GTIN resolved in: ${sources.join(', ')}. Brand owner / product is on public record.',
        0.5,
        evidence: p.barcodeRegisteredOwner, legalReference: 'Rule 6(1)(a)');
  }
  return _r('B05_REGISTRY_ID', 'Registry Identification (Rule 6(1)(a))',
      'WARNING', 'MAJOR',
      'GTIN is structurally valid but is not listed in GS1 India, Open Food '
      'Facts or the other registries checked — the manufacturer/packer '
      'declaration cannot be independently corroborated from the bar code. '
      'Verify against the physical label.',
      0.5,
      legalReference: 'Rule 6(1)(a)');
}

RuleResult _b06(PackageData p, GtinInfo? g) {
  final declared = (p.countryOfOrigin ?? '').trim();
  final prefixCountry = p.barcodeIssuingCountry ?? g?.issuingCountry;
  if (declared.isEmpty) {
    return _r('B06_ORIGIN_CONSISTENCY', 'Origin vs GS1 Prefix Cross-check',
        'NOT_APPLICABLE', 'MINOR',
        'No country of origin available to cross-check against the GS1 prefix.',
        0.0,
        legalReference: 'Rule 6');
  }
  if (prefixCountry != null &&
      !declared.toLowerCase().contains(prefixCountry.toLowerCase()) &&
      !prefixCountry.toLowerCase().contains(declared.toLowerCase())) {
    return _r('B06_ORIGIN_CONSISTENCY', 'Origin vs GS1 Prefix Cross-check',
        'WARNING', 'MINOR',
        "Declared origin '$declared' differs from the GS1 licensing economy "
        "'$prefixCountry'. The GS1 prefix is not proof of origin; confirm against the label.",
        0.25,
        evidence: 'declared=$declared; prefix=$prefixCountry',
        legalReference: 'Rule 6');
  }
  return _r('B06_ORIGIN_CONSISTENCY', 'Origin vs GS1 Prefix Cross-check', 'PASS',
      'MINOR',
      "Declared origin '$declared' is consistent with the GS1 licensing economy.",
      0.25,
      evidence: declared, legalReference: 'Rule 6');
}

List<RuleResult> evaluateBarcodeRules(PackageData p, GtinInfo? g) => [
      _b01(p, g),
      _b02(p, g),
      _b03(p, g),
      _b04(p, g),
      _b05(p, g),
      _b06(p, g),
    ];
