/// Dart port of `legal_metrology_ml/layer2_data_normalization/schema.py`.
///
/// Only the fields the on-device audit uses are kept; the visual/font metrics
/// that need a calibrated image are retained as nullable so the label pipeline
/// can populate them later.
library;

enum QuantityCategory { weight, volume, length, area, number }

enum PackageType { retail, wholesale, export }

/// How a [PackageData] record was assembled — drives source-aware rules.
enum AnalysisSource { image, barcodeRegistry, llmVision }

class PackageData {
  // Identity (Rule 6(1)(b))
  String? commodityName;

  // Manufacturer / packer / importer (Rule 6(1)(a) / Rule 10)
  String? manufacturerName;
  String? manufacturerAddress;
  String? packerName;
  String? packerAddress;
  String? importerName;
  String? importerAddress;
  String? countryOfOrigin;

  // Net quantity (Rules 11-13)
  double? netQuantityValue;
  String? netQuantityUnit;
  QuantityCategory? netQuantityCategory;

  // MRP (Rule 6(1)(e) / Rule 18)
  double? mrpValue;
  String? mrpCurrency;
  bool? mrpIncludesTax;
  bool? mrpAltered;

  // Dates (Rule 6(1)(d))
  String? manufactureDate;
  String? expiryDate;
  String? bestBefore;

  // Consumer care (Rule 6(1)(f))
  String? consumerCareName;
  String? consumerCarePhone;
  String? consumerCareEmail;
  String? consumerCareAddress;

  // Symbols
  String? fssaiLicenseNumber;
  bool hasFssaiLogo = false;
  bool hasVegNonVegSymbol = false;

  // Bar code / GTIN
  bool hasBarcode = false;
  String? barcodeValue;
  String? barcodeType;
  bool? barcodeValid;
  String? barcodeGtinFormat;
  bool? barcodeChecksumValid;
  bool? barcodeIsGs1India;
  bool? barcodeIsRestricted;
  String? barcodeIssuingCountry;
  String? barcodeRegisteredOwner;

  // Visual metrics (label pipeline only)
  double? mrpFontHeightMm;
  double? netQtyFontHeightMm;
  double? mrpContrastRatio;
  double? principalDisplayPanelAreaMm2;
  bool declarationsOnPrincipalPanel = false;

  // Language (Rule 9)
  bool hasHindiText = false;
  bool hasEnglishText = false;

  // Package meta
  bool isImported = false;
  PackageType packageType = PackageType.retail;

  // OCR quality
  double averageOcrConfidence = 0.0;
  int totalTextBlocks = 0;

  // Provenance
  AnalysisSource analysisSource = AnalysisSource.image;
  List<String> productDataSources = [];
  Map<String, String> dataProvenance = {};
  bool productIdentified = false;
}

/// Result of one compliance rule.
class RuleResult {
  final String ruleId;
  final String ruleName;
  final String status; // PASS | FAIL | WARNING | NOT_APPLICABLE | INCONCLUSIVE
  final String severity; // CRITICAL | MAJOR | MINOR
  final String detail;
  final double weight;
  final String? evidence;
  final String? legalReference;

  const RuleResult({
    required this.ruleId,
    required this.ruleName,
    required this.status,
    required this.severity,
    required this.detail,
    required this.weight,
    this.evidence,
    this.legalReference,
  });

  Map<String, dynamic> toJson() => {
        'rule_id': ruleId,
        'rule_name': ruleName,
        'status': status,
        'severity': severity,
        'detail': detail,
        'weight': weight,
        'evidence': evidence,
        'legal_reference': legalReference,
      };
}

class ComplianceDiff {
  final List<RuleResult> passed;
  final List<RuleResult> failed;
  final List<RuleResult> warnings;
  final List<RuleResult> notApplicable;
  final List<RuleResult> inconclusive;

  const ComplianceDiff({
    this.passed = const [],
    this.failed = const [],
    this.warnings = const [],
    this.notApplicable = const [],
    this.inconclusive = const [],
  });

  int get totalRules =>
      passed.length +
      failed.length +
      warnings.length +
      notApplicable.length +
      inconclusive.length;

  List<RuleResult> get all =>
      [...passed, ...failed, ...warnings, ...notApplicable, ...inconclusive];
}

class ComplianceScore {
  final double finalScore; // 0..1
  final int starRating; // 1..5
  final String starLabel;
  final int totalApplicableRules;
  final int passedRules;
  final int failedRules;
  final int criticalFailures;
  final int majorFailures;
  final int minorFailures;

  const ComplianceScore({
    required this.finalScore,
    required this.starRating,
    required this.starLabel,
    required this.totalApplicableRules,
    required this.passedRules,
    required this.failedRules,
    required this.criticalFailures,
    required this.majorFailures,
    required this.minorFailures,
  });
}

class ComplianceReport {
  final String scanId;
  final DateTime timestamp;
  final String source; // human label
  final PackageData packageData;
  final ComplianceDiff diff;
  final ComplianceScore score;
  final List<String> recommendations;

  const ComplianceReport({
    required this.scanId,
    required this.timestamp,
    required this.source,
    required this.packageData,
    required this.diff,
    required this.score,
    required this.recommendations,
  });
}
