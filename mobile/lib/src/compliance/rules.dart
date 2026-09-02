/// Dart port of `legal_metrology_ml/layer4_rulebook_engine/rules.py`.
///
/// Each rule takes a [PackageData] and returns a [RuleResult]. Declaration
/// rules are *source-aware*: a missing declaration is a FAIL from an image
/// audit but INCONCLUSIVE from a bar-code-only audit (a database gap is not a
/// label violation).
library;

import 'models.dart';

typedef Rule = RuleResult Function(PackageData pkg);

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

bool _barcodeOnly(PackageData p) => p.analysisSource == AnalysisSource.barcodeRegistry;

RuleResult _visualNa(String id, String name, String ref) => _r(
      id,
      name,
      'NOT_APPLICABLE',
      'MAJOR',
      'Requires visual inspection of the physical label — not determinable from '
          'bar-code registry data alone.',
      0.0,
      legalReference: ref,
    );

RuleResult _absent(
  PackageData p,
  String id,
  String name,
  String severity,
  double weight,
  String what,
  String ref,
) {
  if (_barcodeOnly(p)) {
    return _r(id, name, 'INCONCLUSIVE', severity,
        '$what is not carried in the bar-code registry data. It may still be '
        'printed on the pack — verify against the physical label.',
        weight,
        legalReference: ref);
  }
  return _r(id, name, 'FAIL', severity, '$what is missing from the label.', weight,
      legalReference: ref);
}

bool _has(String? s) => s != null && s.trim().isNotEmpty;

// ── Rule 3 — retail scope ────────────────────────────────────────────────────
RuleResult checkScope(PackageData p) {
  if (p.packageType == PackageType.wholesale) {
    return _r('R03_SCOPE', 'Retail Scope (Rule 3)', 'NOT_APPLICABLE', 'MINOR',
        'Wholesale package — retail chapter does not apply.', 0.0);
  }
  final q = p.netQuantityValue;
  final u = (p.netQuantityUnit ?? '').toLowerCase();
  if (q != null && q > 25 && ['kg', 'l', 'litre', 'liter'].contains(u)) {
    return _r('R03_SCOPE', 'Retail Scope (Rule 3)', 'FAIL', 'MAJOR',
        'Net quantity $q $u exceeds the 25 kg/L retail scope limit.', 0.5,
        legalReference: 'Rule 3');
  }
  return _r('R03_SCOPE', 'Retail Scope (Rule 3)', 'PASS', 'MINOR',
      'Package is within retail scope.', 0.25);
}

// ── Rule 6(1)(b) — commodity name ────────────────────────────────────────────
RuleResult checkCommodityName(PackageData p) {
  if (_has(p.commodityName)) {
    return _r('R06_NAME', 'Commodity Name (Rule 6)', 'PASS', 'CRITICAL',
        "Commodity name found: '${p.commodityName}'", 1.0,
        evidence: p.commodityName, legalReference: 'Rule 6(1)(b)');
  }
  return _absent(p, 'R06_NAME', 'Commodity Name (Rule 6)', 'CRITICAL', 1.0,
      'Common/generic name of the commodity', 'Rule 6(1)(b)');
}

// ── Rule 6(1)(a) / Rule 10 — manufacturer / packer / importer name ───────────
RuleResult checkManufacturerInfo(PackageData p) {
  final name = [p.manufacturerName, p.packerName, p.importerName]
      .firstWhere((e) => _has(e), orElse: () => null);
  if (name != null) {
    return _r('R10_MFR_NAME', 'Manufacturer/Packer Name (Rule 10)', 'PASS',
        'CRITICAL', "Name found: '$name'", 1.0,
        evidence: name, legalReference: 'Rule 6(1)(a) / Rule 10');
  }
  return _absent(p, 'R10_MFR_NAME', 'Manufacturer/Packer Name (Rule 10)',
      'CRITICAL', 1.0, 'Name of the manufacturer / packer / importer',
      'Rule 6(1)(a) / Rule 10');
}

// ── Rule 6(1)(a) / Rule 10 — complete address ────────────────────────────────
RuleResult checkCompleteAddress(PackageData p) {
  final addr = [p.manufacturerAddress, p.packerAddress, p.importerAddress]
      .firstWhere((e) => _has(e), orElse: () => null);
  if (addr != null && addr.trim().length > 10) {
    return _r('R10_ADDRESS', 'Complete Address (Rule 10)', 'PASS', 'CRITICAL',
        'Address found on label.', 1.0,
        evidence: addr, legalReference: 'Rule 6(1)(a) / Rule 10');
  }
  return _absent(p, 'R10_ADDRESS', 'Complete Address (Rule 10)', 'CRITICAL', 1.0,
      'Complete address of the manufacturer / packer / importer (with PIN code)',
      'Rule 6(1)(a) / Rule 10');
}

// ── Rule 6(1)(c) / Rule 11 — net quantity ────────────────────────────────────
RuleResult checkNetQuantity(PackageData p) {
  if (p.netQuantityValue != null) {
    return _r('R11_NET_QTY', 'Net Quantity (Rule 11)', 'PASS', 'CRITICAL',
        'Net quantity: ${p.netQuantityValue} ${p.netQuantityUnit ?? ''}'.trim(),
        1.0,
        evidence: '${p.netQuantityValue} ${p.netQuantityUnit ?? ''}'.trim(),
        legalReference: 'Rule 6(1)(c) / Rule 11');
  }
  return _absent(p, 'R11_NET_QTY', 'Net Quantity (Rule 11)', 'CRITICAL', 1.0,
      'Net quantity declaration', 'Rule 6(1)(c) / Rule 11');
}

// ── Rule 13 — unit category ──────────────────────────────────────────────────
RuleResult checkQuantityUnit(PackageData p) {
  if (_has(p.netQuantityUnit) && p.netQuantityCategory != null) {
    return _r('R13_UNITS', 'Quantity Unit (Rule 13)', 'PASS', 'MAJOR',
        "Unit '${p.netQuantityUnit}' (${p.netQuantityCategory!.name}) declared.",
        0.5,
        evidence: p.netQuantityUnit);
  }
  if (_has(p.netQuantityUnit)) {
    return _r('R13_UNITS', 'Quantity Unit (Rule 13)', 'WARNING', 'MAJOR',
        "Unit '${p.netQuantityUnit}' found but category unresolved.", 0.5,
        evidence: p.netQuantityUnit);
  }
  return _absent(p, 'R13_UNITS', 'Quantity Unit (Rule 13)', 'MAJOR', 0.5,
      'Standard unit of weight/measure/number for the net quantity',
      'Rule 6(1)(c) / Rule 13');
}

// ── Rule 12 — quantity format ────────────────────────────────────────────────
RuleResult checkQuantityFormat(PackageData p) {
  if (p.netQuantityValue != null && _has(p.netQuantityUnit)) {
    return _r('R12_QTY_FMT', 'Quantity Format (Rule 12)', 'PASS', 'MAJOR',
        'Quantity format appears correct.', 0.5);
  }
  return _r('R12_QTY_FMT', 'Quantity Format (Rule 12)', 'INCONCLUSIVE', 'MAJOR',
      'Cannot verify quantity format without an extracted value and unit.', 0.5,
      legalReference: 'Rule 12');
}

// ── Rule 6(1)(e) / Rule 18 — MRP present ─────────────────────────────────────
RuleResult checkMrpPresent(PackageData p) {
  if (p.mrpValue != null) {
    return _r('R06_MRP', 'MRP Declaration (Rules 6/18)', 'PASS', 'CRITICAL',
        'MRP found: ₹${p.mrpValue!.toStringAsFixed(2)}', 1.0,
        evidence: '₹${p.mrpValue!.toStringAsFixed(2)}',
        legalReference: 'Rule 6(1)(e) / Rule 18');
  }
  return _absent(p, 'R06_MRP', 'MRP Declaration (Rules 6/18)', 'CRITICAL', 1.0,
      'Maximum Retail Price (MRP, inclusive of all taxes)',
      'Rule 6(1)(e) / Rule 18');
}

// ── Rule 6(1)(e) — "inclusive of all taxes" wording ──────────────────────────
RuleResult checkMrpTaxInclusive(PackageData p) {
  if (p.mrpValue == null) {
    return _r('R06_MRP_TAX', 'MRP Tax-Inclusive Wording (Rule 6)', 'INCONCLUSIVE',
        'MAJOR', "No MRP extracted — cannot check the wording.", 0.5,
        legalReference: 'Rule 6(1)(e)');
  }
  if (p.mrpIncludesTax == true) {
    return _r('R06_MRP_TAX', 'MRP Tax-Inclusive Wording (Rule 6)', 'PASS',
        'MAJOR', 'MRP is declared as inclusive of all taxes.', 0.5,
        legalReference: 'Rule 6(1)(e)');
  }
  if (_barcodeOnly(p) || p.mrpIncludesTax == null) {
    return _r('R06_MRP_TAX', 'MRP Tax-Inclusive Wording (Rule 6)', 'INCONCLUSIVE',
        'MAJOR',
        "MRP value known but the 'inclusive of all taxes' wording could not be "
        'verified — check the physical label.',
        0.5,
        legalReference: 'Rule 6(1)(e)');
  }
  return _r('R06_MRP_TAX', 'MRP Tax-Inclusive Wording (Rule 6)', 'FAIL', 'MAJOR',
      "MRP is printed without the mandatory 'inclusive of all taxes' qualifier.",
      0.5,
      legalReference: 'Rule 6(1)(e)');
}

// ── Rule 6 — country of origin (imported packages) ───────────────────────────
RuleResult checkCountryOfOrigin(PackageData p) {
  if (_has(p.countryOfOrigin)) {
    return _r('R06_COO', 'Country of Origin (Rule 6)', 'PASS', 'MAJOR',
        'Country of origin declared: ${p.countryOfOrigin}.', 0.5,
        evidence: p.countryOfOrigin,
        legalReference: 'Rule 6 (imported packages)');
  }
  if (p.isImported) {
    return _r('R06_COO', 'Country of Origin (Rule 6)', 'FAIL', 'MAJOR',
        'Package appears to be imported but the country of origin is not declared.',
        0.5,
        legalReference: 'Rule 6 (imported packages)');
  }
  return _r('R06_COO', 'Country of Origin (Rule 6)', 'NOT_APPLICABLE', 'MINOR',
      'No indication the package is imported — country of origin not mandatory.',
      0.0,
      legalReference: 'Rule 6 (imported packages)');
}

// ── Rule 18 — MRP not altered ────────────────────────────────────────────────
RuleResult checkMrpNotAltered(PackageData p) {
  if (_barcodeOnly(p)) return _visualNa('R18_MRP_ALTER', 'MRP Not Altered (Rule 18)', 'Rule 18');
  if (p.mrpAltered == true) {
    return _r('R18_MRP_ALTER', 'MRP Not Altered (Rule 18)', 'FAIL', 'CRITICAL',
        'MRP appears to have been altered or obscured.', 1.0,
        legalReference: 'Rule 18');
  }
  return _r('R18_MRP_ALTER', 'MRP Not Altered (Rule 18)', 'PASS', 'CRITICAL',
      'MRP appears unaltered.', 1.0);
}

// ── Rule 6(1)(d) — packing date ──────────────────────────────────────────────
RuleResult checkPackingDate(PackageData p) {
  final date = _has(p.manufactureDate) ? p.manufactureDate : p.bestBefore;
  if (_has(date)) {
    return _r('R06_DATE', 'Packing Date (Rule 6)', 'PASS', 'MAJOR',
        'Date found: $date', 0.5, evidence: date, legalReference: 'Rule 6(1)(d)');
  }
  return _absent(p, 'R06_DATE', 'Packing Date (Rule 6)', 'MAJOR', 0.5,
      'Month and year of manufacture / pre-packing / import', 'Rule 6(1)(d)');
}

// ── Rule 6(1)(f) — consumer care ─────────────────────────────────────────────
RuleResult checkConsumerCare(PackageData p) {
  final contact = _has(p.consumerCarePhone) ? p.consumerCarePhone : p.consumerCareEmail;
  if (_has(contact)) {
    return _r('R06_CONSUMER', 'Consumer Care Contact (Rule 6)', 'PASS', 'MAJOR',
        'Consumer care contact found.', 0.5,
        evidence: contact, legalReference: 'Rule 6(1)(f)');
  }
  return _absent(p, 'R06_CONSUMER', 'Consumer Care Contact (Rule 6)', 'MAJOR',
      0.5,
      'Consumer care details (name/designation, address, phone, e-mail)',
      'Rule 6(1)(f)');
}

// ── Rule 9 — legibility (image only) ─────────────────────────────────────────
RuleResult checkLegibility(PackageData p) {
  if (_barcodeOnly(p)) return _visualNa('R09_LEGIBLE', 'Legibility (Rule 9)', 'Rule 9');
  final c = p.averageOcrConfidence;
  if (c == 0.0) {
    return _r('R09_LEGIBLE', 'Legibility (Rule 9)', 'INCONCLUSIVE', 'MAJOR',
        'OCR confidence not available to assess legibility.', 0.5);
  }
  if (c >= 0.4) {
    return _r('R09_LEGIBLE', 'Legibility (Rule 9)', 'PASS', 'MAJOR',
        'Label appears legible (OCR confidence: ${(c * 100).round()}%).', 0.5);
  }
  return _r('R09_LEGIBLE', 'Legibility (Rule 9)', 'FAIL', 'MAJOR',
      'Poor legibility — low OCR confidence (${(c * 100).round()}%).', 0.5,
      legalReference: 'Rule 9');
}

// ── Rule 9 — contrast (image only) ──────────────────────────────────────────
RuleResult checkContrast(PackageData p) {
  if (_barcodeOnly(p)) return _visualNa('R09_CONTRAST', 'Contrast (Rule 9)', 'Rule 9');
  final ratio = p.mrpContrastRatio;
  if (ratio == null) {
    return _r('R09_CONTRAST', 'Contrast (Rule 9)', 'INCONCLUSIVE', 'MAJOR',
        'Contrast ratio not measured.', 0.5);
  }
  if (ratio >= 3.0) {
    return _r('R09_CONTRAST', 'Contrast (Rule 9)', 'PASS', 'MAJOR',
        'Adequate contrast ratio: ${ratio.toStringAsFixed(1)}:1', 0.5);
  }
  return _r('R09_CONTRAST', 'Contrast (Rule 9)', 'FAIL', 'MAJOR',
      'Insufficient contrast ratio: ${ratio.toStringAsFixed(1)}:1 (min 3.0:1).',
      0.5,
      legalReference: 'Rule 9');
}

// ── Rule 9 — language (image only) ──────────────────────────────────────────
RuleResult checkLanguage(PackageData p) {
  if (_barcodeOnly(p)) return _visualNa('R09_LANG', 'Language Requirement (Rule 9)', 'Rule 9');
  if (p.hasHindiText || p.hasEnglishText) {
    final langs = [
      if (p.hasEnglishText) 'English',
      if (p.hasHindiText) 'Hindi',
    ].join(', ');
    return _r('R09_LANG', 'Language Requirement (Rule 9)', 'PASS', 'MAJOR',
        'Declarations found in: $langs.', 0.5);
  }
  return _r('R09_LANG', 'Language Requirement (Rule 9)', 'FAIL', 'MAJOR',
      'No Hindi (Devanagari) or English text detected on the label.', 0.5,
      legalReference: 'Rule 9');
}

// ── Rule 9 — font size (image only) ─────────────────────────────────────────
RuleResult checkFontSize(PackageData p) {
  if (_barcodeOnly(p)) return _visualNa('R07_FONT', 'Font Size (Rule 9)', 'Rule 9');
  final mrpH = p.mrpFontHeightMm;
  final qtyH = p.netQtyFontHeightMm;
  if (mrpH == null && qtyH == null) {
    return _r('R07_FONT', 'Font Size (Rule 9)', 'INCONCLUSIVE', 'MAJOR',
        'Font size not measured (provide package height for calibration).', 0.5);
  }
  final area = p.principalDisplayPanelAreaMm2;
  var minH = 1.0;
  if (area != null) {
    final cm2 = area / 100.0;
    if (cm2 > 100 && cm2 <= 500) {
      minH = 2.0;
    } else if (cm2 > 500) {
      minH = 4.0;
    }
  }
  final failures = <String>[];
  if (mrpH != null && mrpH < minH) {
    failures.add('MRP font ${mrpH.toStringAsFixed(2)}mm < ${minH}mm');
  }
  if (qtyH != null && qtyH < minH) {
    failures.add('Net qty font ${qtyH.toStringAsFixed(2)}mm < ${minH}mm');
  }
  if (failures.isNotEmpty) {
    return _r('R07_FONT', 'Font Size (Rule 9)', 'FAIL', 'MAJOR',
        failures.join('; '), 0.5,
        legalReference: 'Rule 9');
  }
  return _r('R07_FONT', 'Font Size (Rule 9)', 'PASS', 'MAJOR',
      'Font sizes meet the minimum requirement (>= ${minH}mm).', 0.5);
}

/// The full rulebook.
const List<Rule> allRules = [
  checkScope,
  checkCommodityName,
  checkManufacturerInfo,
  checkCompleteAddress,
  checkNetQuantity,
  checkQuantityUnit,
  checkQuantityFormat,
  checkMrpPresent,
  checkMrpTaxInclusive,
  checkCountryOfOrigin,
  checkMrpNotAltered,
  checkPackingDate,
  checkConsumerCare,
  checkLegibility,
  checkContrast,
  checkLanguage,
  checkFontSize,
];
